// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ICollectionManager
 * @author Your Name/Team
 * @notice Interface for managing whitelisted NFT collections eligible for collateral.
 */
interface ICollectionManager {
    // --- Events ---
    event CollectionWhitelisted(address indexed collectionAddress);
    event CollectionRemoved(address indexed collectionAddress);
    // Optional: Event for specific collection parameters if any (e.g., LTV ratios)
    // event CollectionParametersSet(address indexed collectionAddress, uint256 maxLTV);

    // --- Functions ---

    /**
     * @notice Checks if an NFT collection is approved for use as collateral.
     * @param collectionAddress The address of the NFT collection contract.
     * @return True if the collection is whitelisted, false otherwise.
     */
    function isCollectionWhitelisted(address collectionAddress) external view returns (bool);

    /**
     * @notice Adds a new NFT collection to the whitelist.
     * @dev Should be restricted (e.g., Ownable, Governance). Emits CollectionWhitelisted.
     * @param collectionAddress The address of the NFT collection contract to whitelist.
     */
    function addWhitelistedCollection(address collectionAddress) external;

    /**
     * @notice Removes an NFT collection from the whitelist.
     * @dev Should be restricted. Emits CollectionRemoved.
     * @param collectionAddress The address of the NFT collection contract to remove.
     */
    function removeWhitelistedCollection(address collectionAddress) external;

    /**
     * @notice Gets a list of all whitelisted collection addresses.
     * @return An array of whitelisted collection addresses.
     */
    function getWhitelistedCollections() external view returns (address[] memory);

    // Optional: Functions to set/get parameters per collection if needed
    // function setCollectionMaxLTV(address collectionAddress, uint256 maxLTV) external;
    // function getCollectionMaxLTV(address collectionAddress) external view returns (uint256);
}
