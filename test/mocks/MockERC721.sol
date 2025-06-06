// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "solmate/tokens/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function tokenURI(uint256) public pure virtual override returns (string memory) {
        return "";
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
