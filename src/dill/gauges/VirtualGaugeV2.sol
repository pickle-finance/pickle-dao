// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "../VirtualBalanceWrapper.sol";
import "../IJar.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VirtualGaugeV2 is
    ProtocolGovernance,
    ReentrancyGuard,
    VirtualBalanceWrapper
{
    using SafeERC20 for IERC20;

    /// @notice Token addresses
    IERC20 public constant DILL =
        IERC20(0xbBCf169eE191A1Ba7371F30A1C344bFC498b29Cf);

    /// @notice Constant for various precisions
    uint256 private constant _MultiplierPrecision = 1e18;
    uint256 public constant DURATION = 7 days;
    uint256 public multiplierDecayPerSecond = uint256(48e9);

    /// @notice Lock time and multiplier
    uint256 public lockMaxMultiplier = uint256(25e17); // E18. 1x = e18
    uint256 public lockTimeForMaxMultiplier = 365 * 86400; // 1 year
    uint256 public lockTimeMin = 86400; // 1 day

    /// @notice Reward addresses
    address[] public rewardTokens;

    /// @notice Balance tracking
    uint256 public derivedSupply;

    /// @notice Release locked stakes in case of emergency; Administrative booleans
    bool public stakesUnlocked;
    /* ========== STRUCTS & ENUM ========== */
    enum GaugeType {
        REGULAR,
        VIRTUAL,
        ROOT
    }
    /// @notice reward token details
    struct rewardTokenDetail {
        uint256 index;
        bool isActive;
        address distributor;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 periodFinish;
    }

    /// @notice Locked stake details
    struct LockedStake {
        uint256 startTimestamp;
        uint256 liquidity;
        uint256 endingTimestamp;
        uint256 lock_multiplier;
        bool isPermanentlyLocked;
    }

    /* ========== MAPPINGS ========== */
    mapping(address => rewardTokenDetail) public rewardTokenDetails; // token address => detatils
    mapping(address => mapping(uint256 => uint256))
        private _userRewardPerTokenPaid;
    mapping(address => mapping(uint256 => uint256)) public rewards;
    mapping(address => bool) public authorisedAddress;
    mapping(address => uint256) private _lastUsedMultiplier;
    mapping(address => uint256) private _lastRewardClaimTime; // staker addr -> timestamp
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint256) private _base;
    mapping(address => LockedStake) private _lockedStakes; // Stake tracking
    mapping(address => bool) public stakesUnlockedForAccount; // Release locked stakes of an account in case of emergency

    /// @notice Instance of gaugeProxy
    IGaugeProxyV2 public gaugeProxy;

    /* ========== MODIFIERS ========== */

    modifier onlyDistribution(address _token) {
        require(
            msg.sender == rewardTokenDetails[_token].distributor,
            "Caller is not RewardsDistribution contract"
        );
        _;
    }

    modifier lockable(uint256 secs) {
        require(secs >= lockTimeMin, "Minimum stake time not met");
        require(
            secs <= lockTimeForMaxMultiplier,
            "Trying to lock for too long"
        );
        _;
    }

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
    }

    /* ========== VIEWS ========== */

    /**
     * @notice  Get on going rewards for all reward tokens set for a period
     * @return  rewardsPerDurationArr  Array of rewards for all set reward tokens
     */
    function getRewardForDuration()
        external
        view
        returns (uint256[] memory rewardsPerDurationArr)
    {
        rewardsPerDurationArr = new uint256[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardTokenDetail memory token = rewardTokenDetails[
                rewardTokens[i]
            ];
            if (token.isActive) {
                rewardsPerDurationArr[i] = token.rewardRate * DURATION;
            }
        }
    }

    /**
     * @notice  Get multiplier, given the length of the lock
     * @param   _secs  Length of the lock
     * @return  uint256  Lock multiplier
     */
    function lockMultiplier(uint256 _secs) public view returns (uint256) {
        uint256 lock_multiplier = uint256(_MultiplierPrecision) +
            ((_secs * (lockMaxMultiplier - _MultiplierPrecision)) /
                (lockTimeForMaxMultiplier));
        if (lock_multiplier > lockMaxMultiplier)
            lock_multiplier = lockMaxMultiplier;
        return lock_multiplier;
    }

    /**
     * @notice  Get decayed multiplier, given time elapesed since lock start time
     * @param   _account  Address of user, for whose stake decayed multiplier is being calculated
     * @param   _elapsedSeconds  Time elapesed since lock start time
     * @return  uint256  Average decayed lock multiplier
     */
    function _averageDecayedLockMultiplier(
        address _account,
        uint256 _elapsedSeconds
    ) internal view returns (uint256) {
        return
            (2 *
                _lastUsedMultiplier[_account] -
                (_elapsedSeconds - 1) *
                multiplierDecayPerSecond) / 2;
    }

    /**
     * @notice  Get locked stakes for a given account
     * @param   _account  Adress of user whose stakes are to be fetched
     * @return  LockedStake  stakes of 'account'
     */
    function lockedStakesOf(address _account)
        external
        view
        returns (LockedStake memory)
    {
        return _lockedStakes[_account];
    }

    /// @notice Calaculate lastUpdateTime for all reward tokens set
    function lastTimeRewardApplicable() public {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardTokenDetail memory token = rewardTokenDetails[
                rewardTokens[i]
            ];
            if (token.isActive) {
                rewardTokenDetails[rewardTokens[i]].lastUpdateTime = Math.min(
                    block.timestamp,
                    token.periodFinish
                );
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
     * @notice  Set jar
     * @dev     Works only when Jar is not set
     * @param   _jar  Address of Jar
     */
    function setJar(address _jar) external onlyGov {
        require(_jar != address(0), "Cannot set to zero");
        require(_jar != address(jar), "Jar is already set");
        jar = IJar(_jar);
    }

    /**
     * @notice  Set or revoke authorised address
     * @dev     There can be multiple authorised addresses
     * @param   _account  Address to be authorised
     * @param   _value  Whether to set or revoke address authorisation
     */
    function setAuthoriseAddress(address _account, bool _value)
        external
        onlyGov
    {
        require(
            authorisedAddress[_account] != _value,
            "Address is already set to given value"
        );
        authorisedAddress[_account] = _value;
    }

    /**
     * @notice  Set new reward token
     * @param   _rewardToken  Address of reward token
     * @param   _distributionForToken  Address of distribution for '_rewardToken'
     */
    function setRewardToken(address _rewardToken, address _distributionForToken)
        public
        onlyGov
    {
        rewardTokenDetail memory token;
        token.isActive = true;
        token.index = rewardTokens.length;
        token.distributor = _distributionForToken;
        token.rewardRate = 0;
        token.rewardPerTokenStored = 0;
        token.periodFinish = 0;
        rewardTokenDetails[_rewardToken] = token;
        rewardTokens.push(_rewardToken);
    }

    /**
     * @notice  Set reward token inactive
     * @param   _rewardToken  Address of reward token
     */
    function setRewardTokenInactive(address _rewardToken) public onlyGov {
        require(
            rewardTokenDetails[_rewardToken].isActive,
            "Reward token not available"
        );
        rewardTokenDetails[_rewardToken].isActive = false;
    }

    /**
     * @notice  Set distribution for already set reward token
     * @param   _distributionForToken  Address which can distribute '_rewardToken'
     * @param   _rewardToken  Address of reward token
     */
    function setDisributionForToken(
        address _distributionForToken,
        address _rewardToken
    ) public onlyGov {
        require(
            rewardTokenDetails[_rewardToken].isActive,
            "Reward token not available"
        );
        require(
            rewardTokenDetails[_rewardToken].distributor !=
                _distributionForToken,
            "Given address is already distributor for given reward token"
        );
        rewardTokenDetails[_rewardToken].distributor = _distributionForToken;
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

        uint256 lockBoostedDerivedBal = 0;

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
        uint256 combined_boosted_amount = (liquidity * lock_multiplier) /
            _MultiplierPrecision;
        lockBoostedDerivedBal = lockBoostedDerivedBal + combined_boosted_amount;

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
            _lockedStake.lock_multiplier = MaxMultiplier;
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
            rewardTokenDetails[_rewardToken].rewardRate = _reward / DURATION;
        } else {
            uint256 remaining = token.periodFinish - block.timestamp;
            uint256 leftover = remaining * token.rewardRate;
            rewardTokenDetails[_rewardToken].rewardRate =
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

        rewardTokenDetails[_rewardToken].lastUpdateTime = block.timestamp;
        rewardTokenDetails[_rewardToken].periodFinish =
            block.timestamp +
            DURATION;
    }

    /// @notice Unlock stakes for all users
    function unlockStakes() external onlyGov {
        stakesUnlocked = !stakesUnlocked;
    }

    /**
     * @notice  Unlock stakes for a particular user
     * @param   account  Address of user whose stake is to be uncloked
     */
    function unlockStakeForAccount(address account) external onlyGov {
        stakesUnlockedForAccount[account] = !stakesUnlockedForAccount[account];
    }

    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount, uint256 secs);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
}
