// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../../ProtocolGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IAnycallClient {
    function bridge(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId
    ) external payable;

    function calcFees(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId,
        int256[] memory weights,
        uint256 periodId
    ) external view returns(uint256);
}

contract AnyswapRootGauge is ProtocolGovernance, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public constant PICKLE =
        IERC20(0x429881672B9AE42b8EbA0E26cD9C73711b891Ca5);

    // Constant for various precisions
    uint256 public constant DURATION = 7 days;
    uint256 public chainId;
    address public sidechainGaugeProxy;

    //Reward addresses
    address[] public rewardTokens;

    IAnycallClient public anycallClient;

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

    /* ========== CONSTRUCTOR ========== */

    constructor(address _anycallClient, uint256 _chainId, address _sidechainGaugeProxy) {
        anycallClient = IAnycallClient(_anycallClient);
        chainId = _chainId;
        governance = msg.sender;
        sidechainGaugeProxy = _sidechainGaugeProxy;
    }

    /* ========== VIEWS ========== */

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

    function notifyRewardAmount(address _rewardToken, uint256 _reward, int256[] calldata _weights, uint256 periodId)
        external
        onlyDistribution(_rewardToken)
    {
        rewardTokenDetail memory token = rewardTokenDetails[_rewardToken];
        require(token.isActive, "Reward token not available");
        require(
            token.distributor != address(0),
            "Reward distributor for token not available"
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

        uint256 fee = anycallClient.calcFees(
            address(PICKLE),
            _reward,
            sidechainGaugeProxy,
            chainId,
            _weights,
            periodId
        );

        require(fee <= address(this).balance, "insufficient fee");

        anycallClient.bridge{value: fee}(
            address(PICKLE),
            _reward,
            sidechainGaugeProxy,
            chainId,
            _weights,
            periodId
        );
        rewardTokenDetails[_rewardToken] = token;
    }

    receive() external payable {}

    /* ========== EVENTS ========== */
    event RewardAdded(uint256 reward);
}