// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


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
    mapping(address => mapping(uint256 => uint256)) private _lastUsedMultiplier;
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
    mapping(address => LockedStake[]) private _lockedStakes;

    // Administrative booleans
    bool public stakesUnlocked; // Release locked stakes in case of emergency
    mapping(address => bool) public stakesUnlockedForAccount; // Release locked stakes of an account in case of emergency

    /* ========== STRUCTS ========== */

    struct LockedStake {
        uint256 start_timestamp;
        uint256 liquidity;
        uint256 ending_timestamp;
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

    constructor(address _token, address _governance) {
        TOKEN = IERC20(_token);
        governance = _governance;
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
        returns (LockedStake[] memory)
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
        rewardTokenDetails[_rewardToken].isActive = true;
        rewardTokenDetails[_rewardToken].index = rewardTokens.length;
        rewardTokenDetails[_rewardToken].distributor = _distributionForToken;
        rewardTokenDetails[_rewardToken].rewardRate = 0;
        rewardTokenDetails[_rewardToken].rewardPerTokenStored = 0;
        rewardTokenDetails[_rewardToken].periodFinish = 0;

        // rewardTokenDetails[_rewardToken] = token;
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
        uint256 index,
        uint256 elapsedSeconds
    ) internal view returns (uint256) {
        return
            (2 *
                _lastUsedMultiplier[account][index] -
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

        // Loop through the locked stakes, first by getting the liquidity * lock_multiplier portion
        uint256 lockBoostedDerivedBal = 0;
        for (uint256 i = 0; i < _lockedStakes[account].length; i++) {
            LockedStake memory thisStake = _lockedStakes[account][i];
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
                        : _averageDecayedLockMultiplier(
                            account,
                            i,
                            elapsedSeconds
                        );
                    _lastUsedMultiplier[account][i] =
                        _lastUsedMultiplier[account][i] -
                        (elapsedSeconds - 1) *
                        multiplierDecayPerSecond;
                }
            }
            uint256 liquidity = thisStake.liquidity;
            uint256 combined_boosted_amount = (liquidity * lock_multiplier) /
                _MultiplierPrecision;
            lockBoostedDerivedBal =
                lockBoostedDerivedBal +
                combined_boosted_amount;
        }

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

    function depositAllAndLock(uint256 secs, bool isPermanentlyLocked)
        external
        lockable(secs)
    {
        _deposit(
            TOKEN.balanceOf(msg.sender),
            msg.sender,
            secs,
            block.timestamp,
            isPermanentlyLocked
        );
    }

    function depositAll() external {
        _deposit(
            TOKEN.balanceOf(msg.sender),
            msg.sender,
            0,
            block.timestamp,
            false
        );
    }

    function depositFor(uint256 amount, address account) external {
        require(
            stakingDelegates[account][msg.sender],
            "Only registerd delegates can deposit for their deligator"
        );
        _deposit(amount, account, 0, block.timestamp, false);
    }

    function depositForAndLock(
        uint256 amount,
        address account,
        uint256 secs,
        bool isPermanentlyLocked
    ) external lockable(secs) {
        require(
            stakingDelegates[account][msg.sender],
            "Only registerd delegates can stake for their deligator"
        );
        _deposit(amount, account, secs, block.timestamp, isPermanentlyLocked);
    }

    function deposit(uint256 amount) external {
        _deposit(amount, msg.sender, 0, block.timestamp, false);
    }

    function depositAndLock(
        uint256 amount,
        uint256 secs,
        bool isPermanentlyLocked
    ) external lockable(secs) {
        _deposit(
            amount,
            msg.sender,
            secs,
            block.timestamp,
            isPermanentlyLocked
        );
    }

    function _deposit(
        uint256 amount,
        address account,
        uint256 secs,
        uint256 start_timestamp,
        bool isPermanentlyLocked
    ) internal nonReentrant updateReward(account, false) {
        require(amount > 0, "Cannot stake 0");
        uint256 MaxMultiplier = lockMultiplier(secs);
        _lockedStakes[account].push(
            LockedStake(
                start_timestamp,
                amount,
                start_timestamp + secs,
                MaxMultiplier,
                isPermanentlyLocked
            )
        );
        _lastUsedMultiplier[account][
            _lockedStakes[account].length - 1
        ] = MaxMultiplier;

        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;

        // Needed for edge case if the staker only claims once, and after the lock expired
        if (_lastRewardClaimTime[account] == 0)
            _lastRewardClaimTime[account] = block.timestamp;

        TOKEN.safeTransferFrom(account, address(this), amount);
        emit Staked(account, amount, secs, _lockedStakes[account].length - 1);
    }

    function withdraw(uint256 index) external {
        _withdraw(index);
    }

    function withdrawAll() public {
        uint256 amount = _partialWithdrawal(msg.sender, _balances[msg.sender]);
        emit WithdrawnAll(msg.sender, amount);
    }

    function partialWithdrawal(uint256 _amount) external {
        uint256 amount = _partialWithdrawal(msg.sender, _amount);
        emit WithdrawnPartilly(msg.sender, amount);
    }

    function _partialWithdrawal(address _account, uint256 _amount)
        internal
        nonReentrant
        updateReward(_account, false)
        returns (uint256)
    {
        require(
            _amount <= _balances[_account],
            "Withdraw amount exceeds balance"
        );
        uint256 amountToTransfer = 0;
        for (uint256 i = 0; i < _lockedStakes[_account].length; i++) {
            LockedStake memory thisStake = _lockedStakes[_account][i];
            // check if stake is not locked
            uint256 amountRemaining = _amount - amountToTransfer;
            if (
                thisStake.liquidity > 0 &&
                (stakesUnlocked ||
                    stakesUnlockedForAccount[_account] ||
                    (!thisStake.isPermanentlyLocked &&
                        block.timestamp >= thisStake.ending_timestamp))
            ) {
                if (thisStake.liquidity < amountRemaining) {
                    amountToTransfer += thisStake.liquidity;
                    delete _lockedStakes[_account][i];
                } else if (thisStake.liquidity == amountRemaining) {
                    amountToTransfer += thisStake.liquidity;
                    delete _lockedStakes[_account][i];
                    break;
                } else if (thisStake.liquidity > amountRemaining) {
                    _lockedStakes[_account][i].liquidity -= amountRemaining;
                    amountToTransfer = _amount;
                    break;
                }
            }
        }
        if (amountToTransfer > 0) {
            _totalSupply = _totalSupply - amountToTransfer;
            _balances[_account] = _balances[_account] - amountToTransfer;
            TOKEN.safeTransfer(msg.sender, amountToTransfer);
        }
        return amountToTransfer;
    }

    function _withdraw(uint256 index)
        internal
        nonReentrant
        updateReward(msg.sender, false)
    {
        LockedStake memory thisStake;
        thisStake.liquidity = 0;
        require(index < _lockedStakes[msg.sender].length, "Stake not found");

        thisStake = _lockedStakes[msg.sender][index];

        require(
            stakesUnlocked ||
                stakesUnlockedForAccount[msg.sender] ||
                (
                    thisStake.isPermanentlyLocked
                        ? false
                        : block.timestamp >= thisStake.ending_timestamp
                ),
            "Stake is still locked!"
        );

        uint256 liquidity = thisStake.liquidity;

        if (liquidity > 0) {
            _totalSupply = _totalSupply - liquidity;
            _balances[msg.sender] = _balances[msg.sender] - liquidity;
            delete _lockedStakes[msg.sender][index];
            TOKEN.safeTransfer(msg.sender, liquidity);
            emit Withdrawn(msg.sender, liquidity, index);
        }
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

    function notifyRewardAmount(address _rewardToken, uint256 _reward, int256[] calldata _weights, uint256 periodId)
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
            rewardTokenDetails[_rewardToken].rewardRate = (_reward + leftover) / DURATION;
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
        rewardTokenDetails[_rewardToken].periodFinish = block.timestamp + DURATION;

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
    event approvedTokenReceipt(address _spender, uint256 _amount);
    event stakeTransferd(address _to, uint256 _index);
    event allStakesTransferd(address _to);
    event RewardAdded(uint256 reward);
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 secs,
        uint256 index
    );
    event Withdrawn(address indexed user, uint256 amount, uint256 index);
    event WithdrawnAll(address indexed user, uint256 amount);
    event WithdrawnPartilly(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event LockedStakeMaxMultiplierUpdated(uint256 multiplier);
    event MaxRewardsDurationUpdated(uint256 newDuration);
}
