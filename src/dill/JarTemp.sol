// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/**
Temporary contract to interact with Virtual Gauge
 */
 
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {VirtualGaugeV2} from "./gauges/VirtualGaugeV2.sol";
interface iVGauge {
    function depositFor(uint256 _amount, address _account) external;

    function depositForAndLock(
        uint256 amount,
        address account,
        uint256 secs,
        bool isPermanentlyLocked
    ) external;

    function balanceOf(address account) external view returns (uint256);

    function withdrawAll(address account) external returns (uint256 amount);

    function withdrawNonStaked(address account, uint256 index)
        external
        returns (uint256);
    
    function withdrawUnlockedStake(address account)
        external
        returns (uint256);

    function notifyRewardAmount(uint256[] memory rewards) external;

    function getReward(address account) external returns(uint256 _rewardsForJar);

    function unlockStakeForAccount(address account) external;

    function exit(address account) external;
    
}

contract JarTemp {
    using SafeERC20 for IERC20;

    // address public virtualGauge;
    iVGauge private _vGauge;
    IERC20 public constant PICKLE =
        IERC20(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5);

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply = 0;
    bool private _isJarSet;

    constructor() public {
        _isJarSet = false;
    }

    function setVirtualGauge(address _virtualGauge) public {
        _vGauge = iVGauge(_virtualGauge);
        _isJarSet = true;
    }

    function getVirtualGauge() public view returns (address) {
        require(_isJarSet, "set jar first");
        return address(_vGauge);
    }

    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function depositForByJar(uint256 _amount, address _account) public {
        require(_isJarSet, "set jar first");
        _vGauge.depositFor(_amount, _account);
        PICKLE.safeTransferFrom(_account, address(this), _amount);
        _balances[_account] += _amount;
        _totalSupply += _amount;
    }

    function depositForAndLockByJar(
        uint256 _amount,
        address _account,
        uint256 _sec,
        bool _isPermanentlyLocked
    ) public {
        require(_isJarSet, "set jar first");
        _vGauge.depositForAndLock(
            _amount,
            _account,
            _sec,
            _isPermanentlyLocked
        );
        PICKLE.safeTransferFrom(_account, address(this), _amount);
        _balances[_account] += _amount;
        _totalSupply += _amount;
    }

    function withdrawNonStakedByJar(address _account, uint256 _index)
        public
        returns (uint256)
    {
        require(_isJarSet, "set jar first");
        uint256 _amount = _vGauge.withdrawNonStaked(_account, _index);
        _balances[_account] -= _amount;
        _totalSupply -= _amount;
        PICKLE.safeTransfer(_account, _amount);
        return _amount;
    }

    function withdrawUnlockedStakedByJar(address _account)
        public
        returns (uint256)
    {
        require(_isJarSet, "set jar first");
        uint256 _amount = _vGauge.withdrawUnlockedStake(_account);
        _balances[_account] -= _amount;
        _totalSupply -= _amount;
        PICKLE.safeTransfer(_account, _amount);
        return _amount;
    }

    function withdrawAllByJar(address _account)
        public
        returns (uint256 amount)
    {
        require(_isJarSet, "set jar first");
        uint256 _amount = _vGauge.withdrawAll(_account);
        _balances[_account] -= _amount;
        _totalSupply -= _amount;
        PICKLE.safeTransfer(_account, _amount);
        return _amount;
    }

    function getBalanceOf(address _account) external view returns (uint256) {
        require(_isJarSet, "set jar first");
        return _vGauge.balanceOf(_account);
    }

    function getRewardByJar(address account) public returns(uint256){
        uint256 reward = _vGauge.getReward(account);
        // PICKLE.safeTransfer(account, reward);
        return reward;
    }

    function unlockStakeForAccountByJar(address _account) public {
        _vGauge.unlockStakeForAccount(_account);
    }

    function exitByJar(address account) external {
        getRewardByJar(account);
        withdrawAllByJar(account);
    }
}