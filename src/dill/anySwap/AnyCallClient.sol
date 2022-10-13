// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

abstract contract PausableControl {
    mapping(bytes32 => bool) private _pausedRoles;

    bytes32 public constant PAUSE_ALL_ROLE = 0x00;

    event Paused(bytes32 role);
    event Unpaused(bytes32 role);

    modifier whenNotPaused(bytes32 role) {
        require(
            !paused(role) && !paused(PAUSE_ALL_ROLE),
            "PausableControl: paused"
        );
        _;
    }

    modifier whenPaused(bytes32 role) {
        require(
            paused(role) || paused(PAUSE_ALL_ROLE),
            "PausableControl: not paused"
        );
        _;
    }

    function paused(bytes32 role) public view virtual returns (bool) {
        return _pausedRoles[role];
    }

    function _pause(bytes32 role) internal virtual whenNotPaused(role) {
        _pausedRoles[role] = true;
        emit Paused(role);
    }

    function _unpause(bytes32 role) internal virtual whenPaused(role) {
        _pausedRoles[role] = false;
        emit Unpaused(role);
    }
}

abstract contract PausableControlWithAdmin is PausableControl, AdminControl {
    constructor(address _admin) AdminControl(_admin) {}

    function pause(bytes32 role) external onlyAdmin {
        _pause(role);
    }

    function unpause(bytes32 role) external onlyAdmin {
        _unpause(role);
    }
}

/// three level architecture
/// top level is the `AnycallClient` which the users interact with (through UI or tools)
/// middle level is `AnyswapToken` which works as handlers and vaults for tokens
/// bottom level is the `AnycallProxy` which complete the cross-chain interaction

interface IApp {
    function anyExecute(bytes calldata _data)
        external
        returns (bool success, bytes memory result);
}

interface IAnyswapToken {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function withdraw(uint256 amount, address to) external returns (uint256);
}

interface IAnycallExecutor {
    function context()
        external
        returns (
            address from,
            uint256 fromChainID,
            uint256 nonce
        );
}

interface IAnycallV6Proxy {
    function executor() external view returns (address);

    function anyCall(
        address _to,
        bytes calldata _data,
        address _fallback,
        uint256 _toChainID,
        uint256 _flags
    ) external payable;

    function calcSrcFees(
        string calldata _appID,
        uint256 _toChainID,
        uint256 _dataLength
    ) external view returns (uint256);
}

interface ISidechainGaugeProxy {
    function sendRewards(
        uint256 periodId,
        uint256 amount,
        int256[] memory weights
    ) external;
}

abstract contract AnycallClientBase is IApp, PausableControlWithAdmin {
    address public callProxy;
    address public executor;

    // associated client app on each chain
    mapping(uint256 => address) public clientPeers; // key is chainId

    modifier onlyExecutor() {
        require(msg.sender == executor, "AnycallClient: onlyExecutor");
        _;
    }

    constructor(address _admin, address _callProxy)
        PausableControlWithAdmin(_admin)
    {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallV6Proxy(callProxy).executor();
    }

    receive() external payable {
        require(
            msg.sender == callProxy,
            "AnycallClient: receive from forbidden sender"
        );
    }

    function setCallProxy(address _callProxy) external onlyAdmin {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallV6Proxy(callProxy).executor();
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
}

contract AnyswapTokenAnycallClient is AnycallClientBase {
    using SafeERC20 for IERC20;

    address public distributor;

    // pausable control roles
    bytes32 public constant PAUSE_SWAPOUT_ROLE =
        keccak256("PAUSE_SWAPOUT_ROLE");
    bytes32 public constant PAUSE_SWAPIN_ROLE = keccak256("PAUSE_SWAPIN_ROLE");
    bytes32 public constant PAUSE_FALLBACK_ROLE =
        keccak256("PAUSE_FALLBACK_ROLE");

    uint256 public ANYCALL_FLAGS = 2; // Fee on SRC (mainnet) chain
    string public APP_ID = "0"; // Could be changed

    // associated tokens on each chain
    mapping(address => mapping(uint256 => address)) public tokenPeers;

    event LogSwapout(
        address indexed token,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 toChainId,
        int256[] weights
    );
    event LogSwapin(
        address indexed token,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 fromChainId,
        int256[] weights
    );
    event LogSwapoutFail(
        address indexed token,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        uint256 toChainId,
        int256[] weights
    );

    modifier onlyDistributor() {
        require(msg.sender == distributor, "AnycallClient: onlyDistributor");
        _;
    }

    constructor(
        address _admin,
        address _callProxy,
        address _distributor
    ) AnycallClientBase(_admin, _callProxy) {
        distributor = _distributor;
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

    function setDistributor(address _distributor) external onlyAdmin {
        require(_distributor != address(0));
        distributor = _distributor;
    }

    /// @dev Call by the user to submit a request for a cross chain interaction
    function bridge(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId
    ) external payable //onlyDistributor whenNotPaused(PAUSE_SWAPOUT_ROLE) 
    {
        address clientPeer = clientPeers[toChainId];
        require(clientPeer != address(0), "AnycallClient: no dest client");

        address dstToken = tokenPeers[token][toChainId];
        require(dstToken != address(0), "AnycallClient: no dest token");

        uint256 oldCoinBalance;
        if (msg.value > 0) {
            oldCoinBalance = address(this).balance - msg.value;
        }

        address _underlying = _getUnderlying(token);
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
            assert(IAnyswapToken(token).burn(msg.sender, amount));
        }

        bytes memory data = abi.encodeWithSelector(
            this.anyExecute.selector,
            token,
            dstToken,
            amount,
            msg.sender,
            receiver,
            toChainId,
            weights,
            periodId
        );
        IAnycallV6Proxy(callProxy).anyCall{value: msg.value}(
            clientPeer,
            data,
            address(this),
            toChainId,
            ANYCALL_FLAGS
        );

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

    /// @notice Call by `AnycallProxy` to execute a cross chain interaction on the destination chain
    function anyExecute(bytes calldata data)
        external
        override
            onlyExecutor
            whenNotPaused(PAUSE_SWAPIN_ROLE)
        returns (
            bool success,
            bytes memory result
        )
    {
        bytes4 selector = bytes4(data[:4]);
        if (selector == this.anyExecute.selector) {
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
                    data[4:],
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

            (address from, uint256 fromChainId, ) = IAnycallExecutor(executor)
                .context();
            require(
                clientPeers[fromChainId] == from,
                "AnycallClient: wrong context"
            );
            require(
                tokenPeers[dstToken][fromChainId] == srcToken,
                "AnycallClient: mismatch source token"
            );

            address _underlying = _getUnderlying(dstToken);

       
             if (
                _underlying != address(0) &&
                (IERC20(_underlying).balanceOf(dstToken) >= amount)
            ) {
                IAnyswapToken(dstToken).mint(address(this), amount);
                IAnyswapToken(dstToken).withdraw(amount, receiver);
            } else {
                assert(IAnyswapToken(dstToken).mint(receiver, amount));
            }

            // IERC20(dstToken).safeApprove(receiver, amount);
            ISidechainGaugeProxy(receiver).sendRewards(
                periodId,
                amount,
                weights
            );

            emit LogSwapin(
                dstToken,
                sender,
                receiver,
                amount,
                fromChainId,
                weights
            );
        } else if (selector == 0xa35fe8bf) {
            // bytes4(keccak256('anyFallback(address,bytes)'))
            (address _to, bytes memory _data) = abi.decode(
                data[4:],
                (address, bytes)
            );
            anyFallback(_to, _data);
        } else {
            return (false, "unknown selector");
        }
        return (true, "");
    }

    /// @dev Call back by `AnycallProxy` on the originating chain if the cross chain interaction fails
    function anyFallback(address to, bytes memory data)
        internal
        whenNotPaused(PAUSE_FALLBACK_ROLE)
    {
        (address _from, , ) = IAnycallExecutor(executor).context();
        require(_from == address(this), "AnycallClient(fallback): wrong context");

        (
            bytes4 selector,
            address srcToken,
            address dstToken,
            uint256 amount,
            address from,
            address receiver,
            uint256 toChainId,
            int256[] memory weights
        ) = abi.decode(
                data,
                (
                    bytes4,
                    address,
                    address,
                    uint256,
                    address,
                    address,
                    uint256,
                    int256[]
                )
            );

        require(
            selector == this.anyExecute.selector,
            "AnycallClient: wrong fallback data"
        );
        require(
            clientPeers[toChainId] == to,
            "AnycallClient: mismatch dest client"
        );
        require(
            tokenPeers[srcToken][toChainId] == dstToken,
            "AnycallClient: mismatch dest token"
        );

        address _underlying = _getUnderlying(srcToken);

        if (
            _underlying != address(0) &&
            (IERC20(srcToken).balanceOf(address(this)) >= amount)
        ) {
            IERC20(_underlying).safeTransferFrom(address(this), from, amount);
        } else {
            assert(IAnyswapToken(srcToken).mint(from, amount));
        }

        emit LogSwapoutFail(
            srcToken,
            from,
            receiver,
            amount,
            toChainId,
            weights
        );
    }

    function calcFees(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId
    ) external view returns (uint256) {
        address dstToken = tokenPeers[token][toChainId];
        require(dstToken != address(0), "AnycallClient: no dest token");

        bytes memory data = abi.encodeWithSelector(
            this.anyExecute.selector,
            token,
            dstToken,
            amount,
            msg.sender,
            receiver,
            toChainId,
            weights,
            periodId
        );

        return
            IAnycallV6Proxy(callProxy).calcSrcFees(
                APP_ID,
                toChainId,
                data.length
            );
    }

    function _getUnderlying(address token) internal returns (address) {
        (bool success, bytes memory returndata) = token.call(
            abi.encodeWithSelector(0x6f307dc3)
        );
        if (success && returndata.length > 0) {
            address _underlying = abi.decode(returndata, (address));
            return _underlying;
        }
        return address(0);
    }
    function testWoring(uint256 flag) external returns(uint256 f){
        f = flag;
    }
}
