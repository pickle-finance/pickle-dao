// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./BaseGaugeV2.sol";

contract GaugeV2 is BaseGaugeV2 {
    using SafeERC20 for IERC20;

    /// @notice Token addresses
    IERC20 public constant PICKLE =
        IERC20(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5);
    address public constant TREASURY =
        address(0x066419EaEf5DE53cc5da0d8702b990c5bc7D1AB3);

    IERC20 public immutable TOKEN;

    uint256 private _totalSupply;

    /* ========== MAPPINGS ========== */
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => bool)) public stakingDelegates; // Delegate tracking

    // /* ========== MODIFIERS ========== */

    modifier updateReward(address account, bool isClaimReward) {
        rewardPerToken();
        lastTimeRewardApplicable();

        if (account != address(0)) {
            uint256[] memory earnedArr = earned(account);
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                rewardTokenDetail memory token = rewardTokenDetails[
                    rewardTokens[i]
                ];
                if (token.isActive) {
                    rewards[account][i] = earnedArr[i];
                    _userRewardPerTokenPaid[account][i] = token
                        .rewardPerTokenStored;
                }
            }
        }
        _;
        if (account != address(0)) {
            kick(account);
            if (isClaimReward) {
                _lastRewardClaimTime[account] = block.timestamp;
            }
        }
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _token,
        address _governance,
        address _gaugeProxy
    ) {
        require(_token == address(0), "Cannot set token to zero address");
        require(_governance == address(0), "Cannot set governance to zero address");
        require(_gaugeProxy == address(0), "Cannot set gaugeProxy to zero address");
        TOKEN = IERC20(_token);
        governance = _governance;
        gaugeProxy = IGaugeProxyV2(_gaugeProxy);
    }

    /* ========== VIEWS ========== */

    /**
     * @notice  Get total supply of TOKENS
     * @return  uint256  Number of tokens (locked + deposited)
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice  Get TOKEN balance of user in this contract (locked + deposited)
     * @param   _account  Address of user whose balance is to be fetched
     * @return  uint256  of user (locked + deposited)
     */
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    /* ========== PUBLIC METHODS ========== */

    /// @notice Calculate reward per token for all reward tokens set
    function rewardPerToken() public {
        if (_totalSupply != 0) {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                rewardTokenDetail memory token = rewardTokenDetails[
                    rewardTokens[i]
                ];
                if (token.isActive) {
                    lastTimeRewardApplicable();
                    rewardTokenDetails[rewardTokens[i]].rewardPerTokenStored =
                        token.rewardPerTokenStored +
                        (((rewardTokenDetails[rewardTokens[i]].lastUpdateTime -
                            token.lastUpdateTime) *
                            token.rewardRate *
                            _MultiplierPrecision) / derivedSupply);
                }
            }
        }
    }

    /**
     * @notice  Get rewards earned by account
     * @param   _account  Address of user whose rewards are to be fetched
     * @return  _newEarned  Array of rewards eraned by user for all reward tokens
     */
    function earned(address _account)
        public
        returns (uint256[] memory _newEarned)
    {
        rewardPerToken();
        _newEarned = new uint256[](rewardTokens.length);

        if (derivedBalances[_account] == 0) {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                _newEarned[i] = 0;
            }
        } else {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                rewardTokenDetail memory token = rewardTokenDetails[
                    rewardTokens[i]
                ];
                if (token.isActive) {
                    _newEarned[i] =
                        ((derivedBalances[_account] *
                            (token.rewardPerTokenStored -
                                _userRewardPerTokenPaid[_account][i])) /
                            _MultiplierPrecision) +
                        rewards[_account][i];
                }
            }
        }
    }

    /**
     * @notice  Set delegate for staking on behalf of user
     * @param   _delegate  Address of delegate
     */
    function setStakingDelegate(address _delegate) public {
        require(
            stakingDelegates[msg.sender][_delegate],
            "Already a staking delegate for user!"
        );
        require(_delegate != msg.sender, "Cannot delegate to self");
        stakingDelegates[msg.sender][_delegate] = true;
    }

    /**
     * @notice  Get calculated derived balance (DillBoosted + LockedBoosted + NFTBoosted) for '_account'
     * @param   _account  Address of user whose derived balance is to be calculated
     * @return  uint256  Calculated derived balance (DillBoosted + LockedBoosted + NFTBoosted)
     */
    function derivedBalance(address _account) public returns (uint256) {
        uint256 _balance = _balances[_account];
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = (((_totalSupply * DILL.balanceOf(_account)) /
            DILL.totalSupply()) * 60) / 100;
        uint256 dillBoostedDerivedBal = Math.min(
            _derived + _adjusted,
            _balance
        );

        LockedStake memory thisStake = _lockedStakes[_account];
        uint256 lock_multiplier = thisStake.lock_multiplier;
        uint256 lastRewardClaimTime = _lastRewardClaimTime[_account];
        // If the lock is expired
        if (
            thisStake.endingTimestamp <= block.timestamp &&
            !thisStake.isPermanentlyLocked
        ) {
            // If the lock expired in the time since the last claim, the weight needs to be proportionately averaged this time
            if (lastRewardClaimTime < thisStake.endingTimestamp) {
                uint256 timeBeforeExpiry = thisStake.endingTimestamp -
                    lastRewardClaimTime;
                uint256 timeAfterExpiry = block.timestamp -
                    thisStake.endingTimestamp;

                // Get the weighted-average lock_multiplier
                uint256 numerator = (lock_multiplier * timeBeforeExpiry) +
                    (_MultiplierPrecision * timeAfterExpiry);
                lock_multiplier =
                    numerator /
                    (timeBeforeExpiry + timeAfterExpiry);
            }
            // Otherwise, it needs to just be 1x
            else {
                lock_multiplier = _MultiplierPrecision;
            }
        } else {
            uint256 elapsedSeconds = block.timestamp - lastRewardClaimTime;
            if (elapsedSeconds > 0) {
                lock_multiplier = thisStake.isPermanentlyLocked
                    ? lockMaxMultiplier
                    : _averageDecayedLockMultiplier(_account, elapsedSeconds);
                _lastUsedMultiplier[_account] =
                    _lastUsedMultiplier[_account] -
                    (elapsedSeconds - 1) *
                    multiplierDecayPerSecond;
            }
        }
        uint256 liquidity = thisStake.liquidity;
        uint256 lockBoostedDerivedBal = (liquidity * lock_multiplier) /
            _MultiplierPrecision;

        uint256 nftBoostedDerivedBalance = 0;
        if (gaugeProxy.isStaked(_account) && gaugeProxy.isBoostable(_account)) {
            uint256 tokenLevel = gaugeProxy.getTokenLevel(_account);
            uint256 nftLockMultiplier = (lockMaxMultiplier -
                (10e17) *
                tokenLevel) / 100;
            nftBoostedDerivedBalance =
                (thisStake.liquidity * nftLockMultiplier) /
                _MultiplierPrecision;
        }
        return
            dillBoostedDerivedBal +
            lockBoostedDerivedBal +
            nftBoostedDerivedBalance;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice  Calculate and update derived balance for '_account' and derived supply
     * @param   _account  Address of user
     */
    function kick(address _account) public {
        uint256 _derivedBalance = derivedBalances[_account];
        derivedSupply = derivedSupply - _derivedBalance;
        _derivedBalance = derivedBalance(_account);
        derivedBalances[_account] = _derivedBalance;
        derivedSupply = derivedSupply + _derivedBalance;
    }

    /// @notice  Deposit all 'TOKEN' balance of user
    function depositAll() external {
        require(TOKEN.balanceOf(msg.sender) > 0, "Cannot deposit 0");
        _deposit(TOKEN.balanceOf(msg.sender), msg.sender, 0, 0, false, true);
    }

    /**
     * @notice  Deposit 'amount' 'TOKEN' on user's behalf
     * @dev     'TOKEN' owner need to approve delegate to deposit token on owner's behalf
     * @param   _amount  Number of 'TOKEN' to be deposited
     * @param   _account  Address of 'TOKEN' owner
     */
    function depositFor(uint256 _amount, address _account) external {
        require(_amount > 0, "Cannot deposit 0");
        require(
            stakingDelegates[_account][msg.sender],
            "Only registerd delegates can deposit for their deligator"
        );
        _deposit(_amount, _account, 0, 0, false, true);
    }

    /// @notice  Deposit '_amount' 'TOKEN'
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Cannot deposit 0");
        _deposit(_amount, msg.sender, 0, 0, false, true);
    }

    /**
     * @notice  Deposit and lock all 'TOKEN' balance of user
     * @param   _secs  Time period to lock tokens
     * @param   _isPermanentlyLocked  Whether or not to lock tokens perma  nently
     */
    function depositAllAndLock(uint256 _secs, bool _isPermanentlyLocked)
        external
        lockable(_secs)
    {
        require(TOKEN.balanceOf(msg.sender) > 0, "Cannot stake 0");
        LockedStake memory thisStake = _lockedStakes[msg.sender];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                    (thisStake.endingTimestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            TOKEN.balanceOf(msg.sender),
            msg.sender,
            _secs,
            block.timestamp,
            _isPermanentlyLocked,
            false
        );
    }

    /**
     * @notice  Deposit and lock 'amount' 'TOKEN' on user's behalf
     * @dev     'TOKEN' owner need to approve Jar or authorised address to deposit token on owner's behalf
     * @param   _amount  Number of tokens to be deposited and locked
     * @param   _account  'TOKEN' owners address
     * @param   _secs  Time period to lock tokens
     * @param   _isPermanentlyLocked  Whether or not lock tokens permanently
     */
    function depositForAndLock(
        uint256 _amount,
        address _account,
        uint256 _secs,
        bool _isPermanentlyLocked
    ) external lockable(_secs) {
        require(_amount > 0, "Cannot stake 0");
        require(
            stakingDelegates[_account][msg.sender],
            "Only registerd delegates can stake for their deligator"
        );
        LockedStake memory thisStake = _lockedStakes[_account];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[_account]) &&
                    (thisStake.endingTimestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            _amount,
            _account,
            _secs,
            block.timestamp,
            _isPermanentlyLocked,
            false
        );
    }

    /**
     * @notice  Deposit and lock 'amount' 'TOKEN' on user's behalf
     * @dev     This method can also be used on existing stake to increase stake amount, lock time or lock permanently e
     * @param   _amount  Number of tokens to be deposited locked
     * @param   _secs  Time period to lock tokens
     * @param   _isPermanentlyLocked  Whether or not lock tokens permanently
     */
    function depositAndLock(
        uint256 _amount,
        uint256 _secs,
        bool _isPermanentlyLocked
    ) external lockable(_secs) {
        require(_amount > 0, "Cannot stake 0");
        LockedStake memory thisStake = _lockedStakes[msg.sender];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                    (thisStake.endingTimestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            _amount,
            msg.sender,
            _secs,
            block.timestamp,
            _isPermanentlyLocked,
            false
        );
    }

    /**
     * @notice  Add tokens from deposit to stake
     * @param   _amount  Number of token to to add to stake from users normal deposit
     */
    function addBalanceToStake(uint256 _amount) external {
        LockedStake memory _lockedStake = _lockedStakes[msg.sender];
        require(
            (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                _lockedStake.endingTimestamp > block.timestamp,
            "No stake found"
        );
        require(
            _amount + _lockedStake.liquidity <= _balances[msg.sender],
            "Amount must be less that or equal to your non-staked balance"
        );
        _lockedStakes[msg.sender].liquidity += _amount;
    }

    /**
     * @notice  Deposit internal function
     * @dev     This method can handle normal deposit, stake creation and update
     * @param   _amount  Number of tokens to be deposited locked
     * @param   _account  Address of user whose tokens are being deposited/locked
     * @param   _secs  Time period to lock tokens
     * @param   _startTimestamp  Start time stamp of stake
     * @param   _isPermanentlyLocked  Whether or not lock tokens permanently
     * @param   _depositOnly  whether tokens are only deposited only or not
     */
    function _deposit(
        uint256 _amount,
        address _account,
        uint256 _secs,
        uint256 _startTimestamp,
        bool _isPermanentlyLocked,
        bool _depositOnly
    ) internal nonReentrant updateReward(_account, false) {
        LockedStake memory _lockedStake = _lockedStakes[_account];

        if (
            _startTimestamp > 0 &&
            (_lockedStake.startTimestamp == 0 ||
                (!_lockedStake.isPermanentlyLocked &&
                    _lockedStake.endingTimestamp <= _startTimestamp))
        ) {
            _lockedStake.startTimestamp = _startTimestamp;
        }

        if (
            _secs + _lockedStake.startTimestamp > _lockedStake.endingTimestamp
        ) {
            uint256 MaxMultiplier = lockMultiplier(_secs);
            _lockedStake.endingTimestamp = _lockedStake.startTimestamp + _secs;
            _lockedStake.lock_multiplier = MaxMultiplier;
            _lastUsedMultiplier[_account] = MaxMultiplier;
        }

        if (_isPermanentlyLocked && !_lockedStake.isPermanentlyLocked) {
            _lockedStake.isPermanentlyLocked = _isPermanentlyLocked;
        }

        if (_amount > 0) {
            TOKEN.safeTransferFrom(_account, address(this), _amount);
            _totalSupply = _totalSupply + _amount;
            _balances[_account] = _balances[_account] + _amount;
            if (!_depositOnly) {
                _lockedStake.liquidity += _amount;
            }
        }

        _lockedStakes[_account] = _lockedStake;

        // Needed for edge case if the staker only claims once, and after the lock expired
        if (_lastRewardClaimTime[_account] == 0)
            _lastRewardClaimTime[_account] = block.timestamp;

        emit Staked(_account, _amount, _secs);
    }

    /**
     * @notice  Withdraw from non staked balance of user
     * @dev     Can be withdrawn partially
     * @param   _amount  Amount of tokens to withdraw
     * @return  uint256  Amount withdrawn
     */
    function withdrawNonStaked(uint256 _amount) public returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        return _withdraw(msg.sender, _amount);
    }

    /**
     * @notice  Withdraw unlocked stake of user
     * @dev     Complete stake will be withdrawn at once
     * @return  uint256  Amount withdrawn
     */
    function withdrawUnlockedStake() public returns (uint256) {
        return _withdraw(msg.sender, 0);
    }

    /**
     * @notice  Withdraw All balance of user staked and normally deposited
     * @dev     Works only when stake is unlocked
     * @return  uint256  Amount withdrawn
     */
    function withdrawAll() public returns (uint256) {
        return
            withdrawUnlockedStake() +
            withdrawNonStaked(
                _balances[msg.sender] - _lockedStakes[msg.sender].liquidity
            );
    }

    /**
     * @notice  Internal method to withdraw tokens
     * @dev     In case of unlocked stake withdrawl _amount = 0
     * @param   _account  Address of liquidity holder
     * @param   _amount  Amount to be withdrawn
     * @return  uint256  Amount withdrawn
     */
    function _withdraw(address _account, uint256 _amount)
        internal
        nonReentrant
        updateReward(_account, false)
        returns (uint256)
    {
        LockedStake memory thisStake = _lockedStakes[msg.sender];

        //  If user wants to withdraw locked stake
        if (thisStake.liquidity > 0 && _amount == 0) {
            require(
                stakesUnlocked ||
                    stakesUnlockedForAccount[_account] ||
                    !thisStake.isPermanentlyLocked ||
                    thisStake.endingTimestamp < block.timestamp,
                "Cannot withdraw more than non-staked amount"
            );
            _amount = thisStake.liquidity;
            delete _lockedStakes[_account];
        }

        // if user wants to withdraw from non - staked balance
        if (_amount > 0) {
            require(
                _amount + thisStake.liquidity <= _balances[_account],
                "Cannot withdraw more than your non-staked balance"
            );
        }

        // update totalSupply and balances accordingly
        _totalSupply -= _amount;
        _balances[_account] -= _amount;
        TOKEN.safeTransfer(_account, _amount);
        emit Withdrawn(_account, _amount);
        return _amount;
    }

    /// @notice Claim reward accumulated
    function getReward() public nonReentrant updateReward(msg.sender, true) {
        uint256 reward;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokenDetails[rewardTokens[i]].isActive) {
                reward = rewards[msg.sender][i];
                if (reward > 0) {
                    rewards[msg.sender][i] = 0;
                    IERC20(rewardTokens[i]).safeTransfer(msg.sender, reward);
                    emit RewardPaid(msg.sender, reward);
                }
            }
        }
    }

    /**
     * @notice  Get reward accumulated in particular reward token
     * @param   _account  Address of user
     * @param   _rewardToken  Address of set reward token
     */
    function getRewardByToken(address _account, address _rewardToken)
        public
        nonReentrant
        updateReward(_account, true)
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Token not available");
        uint256 reward;
        if (token.isActive) {
            reward = rewards[_account][token.index];
            if (reward > 0) {
                rewards[_account][token.index] = 0;
                IERC20(rewardTokens[token.index]).safeTransfer(_account, reward);
                emit RewardPaid(_account, reward);
            }
        }
    }

    /// @notice Exit from Gauge i.e. Withdraw complete liquidity and claim reward
    function exit() external {
        withdrawAll();
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice  Fetch reward to distribute
     * @param   _rewardToken  Address of reward token
     * @param   _reward  Amount to be fetched
     */
    function notifyRewardAmount(address _rewardToken, uint256 _reward)
        external
        onlyDistribution(_rewardToken)
        updateReward(address(0), false)
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Reward token not available");
        require(
            token.distributor != address(0),
            "Reward distributor for token not set"
        );

        IERC20(_rewardToken).safeTransferFrom(
            token.distributor,
            address(this),
            _reward
        );

        if (block.timestamp >= token.periodFinish) {
            token.rewardRate = _reward / DURATION;
        } else {
            uint256 remaining = token.periodFinish - block.timestamp;
            uint256 leftover = remaining * token.rewardRate;
            token.rewardRate = (_reward + leftover) / DURATION;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = IERC20(_rewardToken).balanceOf(address(this));
        require(
            token.rewardRate <= balance / DURATION,
            "Provided reward too high"
        );

        emit RewardAdded(_reward);

        token.lastUpdateTime = block.timestamp;
        token.periodFinish = block.timestamp + DURATION;
        rewardTokenDetails[_rewardToken] = token;
    }

    /**
     * @notice  Set Gauge-Proxy contract
     * @param   _gaugeProxy  Address of Gauge-Proxy contract
     */
    function setGaugeProxy(address _gaugeProxy) external onlyGov {
        require(_gaugeProxy != address(0), "Address Can't be null");
        gaugeProxy = IGaugeProxyV2(_gaugeProxy);
    }

    /* ========== EVENTS ========== */
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}
