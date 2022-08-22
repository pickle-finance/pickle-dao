// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "../ProtocolGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IGaugeMiddleware {
    function addGauge(address _token, address _governance)
        external
        returns (address);
}

interface IVirtualGaugeMiddleware {
    function addVirtualGauge(address _jar, address _governance)
        external
        returns (address);
}

interface iGaugeV2 {
    function notifyRewardAmount(
        address rewardToken,
        uint256 rewards,
        int256[] memory weights
    ) external;
}

contract SidechainGaugeProxy is ProtocolGovernance, Initializable {
    using SafeERC20 for IERC20;

    IERC20 public PICKLE;

    address[] internal _tokens;
    address bridgeClient;

    enum GaugeType { REGULAR, VIRTUAL }

    struct Gauge {
        GaugeType gaugeType;
        address gaugeAddress;
    }

    // token => gauge
    mapping(address => Gauge) public gauges;
    mapping(uint256 => uint256) public periodRewardAmount;
    mapping(uint256 => int256[]) public periodGaugeWeights;

    IGaugeMiddleware public gaugeMiddleware;
    IVirtualGaugeMiddleware public virtualGaugeMiddleware;

    struct Queue {
        uint[] data;
        uint front;
        uint back;
    }

    /// @dev the number of elements stored in the queue.
    function length(Queue storage q) view internal returns (uint) {
        return q.back - q.front;
    }
    /// @dev the number of elements this queue can hold
    function capacity(Queue storage q) view internal returns (uint) {
        return q.data.length - 1;
    }
    /// @dev push a new element to the back of the queue
    function pushToPeriodQueue(Queue storage q, uint data) internal
    {
        if ((q.back + 1) % q.data.length == q.front)
            return; // throw;
        q.data[q.back] = data;
        q.back = (q.back + 1) % q.data.length;
    }
    /// @dev remove and return the element at the front of the queue
    function popFromPeriodQueue(Queue storage q) internal returns (uint r)
    {
        require(q.back > q.front, "Back <= Front");
        r = q.data[q.front];
        delete q.data[q.front];
        q.front = (q.front + 1) % q.data.length;
    }

    Queue periodQueue;

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function getGauge(address _token) external view returns (Gauge memory) {
        return gauges[_token];
    }

    function initialize(address pickleToken, address _bridgeClient) public initializer {
        governance = msg.sender;
        PICKLE = IERC20(pickleToken);
        bridgeClient = _bridgeClient;
    }

    function addGaugeMiddleware(address _gaugeMiddleware) external {
        require(
            _gaugeMiddleware != address(0),
            "gaugeMiddleware cannot set to zero"
        );
        require(
            _gaugeMiddleware != address(gaugeMiddleware),
            "current and new gaugeMiddleware are same"
        );
        require(msg.sender == governance, "!gov");
        gaugeMiddleware = IGaugeMiddleware(_gaugeMiddleware);
    }

    function addVirtualGaugeMiddleware(address _virtualGaugeMiddleware)
        external
    {
        require(
            _virtualGaugeMiddleware != address(0),
            "virtualGaugeMiddleware cannot set to zero"
        );
        require(
            _virtualGaugeMiddleware != address(virtualGaugeMiddleware),
            "current and new virtualGaugeMiddleware are same"
        );
        require(msg.sender == governance, "!gov");
        virtualGaugeMiddleware = IVirtualGaugeMiddleware(
            _virtualGaugeMiddleware
        );
    }

    // Add new token gauge
    function addGauge(address _token) external {
        require(msg.sender == governance, "!gov");
        require(
            address(gaugeMiddleware) != address(0),
            "cannot add new gauge without initializing gaugeMiddleware"
        );
        Gauge memory _gauge = gauges[_token];
        require(gauges[_token].gaugeAddress == address(0x0), "exists");
        
        _gauge.gaugeAddress = gaugeMiddleware.addGauge(_token, governance);
        _gauge.gaugeType = GaugeType.REGULAR;
        
        _tokens.push(_token);
    }

    // Add new token virtual gauge
    function addVirtualGauge(address _token, address _jar) external {
        require(msg.sender == governance, "!gov");
        require(
            address(gaugeMiddleware) != address(0),
            "cannot add new gauge without initializing gaugeMiddleware"
        );
        Gauge memory _gauge = gauges[_token];

        require(_gauge.gaugeAddress == address(0x0), "exists");

        _gauge.gaugeAddress = virtualGaugeMiddleware.addVirtualGauge(
            _jar,
            governance
        );
        _gauge.gaugeType = GaugeType.VIRTUAL;

        _tokens.push(_token);
    }

    function distribute(uint256 _start, uint256 _end) external {
        require(_start < _end, "SidechainGaugeProxy: bad _start");
        require(_end <= _tokens.length, "SidechainGaugeProxy: bad _end");
        require(
            msg.sender == governance,
            "GaugeProxyV2: only governance can distribute"
        );

        uint256 periodToDistribute = periodQueue.data[periodQueue.front];

        int256[] memory _weights = periodGaugeWeights[periodToDistribute];
        int256 _totalWeight = 0;

        int256 _balance = int256(periodRewardAmount[periodToDistribute]);

        for (uint256 i = 0; i < _weights.length; i++) {
            _totalWeight += (_weights[i] > 0 ? _weights[i] : -_weights[i]);
        }

        if (_balance > 0 && _totalWeight > 0 && _start < _weights.length) {
            for (uint256 i = _start; i < _end; i++) {
                if (i == _weights.length) break;

                address _token = _tokens[i];
                Gauge memory _gauge = gauges[_token];
                
                address _gaugeAddress = _gauge.gaugeAddress;

                int256 _reward = (_balance * _weights[i]) /
                    _totalWeight;

                if (_reward > 0) {
                    uint256 reward_ = uint256(_reward);
                    PICKLE.safeApprove(_gaugeAddress, 0);
                    PICKLE.safeApprove(_gaugeAddress, reward_);
                    iGaugeV2(_gaugeAddress).notifyRewardAmount(address(PICKLE), reward_, new int256[](0));
                }
            }
        }
        if (_tokens.length == _end) {
            popFromPeriodQueue(periodQueue);
        }
    }

    function sendRewards(uint256 periodId, uint256 amount, int256[] memory _weights) external {
        require(msg.sender == bridgeClient, "!bridgeClient");
        require(_weights.length == _tokens.length, "invalid weights length");

        PICKLE.safeTransferFrom(msg.sender, address(this), amount);
        
        pushToPeriodQueue(periodQueue, periodId);
        periodRewardAmount[periodId] = amount;
        periodGaugeWeights[periodId] = _weights;
    }
}
