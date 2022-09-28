// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGaugeProxyV2 {
    function isStaked(address account) external view returns(bool);
    function getTokenLevel(address account) external view returns(uint256);
    function isBoostable(address account) external view returns(bool);
}

contract GaugeV2 is ProtocolGovernance, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Token addresses
    IERC20 public constant PICKLE =
        IERC20(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5);
    IERC20 public constant DILL =
        IERC20(0xbBCf169eE191A1Ba7371F30A1C344bFC498b29Cf);
    address public constant TREASURY =
        address(0x066419EaEf5DE53cc5da0d8702b990c5bc7D1AB3);

    // Constant for various precisions
    uint256 private constant _MultiplierPrecision = 1e18;

    IERC20 public immutable TOKEN;
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
    mapping(address => mapping(uint256 => uint256)) public _rewards;
    uint256[] private rewardPerTokenStored;
    uint256 public multiplierDecayPerSecond = uint256(48e9);
    mapping(address => uint256) private _lastUsedMultiplier;
    mapping(address => uint256) private _lastRewardClaimTime; // staker addr -> timestamp

    // Balance tracking
    uint256 private _totalSupply;
    uint256 public derivedSupply;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint256) private _base;

    // Delegate tracking
    mapping(address => mapping(address => bool)) public stakingDelegates;

    // Stake tracking
    mapping(address => LockedStake) private _lockedStakes;

    // Administrative booleans
    bool public stakesUnlocked; // Release locked stakes in case of emergency
    mapping(address => bool) public stakesUnlockedForAccount; // Release locked stakes of an account in case of emergency

    /* ========== STRUCTS ========== */

    struct LockedStake {
        uint256 startTimestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
        uint256 lock_multiplier;
        bool isPermanentlyLocked;
    }
    //Instance of gaugeProxy
    IGaugeProxyV2 public gaugeProxy;
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
                    _rewards[account][i] = earnedArr[i];
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

    /* ========== CONSTRUCTOR ========== */

    constructor(address _token, address _governance, address _gaugeProxy) {
        TOKEN = IERC20(_token);
        governance = _governance;
        gaugeProxy = IGaugeProxyV2(_gaugeProxy);
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

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
                            1e18) / derivedSupply);
                }
            }
        }
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
                        _rewards[account][i];
                }
            }
        }
    }

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

    function setRewardTokenInactive(address _rewardToken) public onlyGov {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Reward token not available");
        token.isActive = false;
        rewardTokenDetails[_rewardToken] = token;
    }

    function setDisributionForToken(
        address _distributionForToken,
        address _rewardToken
    ) public onlyGov {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];

        require(token.isActive, "Reward token not available");
        require(
            token.distributor != _distributionForToken,
            "Given address is already distributor for given reward token"
        );
        token.distributor = _distributionForToken;
        rewardTokenDetails[_rewardToken] = token;
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

    function setStakingDelegate(address _delegate) public {
        require(
            stakingDelegates[msg.sender][_delegate],
            "Already a staking delegate for user!"
        );
        require(_delegate != msg.sender, "Cannot delegate to self");
        stakingDelegates[msg.sender][_delegate] = true;
    }

    function derivedBalance(address account) public returns (uint256) {
        uint256 _balance = _balances[account];
        uint256 _derived = (_balance * 40) / 100;
        uint256 _adjusted = (((_totalSupply * DILL.balanceOf(account)) /
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
            thisStake.ending_timestamp <= block.timestamp &&
            !thisStake.isPermanentlyLocked
        ) {
            // If the lock expired in the time since the last claim, the weight needs to be proportionately averaged this time
            if (lastRewardClaimTime < thisStake.ending_timestamp) {
                uint256 timeBeforeExpiry = thisStake.ending_timestamp -
                    lastRewardClaimTime;
                uint256 timeAfterExpiry = block.timestamp -
                    thisStake.ending_timestamp;

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

        uint256 nftBoostedDerivedBalance = 0;
        if(gaugeProxy.isStaked(account) && gaugeProxy.isBoostable(account)){
            uint256 tokenLevel = gaugeProxy.getTokenLevel(account);
            uint256 nftLockMultiplier = (lockMaxMultiplier - (10e17) * tokenLevel) / 100;
            nftBoostedDerivedBalance = (thisStake.liquidity * nftLockMultiplier) /
                _MultiplierPrecision;
        }
        return dillBoostedDerivedBal + lockBoostedDerivedBal + nftBoostedDerivedBalance;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function kick(address account) public {
        uint256 _derivedBalance = derivedBalances[account];
        derivedSupply = derivedSupply - _derivedBalance;
        _derivedBalance = derivedBalance(account);
        derivedBalances[account] = _derivedBalance;
        derivedSupply = derivedSupply + _derivedBalance;
    }

    // Simple Deposits

    function depositAll() external {
        require(TOKEN.balanceOf(msg.sender) > 0, "Cannot stake 0");
        _deposit(TOKEN.balanceOf(msg.sender), msg.sender, 0, 0, false, true);
    }

    function depositFor(uint256 amount, address account) external {
        require(amount > 0, "Cannot stake 0");
        require(
            stakingDelegates[account][msg.sender],
            "Only registerd delegates can deposit for their deligator"
        );
        _deposit(amount, account, 0, 0, false, true);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        _deposit(amount, msg.sender, 0, 0, false, true);
    }

    function depositAllAndLock(uint256 secs, bool isPermanentlyLocked)
        external
        lockable(secs)
    {
        require(TOKEN.balanceOf(msg.sender) > 0, "Cannot stake 0");
        LockedStake memory thisStake = _lockedStakes[msg.sender];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                    (thisStake.ending_timestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            TOKEN.balanceOf(msg.sender),
            msg.sender,
            secs,
            block.timestamp,
            isPermanentlyLocked,
            false
        );
    }

    function depositForAndLock(
        uint256 amount,
        address account,
        uint256 secs,
        bool isPermanentlyLocked
    ) external lockable(secs) {
        require(amount > 0, "Cannot stake 0");
        require(
            stakingDelegates[account][msg.sender],
            "Only registerd delegates can stake for their deligator"
        );
        LockedStake memory thisStake = _lockedStakes[account];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[account]) &&
                    (thisStake.ending_timestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            amount,
            account,
            secs,
            block.timestamp,
            isPermanentlyLocked,
            false
        );
    }

    function depositAndLock(
        uint256 amount,
        uint256 secs,
        bool isPermanentlyLocked
    ) external lockable(secs) {
        require(amount > 0, "Cannot stake 0");
        LockedStake memory thisStake = _lockedStakes[msg.sender];
        // Check if stake already exists and if it is unlocked
        if (thisStake.liquidity > 0) {
            require(
                (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                    (thisStake.ending_timestamp > block.timestamp),
                "Please withdraw your unlocked stake first"
            );
        }
        _deposit(
            amount,
            msg.sender,
            secs,
            block.timestamp,
            isPermanentlyLocked,
            false
        );
    }

    function addBalanceToStake(uint256 _amount) external {
        LockedStake memory _lockedStake = _lockedStakes[msg.sender];
        require(
            (!stakesUnlocked || !stakesUnlockedForAccount[msg.sender]) &&
                _lockedStake.ending_timestamp > block.timestamp,
            "No stake found"
        );
        require(
            _amount + _lockedStake.liquidity <= _balances[msg.sender],
            "Amount must be less that or equal to your non-staked balance"
        );
        _lockedStakes[msg.sender].liquidity += _amount;
    }

    function _deposit(
        uint256 amount,
        address account,
        uint256 secs,
        uint256 startTimestamp,
        bool isPermanentlyLocked,
        bool depositOnly
    ) internal nonReentrant updateReward(account, false) {
        LockedStake memory _lockedStake = _lockedStakes[account];

        if (
            startTimestamp > 0 &&
            (_lockedStake.startTimestamp == 0 ||
                (!_lockedStake.isPermanentlyLocked &&
                    _lockedStake.ending_timestamp <= startTimestamp))
        ) {
            _lockedStake.startTimestamp = startTimestamp;
        }

        if (
            secs + _lockedStake.startTimestamp > _lockedStake.ending_timestamp
        ) {
            uint256 MaxMultiplier = lockMultiplier(secs);
            _lockedStake.ending_timestamp = _lockedStake.startTimestamp + secs;
            _lockedStake.lock_multiplier = MaxMultiplier;
            _lastUsedMultiplier[account] = MaxMultiplier;
        }

        if (isPermanentlyLocked && !_lockedStake.isPermanentlyLocked) {
            _lockedStake.isPermanentlyLocked = isPermanentlyLocked;
        }

        if (amount > 0) {
            TOKEN.safeTransferFrom(account, address(this), amount);
            _totalSupply = _totalSupply + amount;
            _balances[account] = _balances[account] + amount;
            if (!depositOnly) {
                _lockedStake.liquidity += amount;
            }
        }

        _lockedStakes[account] = _lockedStake;

        // Needed for edge case if the staker only claims once, and after the lock expired
        if (_lastRewardClaimTime[account] == 0)
            _lastRewardClaimTime[account] = block.timestamp;

        emit Staked(account, amount, secs);
    }

    function withdrawNonStaked(uint256 _amount) public {
        require(_amount > 0, "Amount must be greater than 0");
        _withdraw(msg.sender, _amount);
    }

    function withdrawUnlockedStake() public {
        _withdraw(msg.sender, 0);
    }

    function withdrawAll() public {
        withdrawUnlockedStake();
        withdrawNonStaked(
            _balances[msg.sender] - _lockedStakes[msg.sender].liquidity
        );
    }

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
                    thisStake.ending_timestamp < block.timestamp,
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

    function getReward() public nonReentrant updateReward(msg.sender, true) {
        uint256 reward;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokenDetails[rewardTokens[i]].isActive) {
                reward = _rewards[msg.sender][i];
                if (reward > 0) {
                    _rewards[msg.sender][i] = 0;
                    IERC20(rewardTokens[i]).safeTransfer(msg.sender, reward);
                    emit RewardPaid(msg.sender, reward);
                }
            }
        }
    }

    function getRewardByToken(address account, address _rewardToken)
        public
        nonReentrant
        updateReward(account, true)
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Token not available");
        uint256 reward;
        if (token.isActive) {
            reward = _rewards[account][token.index];
            if (reward > 0) {
                _rewards[account][token.index] = 0;
                IERC20(rewardTokens[token.index]).safeTransfer(account, reward);
                emit RewardPaid(account, reward);
            }
        }
    }

    function exit() external {
        withdrawAll();
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(
        address _rewardToken,
        uint256 _reward
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

    function setMultipliers(uint256 _lock_max_multiplier) external onlyGov {
        require(
            _lock_max_multiplier >= uint256(1e18),
            "Multiplier must be greater than or equal to 1e18"
        );
        lockMaxMultiplier = _lock_max_multiplier;
        emit LockedStakeMaxMultiplierUpdated(lockMaxMultiplier);
    }

    function setGaugeProxy(address _gaugeProxy) external onlyGov {
        require(_gaugeProxy != address(0), "Address Can't be null");
        gaugeProxy = IGaugeProxyV2(_gaugeProxy);
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
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event MaxRewardsDurationUpdated(uint256 newDuration);
}
