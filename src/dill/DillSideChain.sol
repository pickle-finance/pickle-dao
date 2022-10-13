// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.1;

contract DillSideChain {
    mapping(uint256 => mapping(address => uint256)) private _dillBalances;
    mapping(uint256 => uint256) private _totalSupply;
    uint256[] public timeStamps;

    address public admin;
    address private _pendingAdmin;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "!admin");
        _;
    }

    function balanceOf(address _user) public view returns (uint256) {
        return _dillBalances[timeStamps.length - 1][_user];
    }

    function balanceOfAt(address _user, uint256 _timeStamp)
        public
        view
        returns (uint256)
    {
        require(_timeStamp <= block.timestamp, "Future time stamp provided");
        for (uint256 i = 1; i < timeStamps.length; i++) {
            if (_timeStamp < timeStamps[i]) {
                return _dillBalances[timeStamps[i - 1]][_user];
            }
        }
        return _dillBalances[timeStamps.length - 1][_user];
    }

    function totalSupply()
        public
        view
        returns (uint256)
    {
        return _totalSupply[timeStamps.length - 1];
    }

    function totalSupplyAt(uint256 _timeStamp) public view returns (uint256) {
        require(_timeStamp <= block.timestamp, "Future time stamp provided");
        for (uint256 i = 1; i < timeStamps.length; i++) {
            if (_timeStamp < timeStamps[i]) {
                return _totalSupply[timeStamps[i - 1]];
            }
        }
        return _totalSupply[timeStamps.length - 1];
    }

    function setAdmin(address _admin) external onlyAdmin {
        _pendingAdmin = _admin;
    }

    function confirmAdmin() external {
        require(msg.sender == _pendingAdmin, "!Pending admin");
        admin = _pendingAdmin;
        _pendingAdmin = address(0);
    }

    function setUserData(
        address[] memory _users,
        uint256[] memory _values
    ) external onlyAdmin {
        require(_users.length > 0 , "No users provided");
        require(
            _users.length == _values.length,
            "Number of users and balances do not match"
        );

        uint256 _timeStamp = block.timestamp;
        //copy previous totalSupply
        _totalSupply[_timeStamp] = _totalSupply[timeStamps.length - 1];

        for (uint256 i = 0; i < _users.length; i++) {
            _totalSupply[_timeStamp] -= _dillBalances[_timeStamp][_users[i]];
            _dillBalances[_timeStamp][_users[i]] = _values[i];
            _totalSupply[_timeStamp] += _values[i];
        }
        timeStamps.push(_timeStamp);
        emit dillBalancesUpdated(_users, _values);
    }

    event dillBalancesUpdated(address[] users, uint256[] balances);
}
