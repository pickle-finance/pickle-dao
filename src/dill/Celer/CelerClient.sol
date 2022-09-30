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

interface ICelerToken {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function withdraw(uint256 amount, address to) external returns (uint256);
}

interface ISidechainGaugeProxy {
    function sendRewards(
        uint256 periodId,
        uint256 amount,
        int256[] memory weights
    ) external;
}

    modifier onlyDistributor() {
        require(msg.sender == distributor, "CelerCLient: onlyDistributor");
        _;
    }

    constructor(address _messageBus) MessageApp(_messageBus) {}

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
    function sendTokenWithNote(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId,
        bytes calldata _note,
        MsgDataTypes.BridgeSendType _bridgeSendType
    ) external payable {
        address clientPeer = clientPeers[toChainId];
        require(clientPeer != address(0), "CelerCLient: no dest client");

        address dstToken = tokenPeers[token][toChainId];
        require(dstToken != address(0), "CelerCLient: no dest token");

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

        bytes memory data = abi.encode(
            token,
            dstToken,
            amount,
            msg.sender,
            receiver,
            toChainId,
            weights,
            periodId
        );
        sendMessageWithTransfer(
            receiver,
            token,
            amount,
            toChainId,
            _nonce, //--->
            _maxSlippage, //--->
            data,
            _bridgeSendType,
            msg.value
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
    }

    /// @notice Call by `AnycallProxy` to execute a cross chain interaction on the destination chain
    function executeMessageWithTransfer(
        address, // srcContract
        address _token,
        uint256 _amount,
        uint64 _srcChainId,
        bytes memory _message,
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

        //(address from, uint256 fromChainId, ) = IAnycallExecutor(executor)
        //    .context();
        require(
            clientPeers[fromChainId] == from,
            "CelerCLient: wrong context"
        );
        require(
            tokenPeers[dstToken][fromChainId] == srcToken,
            "CelerCLient: mismatch source token"
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
        ISidechainGaugeProxy(receiver).sendRewards(periodId, amount, weights);
        emit MessageWithTransferReceived(
            sender,
            _token,
            _amount,
            _srcChainId,
            note
        );
        return ExecutionStatus.Success;
    }
function executeMessageWithTransferFallback(MsgDataTypes.TransferInfo calldata _transfer, bytes calldata _message)
        private
        returns (IMessageReceiverApp.ExecutionStatus)
    {
        uint256 gasLeftBeforeExecution = gasleft();
        (bool ok, bytes memory res) = address(_transfer.receiver).call{value: msg.value}(
            abi.encodeWithSelector(
                IMessageReceiverApp.executeMessageWithTransferFallback.selector,
                _transfer.sender,
                _transfer.token,
                _transfer.amount,
                _transfer.srcChainId,
                _message,
                msg.sender
            )
        );
        if (ok) {
            return abi.decode((res), (IMessageReceiverApp.ExecutionStatus));
        }
        handleExecutionRevert(gasLeftBeforeExecution, res);
        return IMessageReceiverApp.ExecutionStatus.Fail;
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

        bytes memory data = abi.encode(
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
            calcFee(data);
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

    function testWoring(uint256 flag) external returns (uint256 f) {
        f = flag;
    }
}






