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
    // Token addresses
    IERC20 public constant DILL =
        IERC20(0xbBCf169eE191A1Ba7371F30A1C344bFC498b29Cf);

    // Constant for various precisions
    uint256 private constant _MultiplierPrecision = 1e18;
    uint256 public constant DURATION = 7 days;

    // Lock time and multiplier
    uint256 public lockMaxMultiplier = uint256(25e17); // E18. 1x = e18
    uint256 public lockTimeForMaxMultiplier = 365 * 86400; // 1 year
    uint256 public lockTimeMin = 86400; // 1 day

    //Reward addresses
    address[] public rewardTokens;

    // reward token details
    struct rewardTokenDetail {
        uint256 index;
        bool isActive;
        address distributor;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 periodFinish;
    }
    mapping(address => rewardTokenDetail) public rewardTokenDetails; // token address => detatils

    // Rewards tracking
    mapping(address => mapping(uint256 => uint256))
        private userRewardPerTokenPaid;
    mapping(address => mapping(uint256 => uint256)) public rewards;
    mapping(address => bool) public authorisedAddress;
    // uint256[] private rewardPerTokenStored;
    uint256 public multiplierDecayPerSecond = uint256(48e9);
    mapping(address => uint256) private _lastUsedMultiplier;
    mapping(address => uint256) private _lastRewardClaimTime; // staker addr -> timestamp

    // Balance tracking
    uint256 public derivedSupply;
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint256) private _base;

    // Stake tracking
    mapping(address => LockedStake) private _lockedStakes;

    // Administrative booleans
    bool public stakesUnlocked; // Release locked stakes in case of emergency
    mapping(address => bool) public stakesUnlockedForAccount; // Release locked stakes of an account in case of emergency

    /* ========== STRUCTS ========== */

    struct LockedStake {
        uint256 startTimestamp;
        uint256 liquidity;
        uint256 endingTimestamp;
        uint256 lock_multiplier;
        bool isPermanentlyLocked;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyDistribution(address _token) {
        require(
            msg.sender == rewardTokenDetails[_token].distributor,
            "Caller is not RewardsDistribution contract"
        );
        _;
    }

    modifier onlyGov() {
        require(
            msg.sender == governance,
            "Operation allowed by only governance"
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
                    userRewardPerTokenPaid[account][i] = token
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

    constructor(address _jar, address _governance) {
        require(_jar == address(0), "cannot set zero address");
        jar = IJar(_jar);
        governance = _governance;
    }

    /* ========== VIEWS ========== */
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

    // Multiplier amount, given the length of the lock
    function lockMultiplier(uint256 secs) public view returns (uint256) {
        uint256 lock_multiplier = uint256(_MultiplierPrecision) +
            ((secs * (lockMaxMultiplier - _MultiplierPrecision)) /
                (lockTimeForMaxMultiplier));
        if (lock_multiplier > lockMaxMultiplier)
            lock_multiplier = lockMaxMultiplier;
        return lock_multiplier;
    }

    function _averageDecayedLockMultiplier(
        address account,
        uint256 elapsedSeconds
    ) internal view returns (uint256) {
        return
            (2 *
                _lastUsedMultiplier[account] -
                (elapsedSeconds - 1) *
                multiplierDecayPerSecond) / 2;
    }

    // All the locked stakes for a given account
    function lockedStakesOf(address account)
        external
        view
        returns (LockedStake memory)
    {
        return _lockedStakes[account];
    }

    function earned(address account)
        public
        returns (uint256[] memory newEarned)
    {
        rewardPerToken();
        newEarned = new uint256[](rewardTokens.length);

        if (derivedBalances[account] == 0) {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                newEarned[i] = 0;
            }
        } else {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                rewardTokenDetail memory token = rewardTokenDetails[
                    rewardTokens[i]
                ];
                if (token.isActive) {
                    newEarned[i] =
                        ((derivedBalances[account] *
                            (token.rewardPerTokenStored -
                                userRewardPerTokenPaid[account][i])) / 1e18) +
                        rewards[account][i];
                }
            }
        }
    }

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
                            1e18) / derivedSupply);
                }
            }
        }
    }

    function setJar(address _jar) external onlyGov {
        require(_jar != address(0), "cannot set to zero");
        require(_jar != address(jar), "Jar is already set");
        jar = IJar(_jar);
    }

    function setAuthoriseAddress(address _account, bool value)
        external
        onlyGov
    {
        require(
            authorisedAddress[_account] != value,
            "address is already set to given value"
        );
        authorisedAddress[_account] = value;
    }

    function setRewardToken(address _rewardToken, address _distributionForToken)
        public
        onlyGov
    {
        rewardTokenDetail memory token;
        rewardTokenDetails[_rewardToken].isActive = true;
        rewardTokenDetails[_rewardToken].index = rewardTokens.length;
        rewardTokenDetails[_rewardToken].distributor = _distributionForToken;
        rewardTokenDetails[_rewardToken].rewardRate = 0;
        rewardTokenDetails[_rewardToken].rewardPerTokenStored = 0;
        rewardTokenDetails[_rewardToken].periodFinish = 0;

        rewardTokens.push(_rewardToken);
    }

    function setRewardTokenInactive(address _rewardToken) public onlyGov {
        require(
            rewardTokenDetails[_rewardToken].isActive,
            "Reward token not available"
        );
        rewardTokenDetails[_rewardToken].isActive = false;
    }

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

    function derivedBalance(address account) public returns (uint256) {
        uint256 _balance = balanceOf(account);
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = (((totalSupply() * DILL.balanceOf(account)) /
            DILL.totalSupply()) * 60) / 100;
        uint256 dillBoostedDerivedBal = Math.min(
            _derived + _adjusted,
            _balance
        );

        uint256 lockBoostedDerivedBal = 0;

        LockedStake memory thisStake = _lockedStakes[account];
        uint256 lock_multiplier = thisStake.lock_multiplier;
        uint256 lastRewardClaimTime = _lastRewardClaimTime[account];
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
                    : _averageDecayedLockMultiplier(account, elapsedSeconds);
                _lastUsedMultiplier[account] =
                    _lastUsedMultiplier[account] -
                    (elapsedSeconds - 1) *
                    multiplierDecayPerSecond;
            }
        }
        uint256 liquidity = thisStake.liquidity;
        uint256 combined_boosted_amount = (liquidity * lock_multiplier) /
            _MultiplierPrecision;
        lockBoostedDerivedBal = lockBoostedDerivedBal + combined_boosted_amount;

        return dillBoostedDerivedBal + lockBoostedDerivedBal;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function kick(address account) public {
        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply = derivedSupply - _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply = derivedSupply + _derivedBalance;
    }

    function depositFor(uint256 amount, address account)
        external
        onlyJarAndAuthorised
    {
        require(amount > 0, "Cannot deposit 0");
        _deposit(amount, account, 0, 0, false);
    }

    function depositForAndLock(
        uint256 amount,
        address account,
        uint256 secs,
        bool isPermanentlyLocked
    ) external lockable(secs) onlyJarAndAuthorised {
        require(amount > 0, "Cannot deposit 0");
        LockedStake memory thisStake = _lockedStakes[account];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[account]) &&
                    (thisStake.endingTimestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(amount, account, secs, block.timestamp, isPermanentlyLocked);
    }

    function addBalanceToStakeFor(address _account, uint256 _amount) external {
        LockedStake memory _lockedStake = _lockedStakes[_account];
        require(
            (!stakesUnlocked || !stakesUnlockedForAccount[_account]) &&
                _lockedStake.ending_timestamp > block.timestamp,
            "No stake found"
        );
        require(
            _amount + _lockedStake.liquidity <= _balances[_account],
            "Amount must be less that or equal to your non-staked balance"
        );
        _lockedStakes[_account].liquidity += _amount;
    }

    function _deposit(
        uint256 amount,
        address account,
        uint256 secs,
        uint256 startTimestamp,
        bool isPermanentlyLocked
    ) internal nonReentrant updateReward(account, false) {
        LockedStake memory _lockedStake = _lockedStakes[account];

        if (
            startTimestamp > 0 &&
            (_lockedStake.startTimestamp == 0 ||
                (!_lockedStake.isPermanentlyLocked &&
                    _lockedStake.endingTimestamp <= startTimestamp))
        ) {
            _lockedStake.startTimestamp = startTimestamp;
        }

        if (secs + _lockedStake.startTimestamp > _lockedStake.endingTimestamp) {
            uint256 MaxMultiplier = lockMultiplier(secs);
            _lockedStake.endingTimestamp = _lockedStake.startTimestamp + secs;
            _lockedStake.lock_multiplier = MaxMultiplier;
            _lastUsedMultiplier[account] = MaxMultiplier;
        }

        if (isPermanentlyLocked && !_lockedStake.isPermanentlyLocked) {
            _lockedStake.isPermanentlyLocked = isPermanentlyLocked;
        }

        _lockedStakes[account] = _lockedStake;

        // Needed for edge case if the staker only claims once, and after the lock expired
        if (_lastRewardClaimTime[account] == 0)
            _lastRewardClaimTime[account] = block.timestamp;

        emit Staked(account, amount, secs);
    }

    function withdrawNonStaked(address account, uint256 _amount)
        public
        onlyJarAndAuthorised
        returns (uint256)
    {
        return _withdraw(account, _amount);
    }

    function withdrawUnlockedStake(address _account)
        public
        onlyJarAndAuthorised
        returns (uint256)
    {
        return _withdraw(_account, 0);
    }

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
        return _amount;
    }

    function getReward(address account)
        public
        nonReentrant
        updateReward(account, true)
        onlyJarAndAuthorised
    {
        uint256 reward;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokenDetails[rewardTokens[i]].isActive) {
                reward = rewards[account][i];
                if (reward > 0) {
                    rewards[account][i] = 0;
                    IERC20(rewardTokens[i]).safeTransfer(account, reward);
                    emit RewardPaid(account, reward);
                }
            }
        }
    }

    function getRewardByToken(address account, address _rewardToken)
        public
        nonReentrant
        updateReward(account, true)
        onlyJarAndAuthorised
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Token not available");
        uint256 reward;
        if (token.isActive) {
            reward = rewards[account][token.index];
            if (reward > 0) {
                rewards[account][token.index] = 0;
                IERC20(rewardTokens[token.index]).safeTransfer(account, reward);
                emit RewardPaid(account, reward);
            }
        }
    }

    function exit(address account) external {
        withdrawAll(account);
        getReward(account);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(
        address _rewardToken,
        uint256 _reward,
        int256[] calldata _weights,
        uint256 periodId
    ) external onlyDistribution(_rewardToken) updateReward(address(0), false) {
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

    function setMultipliers(uint256 _lock_max_multiplier) external onlyGov {
        require(
            _lock_max_multiplier >= uint256(1e18),
            "Multiplier must be greater than or equal to 1e18"
        );
        lockMaxMultiplier = _lock_max_multiplier;
        emit LockedStakeMaxMultiplierUpdated(lockMaxMultiplier);
    }

    function setMaxRewardsDuration(uint256 _lockTimeForMaxMultiplier)
        external
        onlyGov
    {
        require(
            _lockTimeForMaxMultiplier >= 86400,
            "Rewards duration too short"
        );
        // require(
        //     periodFinish == 0 || block.timestamp > periodFinish,
        //     "Reward period incomplete"
        // );
        lockTimeForMaxMultiplier = _lockTimeForMaxMultiplier;
        emit MaxRewardsDurationUpdated(lockTimeForMaxMultiplier);
    }

    function unlockStakes() external onlyGov {
        stakesUnlocked = !stakesUnlocked;
    }

    function unlockStakeForAccount(address account) external onlyGov {
        stakesUnlockedForAccount[account] = !stakesUnlockedForAccount[account];
    }

    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount, uint256 secs);
    event Withdrawn(address indexed user, uint256 amount, uint256 index);
    event RewardPaid(address indexed user, uint256 reward);
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event MaxRewardsDurationUpdated(uint256 newDuration);
}
