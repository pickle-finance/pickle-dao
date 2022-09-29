// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./IERC721A.sol";

interface IPickleNFT is IERC721A {
    function getTokenLevel(uint256 _tokenId) external view returns (uint256);
}
