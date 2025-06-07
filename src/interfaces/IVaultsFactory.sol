// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IVaultsFactory
 * @author Lucas Espinosa
 * @notice Interface for creating and managing NFT vaults (bundling multiple NFTs).
 * @dev Vaults themselves would likely be ERC721 tokens.
 */
interface IVaultsFactory {
    // --- Events ---

    /**
     * @notice Emitted when a new vault is created.
     * @param vaultId The ID of the created vault.
     * @param owner The address of the vault owner.
     * @param nftContracts The addresses of NFT contracts included in the vault.
     * @param tokenIds The token IDs of NFTs included in the vault.
     * @param amounts The amounts of each NFT (1 for ERC721, >1 for ERC1155).
     */
    event VaultCreated(
        uint256 indexed vaultId, address indexed owner, address[] nftContracts, uint256[] tokenIds, uint256[] amounts
    );

    /**
     * @notice Emitted when content is added to a vault.
     * @param vaultId The ID of the vault.
     * @param nftContracts The addresses of NFT contracts added.
     * @param tokenIds The token IDs of NFTs added.
     * @param amounts The amounts of each NFT added.
     */
    event VaultContentAdded(
        uint256 indexed vaultId, address[] nftContracts, uint256[] tokenIds, uint256[] amounts
    );

    /**
     * @notice Emitted when content is removed from a vault.
     * @param vaultId The ID of the vault.
     * @param nftContracts The addresses of NFT contracts removed.
     * @param tokenIds The token IDs of NFTs removed.
     * @param amounts The amounts of each NFT removed.
     */
    event VaultContentRemoved(
        uint256 indexed vaultId, address[] nftContracts, uint256[] tokenIds, uint256[] amounts
    );

    /**
     * @notice Struct representing an NFT item to be included in a vault.
     * @param contractAddress The address of the NFT contract.
     * @param tokenId The token ID of the NFT.
     * @param amount The amount (1 for ERC721, >1 for ERC1155).
     * @param isERC1155 True if the NFT is ERC1155, false if ERC721.
     */
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
    function mintVault(address owner, NFTItem[] calldata nftItems) external returns (uint256 vaultId);

    /**
     * @notice Allows adding more NFTs to an existing vault.
     * @dev Requires the caller to be the owner of the vault and to approve NFTs for transfer.
     * @param vaultId The ID of the vault to add content to.
     * @param nftItems Array of NFTItem structs representing NFTs to be added.
     */
    function addContentToVault(uint256 vaultId, NFTItem[] calldata nftItems) external;

    /**
     * @notice Allows removing specific NFTs from an existing vault.
     * @dev Requires the caller to be the owner of the vault.
     * @dev NFTs are transferred from the vault contract back to the owner.
     * @param vaultId The ID of the vault to remove content from.
     * @param nftItems Array of NFTItem structs representing NFTs to be removed.
     */
    function removeContentFromVault(uint256 vaultId, NFTItem[] calldata nftItems) external;

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
