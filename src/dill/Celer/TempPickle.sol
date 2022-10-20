pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TempPickle is ERC20 {
    constructor(uint256 initialSupply) ERC20("TempPickle", "TPICKLE") {
        _mint(msg.sender, initialSupply);
}
}