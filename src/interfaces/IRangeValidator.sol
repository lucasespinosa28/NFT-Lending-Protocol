// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IRangeValidator
 * @author Lucas Espinosa
 * @notice Interface for validating if specific token IDs within certain collections
 * (e.g., Art Blocks) are eligible for collection offers.
 * @dev Allows for range-based and contract-based validation of token IDs.
 */
interface IRangeValidator {
    // --- Events ---

    /**
     * @notice Emitted when a range rule is set for a collection.
     * @param collectionAddress The address of the NFT collection.
     * @param minTokenId The minimum token ID of the range.
     * @param maxTokenId The maximum token ID of the range.
     * @param isAllowed True if tokens in this range are allowed, false if disallowed.
     */
    event RangeRuleSet(address indexed collectionAddress, uint256 minTokenId, uint256 maxTokenId, bool isAllowed);

    /**
     * @notice Emitted when a specific validator contract is set for a collection.
     * @param collectionAddress The address of the NFT collection.
     * @param validatorContract The address of the validator contract.
     */
    event CollectionValidatorSet(address indexed collectionAddress, address indexed validatorContract);

    // --- Functions ---

    /**
     * @notice Checks if a specific token ID from a given collection is valid for a collection offer.
     * @param collectionAddress The address of the NFT collection (e.g., Art Blocks).
     * @param tokenId The token ID to validate.
     * @return True if the token ID is valid within the defined rules for the collection, false otherwise.
     */
    function isTokenIdValidForCollectionOffer(address collectionAddress, uint256 tokenId)
        external
        view
        returns (bool);

    /**
     * @notice Admin function to set or update validation rules for a collection.
     * @dev This could be simple range checks or point to a more complex validation contract per collection.
     * @dev Should be restricted (e.g., Ownable, Governance). Emits RangeRuleSet.
     * @param collectionAddress The address of the NFT collection.
     * @param minTokenId The minimum token ID of the allowed/disallowed range.
     * @param maxTokenId The maximum token ID of the allowed/disallowed range.
     * @param isAllowed True if tokens in this range are allowed, false if disallowed.
     */
    function setTokenIdRangeRule(address collectionAddress, uint256 minTokenId, uint256 maxTokenId, bool isAllowed)
        external;

    /**
     * @notice Admin function to set a specific validator contract for a collection.
     * @dev Allows for more complex, custom validation logic per collection.
     * @dev Should be restricted. Emits CollectionValidatorSet.
     * @param collectionAddress The address of the NFT collection.
     * @param validatorContract The address of the contract implementing validation logic for this collection.
     * Use address(0) to remove a specific validator.
     */
    function setCollectionSpecificValidator(address collectionAddress, address validatorContract) external;
}
