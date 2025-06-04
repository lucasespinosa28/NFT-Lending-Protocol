// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IVaultsFactory
 * @author Your Name/Team
 * @notice Interface for creating and managing NFT vaults (bundling multiple NFTs).
 * @dev Vaults themselves would likely be ERC721 tokens.
 */
interface IVaultsFactory {
    // --- Events ---
    event VaultCreated(
        uint256 indexed vaultId,
        address indexed owner,
        address[] nftContracts,
        uint256[] tokenIds,
        uint256[] amounts // For ERC1155
    );
    event VaultContentAdded(
        uint256 indexed vaultId,
        address[] nftContracts,
        uint256[] tokenIds,
        uint256[] amounts // For ERC1155
    );
    event VaultContentRemoved(
        uint256 indexed vaultId,
        address[] nftContracts,
        uint256[] tokenIds,
        uint256[] amounts // For ERC1155
    );
    // Note: Burning a vault to add more NFTs seems counterintuitive.
    // Usually, you'd add to an existing vault or burn it to retrieve all contents.
    // The description says "burnVault ... to add more NFTs". This might mean
    // "unwrap (burn) the old vault, create a new one with the old + new NFTs".
    // Or it could be a misinterpretation and it means "add to vault".
    // I'll assume "add to vault" for now. "Burn" usually means destroy.
    // If "burnVault" truly means destroy to re-bundle, the event might be VaultDestroyedAndRecreated.

    struct NFTItem {
        address contractAddress;
        uint256 tokenId;
        uint256 amount; // 1 for ERC721, actual amount for ERC1155
        bool isERC1155;
    }

    // --- Functions ---

    /**
     * @notice Allows a user to create a new vault containing specified NFTs.
     * @dev The factory mints a new ERC721 (the vault token) to the user.
     * @dev NFTs are transferred from the user to the vault contract (or held by this factory in escrow for the vault).
     * @param owner The intended owner of the new vault.
     * @param nftItems Array of NFTItem structs representing NFTs to be bundled.
     * @return vaultId The token ID of the newly minted vault ERC721.
     */
    function mintVault(
        address owner,
        NFTItem[] calldata nftItems
    ) external returns (uint256 vaultId);

    /**
     * @notice Allows adding more NFTs to an existing vault.
     * @dev Requires the caller to be the owner of the vault and to approve NFTs for transfer.
     * @param vaultId The ID of the vault to add content to.
     * @param nftItems Array of NFTItem structs representing NFTs to be added.
     */
    function addContentToVault(
        uint256 vaultId,
        NFTItem[] calldata nftItems
    ) external;

    /**
     * @notice Allows removing specific NFTs from an existing vault.
     * @dev Requires the caller to be the owner of the vault.
     * @dev NFTs are transferred from the vault contract back to the owner.
     * @param vaultId The ID of the vault to remove content from.
     * @param nftItems Array of NFTItem structs representing NFTs to be removed.
     */
    function removeContentFromVault(
        uint256 vaultId,
        NFTItem[] calldata nftItems
    ) external;

    /**
     * @notice Allows the owner to burn (destroy) a vault and retrieve all its contents.
     * @dev Transfers all contained NFTs back to the vault owner. Burns the vault ERC721 token.
     * @param vaultId The ID of the vault to burn.
     */
    function burnVault(uint256 vaultId) external;


    /**
     * @notice Retrieves the NFTs contained within a specific vault.
     * @param vaultId The ID of the vault.
     * @return An array of NFTItem structs representing the vault's content.
     */
    function getVaultContent(uint256 vaultId) external view returns (NFTItem[] memory);

    /**
     * @notice Checks if a given token ID represents a valid vault managed by this factory.
     * @param vaultId The token ID to check.
     * @return True if it's a valid vault, false otherwise.
     */
    function isVault(uint256 vaultId) external view returns (bool);

    /**
     * @notice Gets the owner of a specific vault.
     * @param vaultId The ID of the vault.
     * @return The address of the vault owner.
     */
    function ownerOfVault(uint256 vaultId) external view returns (address);
}
