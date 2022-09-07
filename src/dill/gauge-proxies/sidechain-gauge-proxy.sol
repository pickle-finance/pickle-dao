// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
// import "@openzeppelin/contracts/interfaces/IERC20Upgradeable.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface iGaugeV2 {
    function notifyRewardAmount(
        address rewardToken,
        uint256 rewards,
        int256[] memory weights,
        uint256 periodId
    ) external;
}

contract SidechainGaugeProxy is ProtocolGovernance, Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public PICKLE;

    address[] internal _tokens;
    address bridgeClient;

    enum GaugeType {
        REGULAR,
        VIRTUAL
    }

    struct Gauge {
        GaugeType gaugeType;
        address gaugeAddress;
    }

    mapping(address => Gauge) public gauges;
    mapping(uint256 => uint256) public periodRewardAmount;
    mapping(uint256 => int256[]) public periodGaugeWeights;

    struct periodData {
        uint256 amount;
        int256[] weights;
    }
    mapping(uint256 => periodData) public periods; // periodID => periodData
    mapping(uint256 => bool) public distributedForPeriod;
    uint256 public periodToDistribute;

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function getGauge(address _token) external view returns (Gauge memory) {
        return gauges[_token];
    }

    function initialize(
        address pickleToken,
        address _bridgeClient,
        uint256 _periodToDistribute
    ) public initializer {
        periodToDistribute = _periodToDistribute;
        governance = msg.sender;
        PICKLE = IERC20Upgradeable(pickleToken);
        bridgeClient = _bridgeClient;
    }

    // Add new token gauge
    function addGauge(address _token, address _gaugeAddress) external {
        require(msg.sender == governance, "!gov");
        require(gauges[_token].gaugeAddress == address(0x0), "exists");

        gauges[_token].gaugeAddress = _gaugeAddress;
        gauges[_token].gaugeType = GaugeType.REGULAR;

        _tokens.push(_token);
    }

    // Add new token virtual gauge
    function addVirtualGauge(
        address _token,
        address _jar,
        address _gaugeAddress
    ) external {
        require(msg.sender == governance, "!gov");

        require(gauges[_token].gaugeAddress == address(0x0), "exists");

        gauges[_token].gaugeAddress = _gaugeAddress;
        gauges[_token].gaugeType = GaugeType.VIRTUAL;

        _tokens.push(_token);
    }

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
                    iGaugeV2(_gaugeAddress).notifyRewardAmount(
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
