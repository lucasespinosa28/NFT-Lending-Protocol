// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IStash} from "../interfaces/IStash.sol";
import {IERC721 as ExternalIERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

/**
 * @title Stash
 * @author Your Name/Team
 * @notice A wrapper for specific ERC721 tokens to make them compatible.
 * This Stash contract itself is an ERC721.
 * @dev Implements IStash. This is a placeholder implementation.
 */
contract Stash is IStash, ERC721, Ownable, IERC721Receiver {
    struct StashedTokenInfo {
        address originalContract;
        uint256 originalTokenId;
        // originalOwner is implicitly the owner of the stashTokenId
        bool isStashed; // Tracks if the original token's info is actively managed here
    }

    // Mapping from stashTokenId (token ID of this ERC721 contract) to original token info
    mapping(uint256 => StashedTokenInfo) private stashedTokenDetails;

    // Mapping from original contract + original token ID to its stashTokenId
    // keccak256(abi.encodePacked(originalContract, originalTokenId)) => stashTokenId
    mapping(bytes32 => uint256) private originalToStashId;

    uint256 private stashTokenCounter; // For minting new stashTokenIds

    // Optional: If this stash is for a specific original contract
    address public immutable specificOriginalContract;
    IIPAssetRegistry public immutable iipAssetRegistry;

    constructor(
        string memory name, // Name for the wrapped ERC721 token (e.g., "Stashed CryptoPunk")
        string memory symbol, // Symbol for the wrapped ERC721 token (e.g., "sPUNK")
        address _specificOriginalContract, // address(0) if generic, else the specific contract this wraps
        address _iipAssetRegistry // New parameter
    ) ERC721(name, symbol) Ownable(msg.sender) {
        require(_iipAssetRegistry != address(0), "Stash: IIPAssetRegistry zero address");
        specificOriginalContract = _specificOriginalContract;
        iipAssetRegistry = IIPAssetRegistry(_iipAssetRegistry); // Initialize here
    }

    /**
     * @dev Internal function to check if a token ID has been minted by this Stash contract.
     * Replaces the removed _exists() from older OZ ERC721 versions for this contract's tokens.
     */
    function _isMinted(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function stash(address originalContract, uint256 originalTokenId)
        external
        override
        returns (uint256 stashTokenId)
    {
        require(originalContract != address(0), "Original contract zero address");

        // Check with Story Protocol IIPAssetRegistry
        address retrievedIpId = iipAssetRegistry.ipId(block.chainid, originalContract, originalTokenId);
        if (retrievedIpId != address(0)) {
            require(!iipAssetRegistry.isRegistered(retrievedIpId), "Stash: Token is already registered with Story Protocol");
        }

        if (specificOriginalContract != address(0)) {
            require(originalContract == specificOriginalContract, "Stash: Wrong original contract");
        }

        bytes32 originalKey = keccak256(abi.encodePacked(originalContract, originalTokenId));
        require(originalToStashId[originalKey] == 0, "Token already stashed");

        // Take ownership of the original NFT
        ExternalIERC721(originalContract).safeTransferFrom(msg.sender, address(this), originalTokenId);

        stashTokenCounter++;
        stashTokenId = stashTokenCounter;

        stashedTokenDetails[stashTokenId] = StashedTokenInfo({
            originalContract: originalContract,
            originalTokenId: originalTokenId,
            isStashed: true // Mark that this stash token ID has associated original token data
        });
        originalToStashId[originalKey] = stashTokenId;

        _mint(msg.sender, stashTokenId); // Mint the wrapped token to the stasher

        emit TokenStashed(originalContract, originalTokenId, msg.sender, stashTokenId);
        return stashTokenId;
    }

    function unstash(uint256 stashTokenId) external override {
        require(_isMinted(stashTokenId), "Stash token does not exist"); // Check if this Stash contract's token exists
        require(ownerOf(stashTokenId) == msg.sender, "Not owner of stash token");

        StashedTokenInfo storage info = stashedTokenDetails[stashTokenId];
        require(info.isStashed, "Token not actively stashed or already unstashed");

        address originalContract = info.originalContract;
        uint256 originalTokenId = info.originalTokenId;

        // Burn the wrapped token
        _burn(stashTokenId);

        // Clean up state
        bytes32 originalKey = keccak256(abi.encodePacked(originalContract, originalTokenId));
        delete originalToStashId[originalKey];
        // Instead of deleting the struct, mark as not stashed to prevent re-use of stashTokenId with old data
        // Or ensure stashTokenCounter never re-uses IDs. Deleting is fine if IDs are unique.
        delete stashedTokenDetails[stashTokenId];

        // Return the original NFT to the unstasher (msg.sender)
        ExternalIERC721(originalContract).safeTransferFrom(address(this), msg.sender, originalTokenId);

        emit TokenUnstashed(stashTokenId, originalContract, originalTokenId, msg.sender);
    }

    function getOriginalTokenInfo(uint256 stashTokenId)
        external
        view
        override
        returns (address originalContract, uint256 originalTokenId, address owner)
    {
        require(_isMinted(stashTokenId), "Stash token does not exist"); // Check if this Stash contract's token exists
        StashedTokenInfo storage info = stashedTokenDetails[stashTokenId];
        require(info.isStashed, "Stash info missing or token unstashed"); // Ensure the mapping has valid data
        return (info.originalContract, info.originalTokenId, ownerOf(stashTokenId));
    }

    function isStashed(address originalContract, uint256 originalTokenId)
        external
        view
        override
        returns (bool, uint256 stashTokenId)
    {
        bytes32 originalKey = keccak256(abi.encodePacked(originalContract, originalTokenId));
        stashTokenId = originalToStashId[originalKey];
        // A token is stashed if its originalKey maps to a non-zero stashTokenId
        // AND that stashTokenId actually exists and its details confirm it's active.
        if (stashTokenId != 0 && _isMinted(stashTokenId) && stashedTokenDetails[stashTokenId].isStashed) {
            return (true, stashTokenId);
        }
        return (false, 0);
    }

    // Required by OpenZeppelin ERC721
    function _baseURI() internal view override returns (string memory) {
        return "api/stash/"; // Placeholder
    }

    // IERC721Receiver (for receiving the original NFTs)
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IStash).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
