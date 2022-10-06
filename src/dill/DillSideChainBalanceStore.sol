// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.1;

contract DillSideChainBalanceStore {
    uint256[] public timeStamps;
    address public admin;
    address private _pendingAdmin;

    mapping(uint256 => mapping(address => uint256)) private _dillBalances;
    mapping(uint256 => uint256) private _totalSupply;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _admin) {
        admin = _admin;
    }

    /* ========== MODIFIERS ========== */
    modifier onlyAdmin() {
        require(msg.sender == admin, "!admin");
        _;
    }

    /* ========== VIEWS ========== */
    /**
     * @notice  Get balance of user
     * @param   _user  Address of user whose balacne is to be fetched
     * @return  uint256  Balance of user
     */
    function balanceOf(address _user) public view returns (uint256) {
        return _dillBalances[timeStamps.length - 1][_user];
    }

    /**
     * @notice  Get balance of user at given timeStamp
     * @dev     balance will be of nearest stored smaller timestamp
     * @param   _user  Address of user whose balacne is to be fetched
     * @param   _timeStamp  Timestamp at which _user's balance is to be fetched
     * @return  uint256  Balance of user at given timeStamp
     */
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

    /**
     * @notice  Get total Dill supply
     * @return  uint256  Total supply of Dill on mainnet
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply[timeStamps.length - 1];
    }

    /**
     * @notice  Get total Dill supply
     * @dev     TotalSupply will be of nearest stored smaller timestamp
     * @param   _timeStamp  Timestamp at which total Dill supply is to be fetched
     * @return  uint256  Total supply of Dill on mainnet
     */
    function totalSupplyAt(uint256 _timeStamp) public view returns (uint256) {
        require(_timeStamp <= block.timestamp, "Future time stamp provided");
        for (uint256 i = 1; i < timeStamps.length; i++) {
            if (_timeStamp < timeStamps[i]) {
                return _totalSupply[timeStamps[i - 1]];
            }
        }
        return _totalSupply[timeStamps.length - 1];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    /**
     * @notice  Set new admin 
     * @dev     This method must be followed by confirmAdmin() 
     * @param   _admin  Address of new admin
     */
    function setAdmin(address _admin) external onlyAdmin {
        _pendingAdmin = _admin;
    }

    /**
     * @notice  Confirm admin rights
     * @dev     Before this execute setAdmin(), this method must be executed by to be admin address
     */
    function confirmAdmin() external {
        require(msg.sender == _pendingAdmin, "!Pending admin");
        admin = _pendingAdmin;
        _pendingAdmin = address(0);
    }

    /**
     * @notice  Set/Update dill balances of users 
     * @param   _users  Array of addresses of users
     * @param   _values  Array of dill balances
     */
    function setUserData(address[] memory _users, uint256[] memory _values)
        external
        onlyAdmin
    {
        require(_users.length > 0, "No users provided");
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

    /* ========== EVENTS ========== */
    event dillBalancesUpdated(address[] users, uint256[] balances);
}