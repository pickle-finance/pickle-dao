// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PickleNFT is ERC721A, Ownable{

    string private baseTokenUri;

    constructor() ERC721A("Pickle", "PFP"){

    }

    function mint() external onlyOwner{
        _safeMint(msg.sender, 200);
    }

    function _baseURI() internal view override  returns (string memory) {
        return baseTokenUri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId))) : '';
    }

    function setTokenUri(string memory _baseTokenUri) external onlyOwner{
        baseTokenUri = _baseTokenUri;
    }
}