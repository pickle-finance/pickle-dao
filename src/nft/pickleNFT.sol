// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev Design to mint nfts in batch use erc721a concept
 * Mint to owne only 
 */

contract PickleNFT is ERC721A, Ownable{

    string private baseTokenUri;
    mapping(uint256 => uint8) tokenLevel;

    event TokenLevelUpdate(uint256 tokenId, level);

    constructor() ERC721A("Pickle", "PFP"){

    }

    /**
     * @dev Safely mints `quantity` tokens and transfers them to `to`.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement
     * {IERC721Receiver-onERC721Received}, which is called for each safe transfer.
     * - `quantity` must be greater than 0.
     *
     *
     * Emits a {Transfer} event for each mint.
     */
    function mint() external onlyOwner{
        _safeMint(msg.sender, 200);
    }

    /**
     * @dev Return base url of meta data
     */
    function _baseURI() internal view override  returns (string memory) {
        return baseTokenUri;
    }

    /**
     * @dev concat base url with particular token id
     * @return tokenUri : token id appended with base url 
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, _toString(tokenId))) : '';
    }

    /**
     * @dev set new base url can be perform by owner only
     */
    function setTokenUri(string memory _baseTokenUri) external onlyOwner{
        baseTokenUri = _baseTokenUri;
    }

    function setTokenLevel(uint256 _tokenId, uint256 _level) external onlyOwner {
        require(_level > 0 , "PickleNFT : Level varies between 1 to 100";)
        require(_level < 101 , "PickleNFT : Level varies between 1 to 100";)
        tokenLevel[_tokenId] = _level;
        emit TokenLevelUpdate(_tokenId, _level);
    }

    function getTokenLevel(uint256 _tokenId) external view returns(uint256) {
        require(_exists(tokenId), "PickleNFT : Level query for nonexistent token");
        return tokenLevel[_tokenId];
    }

} 