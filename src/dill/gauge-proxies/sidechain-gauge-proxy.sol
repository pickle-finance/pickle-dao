// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IGaugeV2 {
    function notifyRewardAmount(
        address rewardToken,
        uint256 rewards,
        int256[] memory weights,
        uint256 periodId
    ) external;
}

contract SidechainGaugeProxy is ProtocolGovernance, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public periodToDistribute;
    address[] internal _tokens;
    address bridgeClient;

    /* ========== ENUM & STRUCTS ========== */
    enum GaugeType {
        REGULAR,
        VIRTUAL
    }

    struct Gauge {
        GaugeType gaugeType;
        address gaugeAddress;
    }

    struct periodData {
        uint256 amount;
        int256[] weights;
    }

    /* ========== MAPPINGS ========== */
    mapping(address => Gauge) public gauges;
    mapping(uint256 => uint256) public periodRewardAmount;
    mapping(uint256 => int256[]) public periodGaugeWeights;
    mapping(uint256 => periodData) public periods; // periodID => periodData
    mapping(uint256 => bool) public distributedForPeriod;

    IERC20Upgradeable public PICKLE;

    /* ========== VIEWS ========== */
    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function getGauge(address _token) external view returns (Gauge memory) {
        return gauges[_token];
    }

    /* ========== INITIALIZER ========== */
    /**
     * @notice  Initializer
     * @param   _pickleToken  Address of pickle token on sidechain
     * @param   _bridgeClient  Address of Anycall bridge client
     * @param   _periodToDistribute  Initial period to start distribution from
     */
    function initialize(
        address _pickleToken,
        address _bridgeClient,
        uint256 _periodToDistribute
    ) public initializer {
        periodToDistribute = _periodToDistribute;
        governance = msg.sender;
        PICKLE = IERC20Upgradeable(_pickleToken);
        bridgeClient = _bridgeClient;
    }

      /**
     * @notice  Add new gauge
     * @param   _token  Address of gauge token
     * @param   _gaugeAddress  Address of gauge
     */
    function addGauge(address _token, address _gaugeAddress) external {
        require(msg.sender == governance, "!gov");
        require(gauges[_token].gaugeAddress == address(0x0), "exists");

        gauges[_token].gaugeAddress = _gaugeAddress;
        gauges[_token].gaugeType = GaugeType.REGULAR;

        _tokens.push(_token);
    }

       /**
     * @notice  Add new virtual gauge
     * @param   _token  Address of gauge token
     * @param   _gaugeAddress  Address of gauge
     */
    function addVirtualGauge(
        address _token,
        address _gaugeAddress
    ) external {
        require(msg.sender == governance, "!gov");

        require(gauges[_token].gaugeAddress == address(0x0), "exists");

        gauges[_token].gaugeAddress = _gaugeAddress;
        gauges[_token].gaugeType = GaugeType.VIRTUAL;

        _tokens.push(_token);
    }

    /**
     * @notice  Distribute rewards to gauges
     * @dev     _start and _end are taken to avoid out of gas error in case large number of gauges are listed
     * @param   _start  Starting index of gauges
     * @param   _end  Ending index of gauges
     */
    function distribute(uint256 _start, uint256 _end) external {
        require(_start < _end, "SidechainGaugeProxy: bad _start");
        require(_end <= _tokens.length, "SidechainGaugeProxy: bad _end");
        require(
            msg.sender == governance,
            "GaugeProxyV2: only governance can distribute"
        );
        uint256 _periodToDistribute = periodToDistribute;
        require(
            distributedForPeriod[_periodToDistribute] == false,
            "Already distributed for given period"
        );
        require(
            periods[_periodToDistribute].weights.length == 0 &&
                periods[_periodToDistribute].amount == 0,
            "All period distribution compleated"
        );
        int256[] memory _weights = periods[periodToDistribute].weights;
        int256 _totalWeight = 0;

        int256 _balance = int256(periods[periodToDistribute].amount);

        for (uint256 i = 0; i < _weights.length; i++) {
            _totalWeight += (_weights[i] > 0 ? _weights[i] : -_weights[i]);
        }

        if (_balance > 0 && _totalWeight > 0 && _start < _weights.length) {
            for (uint256 i = _start; i < _end; i++) {
                if (i == _weights.length) break;

                address _token = _tokens[i];
                Gauge memory _gauge = gauges[_token];

                address _gaugeAddress = _gauge.gaugeAddress;

                int256 _reward = (_balance * _weights[i]) / _totalWeight;

                if (_reward > 0) {
                    uint256 reward_ = uint256(_reward);
                    PICKLE.safeApprove(_gaugeAddress, 0);
                    PICKLE.safeApprove(_gaugeAddress, reward_);
                    IGaugeV2(_gaugeAddress).notifyRewardAmount(
                        address(PICKLE),
                        reward_,
                        new int256[](0),
                        _periodToDistribute
                    );
                }
            }
        }
        if (_tokens.length == _end) {
            distributedForPeriod[_periodToDistribute] = true;
            periodToDistribute += 1;
        }
    }

    /**
     * @notice  Fetch rewards data 
     * @param   _periodId  PeriodId for which rewards data is fetched
     * @param   _amount  Amount to be distributed for _periodId's distribution
     * @param   _weights  Gauge weights for _periodId 
     */
    function sendRewards(
        uint256 _periodId,
        uint256 _amount,
        int256[] memory _weights
    ) external {
        require(msg.sender == bridgeClient, "!bridgeClient");
        require(_weights.length == _tokens.length, "invalid weights length");
        require(
            distributedForPeriod[_periodId] == false,
            "Already distributed for given period"
        );
        periodData memory period = periods[periodToDistribute];
        require(
            period.weights.length == 0 && period.amount == 0,
            "already added reward for period"
        );

        periods[_periodId].amount = _amount;
        periods[_periodId].weights = _weights;
    }
}
