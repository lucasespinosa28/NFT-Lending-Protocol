// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IPurchaseBundler (or ISellAndRepay)
 * @author Your Name/Team
 * @notice Interface for the "Sell & Repay" feature, allowing borrowers to list
 * collateralized NFTs for sale, with proceeds automatically repaying the loan.
 */
interface IPurchaseBundler {
    struct SaleListing {
        bytes32 loanId;
        address seller; // Borrower
        address nftContract;
        uint256 nftTokenId;
        bool isVault;
        uint256 price; // Asking price in loan currency
        address currency; // Loan currency
        bool isActive;
    }
    // address specificBuyer; // If listing is for a specific buyer initially

    // --- Events ---
    event CollateralListedForSale( // Also in ILendingProtocol, consider if needed here or just one place
        bytes32 indexed loanId,
        address indexed seller,
        address indexed nftContract,
        uint256 nftTokenId,
        uint256 price,
        address currency
    );

    event SaleListingCancelled(bytes32 indexed loanId, address indexed seller);

    event CollateralSoldAndRepaid( // Also in ILendingProtocol
        bytes32 indexed loanId,
        address indexed buyer,
        address nftContract,
        uint256 nftTokenId,
        uint256 salePrice,
        uint256 amountToRepayLoan,
        uint256 surplusToBorrower
    );

    // --- Functions ---

    /**
     * @notice Allows a borrower to list their collateralized NFT for sale.
     * @dev The listing price must be higher than the maximum potential debt (principal + max interest).
     * @dev The lending protocol must approve this action and mark the NFT as available for sale via this contract.
     * @param loanId The ID of the loan whose collateral is being listed.
     * @param nftContract Address of the NFT contract.
     * @param nftTokenId Token ID of the NFT.
     * @param isVault True if the collateral is a vault.
     * @param price The asking price for the NFT, in the loan's currency.
     * @param currency The currency of the loan and sale.
     * @return listingId A unique ID for this sale listing (can be loanId).
     */
    function listCollateralForSale(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        uint256 price,
        address currency
    )
        // address specificBuyer // Optional: if only a specific buyer can purchase initially
        external
        returns (bytes32 listingId);

    /**
     * @notice Allows a buyer to purchase a listed NFT.
     * @dev Transfers payment from buyer. Uses proceeds to repay the loan via ILendingProtocol.
     * @dev Transfers NFT to buyer. Transfers any surplus from sale to borrower.
     * @dev Emits CollateralSoldAndRepaid.
     * @param listingId The ID of the sale listing (loanId).
     * @param paymentAmount The amount the buyer is paying (must match or exceed listing price).
     */
    function buyListedCollateral(bytes32 listingId, uint256 paymentAmount) external payable; // payable if currency is ETH/WETH

    /**
     * @notice Allows the borrower (seller) to cancel their sale listing.
     * @dev Can only be called if the NFT hasn't been sold.
     * @dev Emits SaleListingCancelled.
     * @param listingId The ID of the sale listing (loanId).
     */
    function cancelSaleListing(bytes32 listingId) external;

    // --- Getters ---
    function getSaleListing(bytes32 listingId) external view returns (SaleListing memory);
    function getMaximumDebt(bytes32 loanId) external view returns (uint256); // Helper to check listing price
}
