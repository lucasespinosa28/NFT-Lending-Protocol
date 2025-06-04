// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IStash
 * @author Your Name/Team
 * @notice Interface for a wrapper contract (Stash) to make older or non-standard
 * ERC721 tokens compatible with the lending protocol.
 * The Stash contract would itself be an ERC721, minting a new "wrapped" token
 * when an original token is deposited.
 */
interface IStash is
    IERC721 // The Stash itself is an ERC721
{
    // --- Events ---
    event TokenStashed( // Removed indexed from here
        // The new token ID minted by this Stash contract
    address indexed originalContract, uint256 originalTokenId, address indexed stasher, uint256 indexed stashTokenId);

    event TokenUnstashed( // The token ID burned by this Stash contract
    uint256 indexed stashTokenId, address indexed originalContract, uint256 originalTokenId, address indexed unstasher);

    // --- Functions ---

    /**
     * @notice Deposits an original NFT into the Stash and mints a new, wrapped ERC721 token to the depositor.
     * @dev The Stash contract takes ownership of the original NFT.
     * @param originalContract The address of the original NFT contract.
     * @param originalTokenId The token ID of the original NFT.
     * @return stashTokenId The token ID of the newly minted wrapped NFT from this Stash contract.
     */
    function stash(address originalContract, uint256 originalTokenId) external returns (uint256 stashTokenId);

    /**
     * @notice Burns a wrapped NFT (stashTokenId) and returns the original NFT to the owner.
     * @dev Caller must be the owner of the stashTokenId.
     * @param stashTokenId The token ID of the wrapped NFT to burn.
     */
    function unstash(uint256 stashTokenId) external;

    /**
     * @notice Retrieves information about the original token stashed for a given stashTokenId.
     * @param stashTokenId The token ID of the wrapped NFT.
     * @return originalContract Address of the original NFT contract.
     * @return originalTokenId Token ID of the original NFT.
     * @return owner The current owner of the stashed (wrapped) token.
     */
    function getOriginalTokenInfo(uint256 stashTokenId)
        external
        view
        returns (address originalContract, uint256 originalTokenId, address owner);

    /**
     * @notice Checks if a given original token is currently stashed.
     * @param originalContract The address of the original NFT contract.
     * @param originalTokenId The token ID of the original NFT.
     * @return True if the token is stashed, false otherwise.
     * @return stashTokenId If stashed, returns the corresponding stash token ID.
     */
    function isStashed(address originalContract, uint256 originalTokenId)
        external
        view
        returns (bool, uint256 stashTokenId);

    /**
     * @notice The address of the original NFT contract this Stash is designed to wrap.
     * Some stashes might be generic, others specific to one original contract.
     * If generic, this might return address(0) or not exist.
     * If specific, it helps identify the Stash's purpose.
     */
    // function originalTokenContract() external view returns (address); // Optional
}
