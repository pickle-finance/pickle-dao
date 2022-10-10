// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGaugeProxyV2 {
    function isStaked(address account) external view returns (bool);

    function getTokenLevel(address account) external view returns (uint256);

    function isBoostable(address account) external view returns (bool);
}

abstract contract BaseGaugeV2 is ProtocolGovernance, ReentrancyGuard {
    
    /// @notice Token addresses
    IERC20 public constant DILL =
        IERC20(0xbBCf169eE191A1Ba7371F30A1C344bFC498b29Cf);

    /// @notice Constant for various precisions
    uint256 public constant DURATION = 7 days;
    uint256 public multiplierDecayPerSecond = uint256(48e9);
    uint256 internal constant _MultiplierPrecision = 1e18;

    /// @notice Lock time and multiplier
    uint256 public lockMaxMultiplier = uint256(25e17); // E18. 1x = e18
    uint256 public lockTimeForMaxMultiplier = 365 * 86400; // 1 year
    uint256 public lockTimeMin = 86400; // 1 day
    
    /// @notice Reward addresses
    address[] public rewardTokens;

    /// @notice Balance tracking
    uint256 public derivedSupply;

    // Release locked stakes in case of emergency; Administrative booleans
    bool internal stakesUnlocked;    

    /* ========== STRUCTS ========== */

    /// @notice Locked stake details
    struct LockedStake {
        uint256 startTimestamp;
        uint256 liquidity;
        uint256 endingTimestamp;
        uint256 lock_multiplier;
        bool isPermanentlyLocked;
    }

    /// @notice Reward token details
    struct rewardTokenDetail {
        uint256 index;
        bool isActive;
        address distributor;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 periodFinish;
    }

    /* ========== MAPPINGS ========== */
    mapping(address => rewardTokenDetail) public rewardTokenDetails; // token address => detatils
    mapping(address => mapping(uint256 => uint256))
        internal _userRewardPerTokenPaid;
    mapping(address => mapping(uint256 => uint256)) public rewards;
    mapping(address => uint256) internal _lastUsedMultiplier;
    mapping(address => uint256) internal _lastRewardClaimTime; // staker addr -> timestamp
    mapping(address => uint256) public derivedBalances;
    mapping(address => uint256) internal _base;
    mapping(address => bool) public stakesUnlockedForAccount; // Release locked stakes of an account in case of emergency
    mapping(address => LockedStake) internal _lockedStakes; // Stake tracking

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

    /* ========== MUTATIVE FUNCTIONS ========== */

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
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];

        require(token.isActive, "Reward token not available");
        require(
            token.distributor != _distributionForToken,
            "Given address is already distributor for given reward token"
        );
        token.distributor = _distributionForToken;
        rewardTokenDetails[_rewardToken] = token;
    }

    /// @notice Unlock stakes for all users
    function unlockStakes() external onlyGov {
        stakesUnlocked = !stakesUnlocked;
    }

    /**
     * @notice  Unlock stakes for a particular user
     * @param   _account  Address of user whose stake is to be uncloked
     */
    function unlockStakeForAccount(address _account) external onlyGov {
        stakesUnlockedForAccount[_account] = !stakesUnlockedForAccount[
            _account
        ];
    }

    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount, uint256 secs);
}