// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IPurchaseBundler (or ISellAndRepay)
 * @author Lucas Espinosa
 * @notice Interface for the "Sell & Repay" feature, allowing borrowers to list
 * collateralized NFTs for sale, with proceeds automatically repaying the loan.
 * @dev Defines events, structs, and functions for collateral sale and loan repayment.
 */
interface IPurchaseBundler {
    /**
     * @notice Struct representing a sale listing for a collateralized NFT.
     * @dev Contains sale parameters and state.
     */
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

    /**
     * @notice Emitted when collateral is listed for sale.
     * @param loanId The ID of the loan.
     * @param seller The address of the seller (borrower).
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param price The listing price.
     * @param currency The currency of the sale.
     */
    event CollateralListedForSale(
        bytes32 indexed loanId,
        address indexed seller,
        address indexed nftContract,
        uint256 nftTokenId,
        uint256 price,
        address currency
    );

    /**
     * @notice Emitted when a sale listing is cancelled by the seller.
     * @param loanId The ID of the loan.
     * @param seller The address of the seller.
     */
    event SaleListingCancelled(bytes32 indexed loanId, address indexed seller);

    /**
     * @notice Emitted when collateral is sold and the loan is repaid.
     * @param loanId The ID of the loan.
     * @param buyer The address of the buyer.
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param salePrice The sale price.
     * @param amountToRepayLoan The amount used to repay the loan.
     * @param surplusToBorrower The surplus returned to the borrower.
     */
    event CollateralSoldAndRepaid(
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
     * @param actualSeller The original borrower initiating the sale through LendingProtocol.
     * @return listingId A unique ID for this sale listing (can be loanId).
     */
    function listCollateralForSale(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        uint256 price,
        address currency,
        address actualSeller // The original borrower initiating the sale through LendingProtocol
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

    /**
     * @notice Gets the details of a sale listing by its ID.
     * @param listingId The ID of the sale listing.
     * @return The SaleListing struct.
     */
    function getSaleListing(bytes32 listingId) external view returns (SaleListing memory);

    /**
     * @notice Gets the maximum debt for a loan (principal + max interest).
     * @param loanId The ID of the loan.
     * @return The maximum debt amount.
     */
    function getMaximumDebt(bytes32 loanId) external view returns (uint256);
}
