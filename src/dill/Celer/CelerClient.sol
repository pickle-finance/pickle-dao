// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./framework/MessageApp.sol";

abstract contract AdminControl {
    address public admin;
    address public pendingAdmin;

    event ChangeAdmin(address indexed _old, address indexed _new);
    event ApplyAdmin(address indexed _old, address indexed _new);

    constructor(address _admin) {
        require(_admin != address(0), "AdminControl: address(0)");
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "AdminControl: not admin");
        _;
    }

    function changeAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "AdminControl: address(0)");
        pendingAdmin = _admin;
        emit ChangeAdmin(admin, _admin);
    }

    function applyAdmin() external {
        require(msg.sender == pendingAdmin, "AdminControl: Forbidden");
        emit ApplyAdmin(admin, pendingAdmin);
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }
}

interface ICelerToken {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function withdraw(uint256 amount, address to) external returns (uint256);

    function underlying() external returns (address);
}

interface ISidechainGaugeProxy {
    function sendRewards(
        uint256 periodId,
        uint256 amount,
        int256[] memory weights
    ) external;
}

contract CelerClient is MessageApp, AdminControl {
    using SafeERC20 for IERC20;

    address public distributor;
    mapping(address => mapping(uint256 => address)) public tokenPeers;
    mapping(uint256 => address) public clientPeers;

    event LogSwapout(
        address indexed token,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 toChainId,
        int256[] weights
    );
     event MessageReceived(
        address srcContract,
        uint64 srcChainId,
        address sender,
        bytes message
    );

    event LogSwapoutFail(
        address indexed token,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 toChainId,
        int256[] weights
    );

    constructor(address _messageBus)
        MessageApp(_messageBus)
        AdminControl(msg.sender)
    {}

    modifier onlyDistributor() {
        require(msg.sender == distributor, "CelerCLient: onlyDistributor");
        _;
    }

    function setTokenPeers(
        address srcToken,
        uint256[] calldata chainIds,
        address[] calldata dstTokens
    ) external onlyAdmin {
        require(chainIds.length == dstTokens.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            tokenPeers[srcToken][chainIds[i]] = dstTokens[i];
        }
    }

    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peers
    ) external onlyAdmin {
        require(_chainIds.length == _peers.length);
        for (uint256 i = 0; i < _chainIds.length; i++) {
            clientPeers[_chainIds[i]] = _peers[i];
        }
    }

    function setDistributor(address _distributor) external onlyAdmin {
        require(_distributor != address(0));
        distributor = _distributor;
    }

    function mintCelerToken(address token) external {
        ICelerToken(token).mint(address(this), 100000);
    }

    /**
    @dev Call by the user to submit a request for a cross chain interaction
    @param token : address of celer token 
    @param amount : amount to be bridge 
    @param receiver : receiver of the token on destination chain
    @param toChainId : chain id of destination chain
    @param weights : weigths of the the guages
    @param periodId : current period id
     */

    function bridge(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId
    ) external payable {
        address clientPeer = clientPeers[toChainId];
        require(clientPeer != address(0), "CelerCLient: no dest client");

        address dstToken = tokenPeers[token][toChainId];
        require(dstToken != address(0), "CelerCLient: no dest token");

        uint256 oldCoinBalance;
        if (msg.value > 0) {
            oldCoinBalance = address(this).balance - msg.value;
        }

        address _underlying = ICelerToken(token).underlying();

        if (
            _underlying != address(0) &&
            IERC20(token).balanceOf(msg.sender) < amount
        ) {
            uint256 old_balance = IERC20(_underlying).balanceOf(token);
            IERC20(_underlying).safeTransferFrom(msg.sender, token, amount);
            uint256 new_balance = IERC20(_underlying).balanceOf(token);
            // update amount to real balance increasement (some token may deduct fees)
            amount = new_balance > old_balance ? new_balance - old_balance : 0;
        } else {
            assert(ICelerToken(token).burn(msg.sender, amount));
        }

        bytes memory data = abi.encode(
            token,
            dstToken,
            amount,
            msg.sender,
            receiver,
            weights,
            periodId
        );
        sendMessage(clientPeer, uint64(toChainId), data, msg.value);
        if (msg.value > 0) {
            uint256 newCoinBalance = address(this).balance;
            if (newCoinBalance > oldCoinBalance) {
                // return remaining fees
                (bool success, ) = msg.sender.call{
                    value: newCoinBalance - oldCoinBalance
                }("");
                require(success);
            }
        }

        emit LogSwapout(
            token,
            msg.sender,
            receiver,
            amount,
            toChainId,
            weights
        );
    }

    /**
     * @notice Called by MessageBus to execute a message with an associated token transfer.
     * The contract is guaranteed to have received the right amount of tokens before this function is called.
     * @param _srcContract Address of the token from where tokens are bridged
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _data Arbitrary message bytes originated from and encoded by the source app contract
     */

    function executeMessage(
        address _srcContract,
        uint64 _srcChainId,
        bytes calldata _data,
        address // executor
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        (
            address srcToken,
            address dstToken,
            uint256 amount,
            address sender,
            address receiver,
            int256[] memory weights,
            uint256 periodId
        ) = abi.decode(
                _data,
                (
                    address,
                    address,
                    uint256,
                    address,
                    address,
                    int256[],
                    uint256
                )
            );
        require(
            clientPeers[_srcChainId] == _srcContract,
            "CelerCLient: wrong context"
        );
        require(
            tokenPeers[dstToken][_srcChainId] == srcToken,
            "CelerCLient: mismatch source token"
        );

        address _underlying = ICelerToken(dstToken).underlying();

        if (
            _underlying != address(0) &&
            (IERC20(_underlying).balanceOf(dstToken) >= amount)
        ) {
            ICelerToken(dstToken).mint(address(this), amount);
            ICelerToken(dstToken).withdraw(amount, receiver);
        } else {
            assert(ICelerToken(dstToken).mint(receiver, amount));
        }

        //ISidechainGaugeProxy(receiver).sendRewards(periodId, amount, weights);

        emit MessageReceived(_srcContract, _srcChainId, sender, _data);
        return ExecutionStatus.Success;
    }

    function executeMessageWithTransferFallback(
        address, //_sender,
        address, // _token
        uint256, // _amount
        uint64, //_srcChainId,
        bytes calldata _data,
        address // executor
    ) external payable override onlyMessageBus returns (ExecutionStatus) {
        (
            address srcToken,
            address dstToken,
            uint256 amount,
            address sender,
            address receiver,
            uint256 toChainId,
            int256[] memory weights,
            uint256 periodId
        ) = abi.decode(
                _data,
                (
                    address,
                    address,
                    uint256,
                    address,
                    address,
                    uint256,
                    int256[],
                    uint256
                )
            );

        require(
            clientPeers[toChainId] == receiver,
            "AnycallClient: mismatch dest client"
        );
        require(
            tokenPeers[srcToken][toChainId] == dstToken,
            "AnycallClient: mismatch dest token"
        );

        emit LogSwapoutFail(
            srcToken,
            sender,
            receiver,
            amount,
            toChainId,
            weights
        );
        return ExecutionStatus.Fail;
    }
}
