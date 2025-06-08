// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ILendingProtocol
 * @author Lucas Espinosa
 * @notice Interface for the core NFT lending protocol, managing loan offers,
 * acceptance, repayment, refinancing, and collateral claims.
 * @dev Defines events, structs, and functions for the lending protocol.
 */
interface ILendingProtocol {
    // --- Structs ---

    /**
     * @notice Enum representing the status of a loan.
     * @dev Used to track the lifecycle of a loan.
     */
    enum LoanStatus {
        PENDING_ACCEPTANCE, // Offer made, not yet accepted
        ACTIVE, // Loan is active
        REPAID, // Loan has been repaid
        DEFAULTED, // Loan defaulted, collateral claimable/auctioned
        AUCTION_PENDING, // Loan defaulted, auction pending (for multi-tranche)
        AUCTION_ACTIVE, // Loan defaulted, auction active
        AUCTION_SETTLED // Loan defaulted, auction settled
    }

    /**
     * @notice Enum representing the type of loan offer.
     * @dev STANDARD is for a specific NFT, COLLECTION is for any NFT in a collection.
     */
    enum OfferType {
        STANDARD, // Offer for a specific NFT
        COLLECTION // Offer for any NFT in a collection
    }

    /**
     * @notice Struct to group parameters for makeLoanOffer to avoid stack too deep errors.
     * @dev Used as input for creating a loan offer.
     */
    struct OfferParams {
        OfferType offerType;
        address nftContract; // For standard offers, the specific NFT contract or collection for collection offers
        uint256 nftTokenId; // For standard offers, the specific NFT token ID; 0 for collection offers
        address currency; // WETH, USDC, etc.
        uint256 principalAmount;
        uint256 interestRateAPR; // Annual Percentage Rate (e.g., 500 for 5.00%)
        uint256 durationSeconds;
        uint64 expirationTimestamp; // When the offer expires if not accepted
        uint256 originationFeeRate; // Percentage of principal (e.g., 100 for 1.00%)
        // Collection offer specific params
        uint256 totalCapacity; // For collection offers: max capital lender wants to deploy
        uint256 maxPrincipalPerLoan; // For collection offers: max principal for an individual loan
        uint256 minNumberOfLoans; // For collection offers: to distribute total capacity
    }

    /**
     * @notice Struct representing a loan offer.
     * @dev Contains all parameters and state for a loan offer.
     */
    struct LoanOffer {
        bytes32 offerId;
        address lender;
        OfferType offerType;
        address nftContract;
        uint256 nftTokenId;
        address currency;
        uint256 principalAmount;
        uint256 interestRateAPR;
        uint256 durationSeconds;
        uint64 expirationTimestamp;
        uint256 originationFeeRate;
        uint256 maxSeniorRepayment; // For tranche seniority
        uint256 totalCapacity;
        uint256 maxPrincipalPerLoan;
        uint256 minNumberOfLoans;
        bool isActive;
    }

    /**
     * @notice Struct representing an active or historical loan.
     * @dev Contains all parameters and state for a loan.
     */
    struct Loan {
        bytes32 loanId;
        bytes32 offerId;
        address borrower;
        address lender;
        address nftContract;
        uint256 nftTokenId;
        bool isVault;
        address currency;
        uint256 principalAmount;
        uint256 interestRateAPR;
        uint256 originationFeePaid;
        uint64 startTime;
        uint64 dueTime;
        uint256 accruedInterest; // Interest accrued at the point of repayment or default
        LoanStatus status; // Current status of the loan
        // --- Story Protocol Integration Fields ---
        address storyIpId; // Story Protocol IP ID of the underlying asset, if applicable
        bool isStoryAsset; // True if the underlying collateral is a Story Protocol registered asset
    }

    // --- Events ---

    /**
     * @notice Emitted when a loan offer is made by a lender.
     * @param offerId The unique identifier for the offer.
     * @param lender The address of the lender.
     * @param offerType The type of offer (STANDARD or COLLECTION).
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT (0 for collection offers).
     * @param currency The address of the ERC20 currency.
     * @param principalAmount The principal amount offered.
     * @param interestRateAPR The annual percentage rate offered.
     * @param durationSeconds The duration of the loan in seconds.
     * @param expirationTimestamp The timestamp when the offer expires.
     */
    event OfferMade(
        bytes32 indexed offerId,
        address indexed lender,
        OfferType offerType,
        address indexed nftContract,
        uint256 nftTokenId,
        address currency,
        uint256 principalAmount,
        uint256 interestRateAPR,
        uint256 durationSeconds,
        uint64 expirationTimestamp
    );

    /**
     * @notice Emitted when a loan offer is accepted by a borrower.
     * @param loanId The unique identifier for the loan.
     * @param offerId The unique identifier for the offer.
     * @param borrower The address of the borrower.
     * @param lender The address of the lender.
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param currency The address of the ERC20 currency.
     * @param principalAmount The principal amount borrowed.
     * @param dueTime The timestamp when the loan is due.
     */
    event OfferAccepted(
        bytes32 indexed loanId,
        bytes32 indexed offerId,
        address indexed borrower,
        address lender,
        address nftContract,
        uint256 nftTokenId,
        address currency,
        uint256 principalAmount,
        uint64 dueTime
    );

    /**
     * @notice Emitted when a loan offer is cancelled by the lender.
     * @param offerId The unique identifier for the offer.
     * @param lender The address of the lender.
     */
    event OfferCancelled(bytes32 indexed offerId, address indexed lender);

    /**
     * @notice Emitted when a loan is repaid.
     * @param loanId The unique identifier for the loan.
     * @param borrower The address of the borrower.
     * @param lender The address of the lender.
     * @param principalAmount The principal amount repaid.
     * @param interestPaid The interest amount paid.
     */
    event LoanRepaid(
        bytes32 indexed loanId,
        address indexed borrower,
        address indexed lender,
        uint256 principalAmount,
        uint256 interestPaid
    );

    /**
     * @notice Emitted when collateral is claimed by the lender after default.
     * @param loanId The unique identifier for the loan.
     * @param lender The address of the lender.
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     */
    event CollateralClaimed(
        bytes32 indexed loanId, address indexed lender, address indexed nftContract, uint256 nftTokenId
    );

    /**
     * @notice Emitted when collateral is listed for sale by the borrower.
     * @param loanId The unique identifier for the loan.
     * @param seller The address of the seller (borrower).
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param price The listing price.
     */
    event CollateralListedForSale( // borrower
    bytes32 indexed loanId, address indexed seller, address indexed nftContract, uint256 nftTokenId, uint256 price);

    /**
     * @notice Emitted when a collateral sale is cancelled by the seller.
     * @param loanId The unique identifier for the loan.
     * @param seller The address of the seller.
     */
    event CollateralSaleCancelled(bytes32 indexed loanId, address indexed seller);

    /**
     * @notice Emitted when collateral is sold and the loan is repaid.
     * @param loanId The unique identifier for the loan.
     * @param buyer The address of the buyer.
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param salePrice The sale price.
     * @param amountToRepayLoan The amount used to repay the loan.
     */
    event CollateralSoldAndRepaid(
        bytes32 indexed loanId,
        address indexed buyer,
        address nftContract,
        uint256 nftTokenId,
        uint256 salePrice,
        uint256 amountToRepayLoan
    );

    // --- Functions ---

    /**
     * @notice Claims collateral and repays the loan in a single transaction.
     * @param loanId The unique identifier for the loan.
     */
    function claimAndRepay(bytes32 loanId) external;

    /**
     * @notice Allows a lender to create a standard or collection loan offer.
     * @dev Emits OfferMade event.
     * @param params Struct containing all parameters for the offer.
     * @return offerId The ID of the newly created offer.
     */
    function makeLoanOffer(OfferParams calldata params) external returns (bytes32 offerId);

    /**
     * @notice Allows a borrower to accept a loan offer and initiate a loan.
     * @dev Transfers NFT to escrow, transfers principal to borrower. Emits OfferAccepted.
     * @param offerId The ID of the offer to accept.
     * @param nftContract The specific NFT contract (if collection offer, borrower specifies).
     * @param nftTokenId The specific NFT token ID (if collection offer, borrower specifies).
     * @return loanId The ID of the newly created loan.
     */
    function acceptLoanOffer(bytes32 offerId, address nftContract, uint256 nftTokenId)
        external
        returns (bytes32 loanId);

    /**
     * @notice Allows a lender to cancel an active loan offer.
     * @dev Emits OfferCancelled.
     * @param offerId The ID of the offer to cancel.
     */
    function cancelLoanOffer(bytes32 offerId) external;

    /**
     * @notice Handles full repayment of principal and accrued interest.
     * @dev Transfers currency from borrower, returns collateral to borrower. Emits LoanRepaid.
     * @param loanId The ID of the loan to repay.
     */
    function repayLoan(bytes32 loanId) external;

    /**
     * @notice For lenders to claim collateral upon default in single-tranche loans.
     * @dev Transfers NFT from escrow to lender. Emits CollateralClaimed.
     * @param loanId The ID of the defaulted loan.
     */
    function claimCollateral(bytes32 loanId) external;

    // --- Collateral Sale Functions ---

    /**
     * @notice Lists collateral for sale by the borrower.
     * @param loanId The ID of the loan whose collateral is being listed.
     * @param price The listing price.
     */
    function listCollateralForSale(bytes32 loanId, uint256 price) external;

    /**
     * @notice Cancels a collateral sale listing.
     * @param loanId The ID of the loan whose collateral sale is being cancelled.
     */
    function cancelCollateralSale(bytes32 loanId) external;

    /**
     * @notice Allows a buyer to purchase collateral and repay the loan.
     * @param loanId The ID of the loan whose collateral is being purchased.
     * @param salePrice The sale price.
     */
    function buyCollateralAndRepay(bytes32 loanId, uint256 salePrice) external;

    // --- Getters ---

    /**
     * @notice Gets the details of a loan by its ID.
     * @param loanId The ID of the loan.
     * @return The Loan struct.
     */
    function getLoan(bytes32 loanId) external view returns (Loan memory);

    /**
     * @notice Gets the details of a loan offer by its ID.
     * @param offerId The ID of the loan offer.
     * @return The LoanOffer struct.
     */
    function getLoanOffer(bytes32 offerId) external view returns (LoanOffer memory);

    /**
     * @notice Calculates the interest due for a loan.
     * @param loanId The ID of the loan.
     * @return interestDue The amount of interest due.
     */
    function calculateInterest(bytes32 loanId) external view returns (uint256 interestDue);

    /**
     * @notice Checks if a loan is repayable.
     * @param loanId The ID of the loan.
     * @return True if the loan is repayable, false otherwise.
     */
    function isLoanRepayable(bytes32 loanId) external view returns (bool);

    /**
     * @notice Checks if a loan is in default.
     * @param loanId The ID of the loan.
     * @return True if the loan is in default, false otherwise.
     */
    function isLoanInDefault(bytes32 loanId) external view returns (bool);

    /**
     * @notice Called by an authorized contract (e.g., PurchaseBundler) to record that a loan has been repaid
     * through an external mechanism like a collateral sale.
     * @dev Updates loan status to REPAID and records accrued interest.
     * @param loanId The ID of the loan that was repaid.
     * @param principalRepaid The amount of principal repaid.
     * @param interestRepaid The amount of interest repaid.
     */
    function recordLoanRepaymentViaSale(bytes32 loanId, uint256 principalRepaid, uint256 interestRepaid) external;
}
