// SPDX-License-Identifier: MIT
// Based on OpenZeppelin Contracts (last updated v4.9.3) (mocks/token/ERC721Mock.sol)
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/mocks/token/ERC721Mock.sol

pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

/**
 * @title ERC721Mock
 * @dev Basic ERC721 mock contract with minting, burning, and enumeration capabilities.
 * Useful for testing environments.
 */
contract ERC721Mock is ERC721, ERC721Enumerable, ERC721Burnable {
    uint256 private _nextTokenId;

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}

    /**
     * @dev Mints a new token for `to`.
     * The token ID is automatically assigned and incremented.
     * Emits a {Transfer} event.
     */
    function mint(address to) public virtual returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev Mints a new token with a specific `tokenId` for `to`.
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `tokenId` must not already exist.
     */
    function mint(address to, uint256 tokenId) public virtual {
        _safeMint(to, tokenId);
        if (tokenId >= _nextTokenId) {
            _nextTokenId = tokenId + 1;
        }
    }

    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be approved to manage it.
     */
    function burn(uint256 tokenId) public virtual override {
        super.burn(tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "mock://token/";
    }

    /**
     * @dev See {ERC721-_increaseBalance}.
     */
    function _increaseBalance(address account, uint128 amount) internal virtual override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }

    /**
     * @dev See {ERC721-_update}.
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}

