// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../VirtualBalanceWrapper.sol";
import "./BaseGaugeV2.sol";
import "../IJar.sol";

contract VirtualGaugeV2 is
   BaseGaugeV2,
    VirtualBalanceWrapper
{
    using SafeERC20 for IERC20;

    /* ========== MAPPINGS ========== */
    mapping(address => bool) public authorisedAddress;

    /* ========== MODIFIERS ========== */
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

    modifier onlyJarAndAuthorised() {
        require(msg.sender == address(jar) || authorisedAddress[msg.sender]);
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _jar,
        address _governance,
        address _gaugeProxy
    ) {
        require(_jar == address(0), "Cannot set token to zero address");
        require(_governance == address(0), "Cannot set governance to zero address");
        require(_gaugeProxy == address(0), "Cannot set gaugeProxy to zero address");
        jar = IJar(_jar);
        governance = _governance;
        gaugeProxy = IGaugeProxyV2(_gaugeProxy);
    }

    /**
     * @notice  Get calculated derived balance (DillBoosted + LockedBoosted + NFTBoosted) for '_account'
     * @param   _account  Address of user whose derived balance is to be calculated
     * @return  uint256  Calculated derived balance (DillBoosted + LockedBoosted + NFTBoosted)
     */
    function derivedBalance(address _account) public returns (uint256) {
        uint256 _balance = balanceOf(_account);
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = (((totalSupply() * DILL.balanceOf(_account)) /
            DILL.totalSupply()) * 60) / 100;
        uint256 dillBoostedDerivedBal = Math.min(
            _derived + _adjusted,
            _balance
        );

        LockedStake memory thisStake = _lockedStakes[_account];
        uint256 lockMultiplier = thisStake.lockMultiplier;
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

                // Get the weighted-average lockMultiplier
                uint256 numerator = ( _averageDecayedLockMultiplier(_account, timeBeforeExpiry) * 
                    timeBeforeExpiry) + (_MultiplierPrecision * timeAfterExpiry);
                // uint256 numerator = (lockMultiplier * timeBeforeExpiry) +
                //     (_MultiplierPrecision * timeAfterExpiry);
                lockMultiplier =
                    numerator /
                    (timeBeforeExpiry + timeAfterExpiry);
            }
            // Otherwise, it needs to just be 1x
            else {
                lockMultiplier = _MultiplierPrecision;
            }
        } else {
            uint256 elapsedSeconds = block.timestamp - lastRewardClaimTime;
            if (elapsedSeconds > 0) {
                lockMultiplier = thisStake.isPermanentlyLocked
                    ? lockMaxMultiplier
                    : _averageDecayedLockMultiplier(_account, elapsedSeconds);
                _lastUsedMultiplier[_account] =
                    _lastUsedMultiplier[_account] -
                    (elapsedSeconds - 1) *
                    multiplierDecayPerSecond;
            }
        }
        uint256 liquidity = thisStake.liquidity;
        uint256 lockBoostedDerivedBal = (liquidity * lockMultiplier) /
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
    /// @notice Calculate reward per token for all reward tokens set
    function rewardPerToken() public {
        if (totalSupply() != 0) {
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

    /**
     * @notice  Deposit 'amount' 'TOKEN' on user's behalf, can be executed by Jar or authorised address only
     * @dev     'TOKEN' owner need to approve Jar or authorised address to deposit token on owner's behalf
     * @param   _amount  Number of 'TOKEN' to be deposited
     * @param   _account  Address of 'TOKEN' owner
     */
    function depositFor(uint256 _amount, address _account)
        external
        onlyJarAndAuthorised
    {
        require(_amount > 0, "Cannot deposit 0");
        _deposit(_amount, _account, 0, 0, false);
    }

    /**
     * @notice  Deposit and lock 'amount' 'TOKEN' on user's behalf, can be executed by Jar or authorised address only
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
    ) external lockable(_secs) onlyJarAndAuthorised {
        require(_amount > 0, "Cannot deposit 0");
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
            _isPermanentlyLocked
        );
    }

    /**
     * @notice  Add tokens from deposit to stake
     * @param   _account  Number of token to to add to stake from users normal deposit
     * @param   _amount  Number of token to to add to stake from users normal deposit
     */
    function addBalanceToStake(address _account, uint256 _amount) external {
        LockedStake memory _lockedStake = _lockedStakes[_account];
        require(
            (!stakesUnlocked || !stakesUnlockedForAccount[_account]) &&
                _lockedStake.endingTimestamp > block.timestamp,
            "No stake found"
        );
        require(
            _amount + _lockedStake.liquidity <= balanceOf(_account),
            "Amount must be less that or equal to your non-staked balance"
        );
        _lockedStakes[_account].liquidity += _amount;
    }

    /**
     * @notice  Deposit internal function
     * @dev     This method can handle normal deposit, stake creation and update
     * @param   _amount  Number of tokens to be deposited locked
     * @param   _account  Address of user whose tokens are being deposited/locked
     * @param   _secs  Time period to lock tokens
     * @param   _startTimestamp  Start time stamp of stake
     * @param   _isPermanentlyLocked  Whether or not lock tokens permanently
     */
    function _deposit(
        uint256 _amount,
        address _account,
        uint256 _secs,
        uint256 _startTimestamp,
        bool _isPermanentlyLocked
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
            _lockedStake.lockMultiplier = MaxMultiplier;
            _lastUsedMultiplier[_account] = MaxMultiplier;
        }

        if (_isPermanentlyLocked && !_lockedStake.isPermanentlyLocked) {
            _lockedStake.isPermanentlyLocked = _isPermanentlyLocked;
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
     * @param   _account  Address of liquidity holder to withdraw from
     * @param   _amount  Amount of tokens to withdraw
     * @return  uint256  Amount withdrawn
     */
    function withdrawNonStaked(address _account, uint256 _amount)
        public
        onlyJarAndAuthorised
        returns (uint256)
    {
        return _withdraw(_account, _amount);
    }

    /**
     * @notice  Withdraw All balance of user staked and normally deposited
     * @dev     Works only when stake is unlocked
     * @param   _account  Address of liquidity holder to withdraw from
     * @return  uint256  Amount withdrawn
     */
    function withdrawUnlockedStake(address _account)
        public
        onlyJarAndAuthorised
        returns (uint256)
    {
        return _withdraw(_account, 0);
    }

    /**
     * @notice  Withdraw All balance of user staked and normally deposited
     * @dev     Works only when stake is unlocked
     * @param   _account  Address of liquidity holder to withdraw from
     * @return  uint256  Amount withdrawn
     */
    function withdrawAll(address _account)
        public
        onlyJarAndAuthorised
        returns (uint256)
    {
        return (withdrawUnlockedStake(_account) +
            withdrawNonStaked(
                _account,
                balanceOf(_account) - _lockedStakes[_account].liquidity
            ));
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
        LockedStake memory thisStake = _lockedStakes[_account];

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
                _amount + thisStake.liquidity <= balanceOf(_account),
                "Cannot withdraw more than your non-staked balance"
            );
        }
        emit Withdrawn(_account, _amount);
        return _amount;
    }

    /// @notice Claim accumulated reward
    function getReward(address _account)
        public
        nonReentrant
        updateReward(_account, true)
        onlyJarAndAuthorised
    {
        uint256 reward;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokenDetails[rewardTokens[i]].isActive) {
                reward = rewards[_account][i];
                if (reward > 0) {
                    rewards[_account][i] = 0;
                    IERC20(rewardTokens[i]).safeTransfer(_account, reward);
                    emit RewardPaid(_account, reward);
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
        onlyJarAndAuthorised
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Token not available");
        uint256 reward;
        if (token.isActive) {
            reward = rewards[_account][token.index];
            if (reward > 0) {
                rewards[_account][token.index] = 0;
                IERC20(rewardTokens[token.index]).safeTransfer(
                    _account,
                    reward
                );
                emit RewardPaid(_account, reward);
            }
        }
    }

    /// @notice Exit from Gauge i.e. Withdraw complete liquidity and claim reward
    function exit(address account) external {
        withdrawAll(account);
        getReward(account);
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
            token.rewardRate =
                (_reward + leftover) /
                DURATION;
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

    /* ========== EVENTS ========== */
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}
