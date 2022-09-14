// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.1;

contract DillSideChain {
    mapping(address => uint256) public dillBalances;
    uint256 public totalSupply;

    address public admin;
    address private _pendingAdmin;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "!admin");
        _;
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
    ) public onlyAdmin {
        require(
            _users.length == _values.length,
            "Number of users and values do not match"
        );
        if (_users.length > 0) {
            for (uint256 i = 0; i < _users.length; i++) {
                totalSupply -= dillBalances[_users[i]];
                dillBalances[_users[i]] = _values[i];
                totalSupply += dillBalances[_users[i]];
            }
            emit dillBalancesUpdated(_users, _values);
        }

    }

    event dillBalancesUpdated(address[] users, uint256[] balances);
}
