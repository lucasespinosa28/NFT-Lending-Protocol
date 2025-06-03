// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILendingProtocol
 * @author Your Name/Team
 * @notice Interface for the core NFT lending protocol, managing loan offers,
 * acceptance, repayment, refinancing, and collateral claims.
 */
interface ILendingProtocol {
    // --- Structs ---

    enum LoanStatus {
        PENDING_ACCEPTANCE, // Offer made, not yet accepted
        ACTIVE,             // Loan is active
        REPAID,             // Loan has been repaid
        DEFAULTED,          // Loan defaulted, collateral claimable/auctioned
        AUCTION_PENDING,    // Loan defaulted, auction pending (for multi-tranche)
        AUCTION_ACTIVE,     // Loan defaulted, auction active
        AUCTION_SETTLED     // Loan defaulted, auction settled
    }

    enum OfferType {
        STANDARD, // Offer for a specific NFT
        COLLECTION  // Offer for any NFT in a collection
    }

    // Struct to group parameters for makeLoanOffer to avoid stack too deep errors
    struct OfferParams {
        OfferType offerType;
        address nftContract; // For standard offers, the specific NFT contract or collection for collection offers
        uint256 nftTokenId;  // For standard offers, the specific NFT token ID; 0 for collection offers
        address currency;    // WETH, USDC, etc.
        uint256 principalAmount;
        uint256 interestRateAPR; // Annual Percentage Rate (e.g., 500 for 5.00%)
        uint256 durationSeconds;
        uint64 expirationTimestamp; // When the offer expires if not accepted
        uint256 originationFeeRate; // Percentage of principal (e.g., 100 for 1.00%)
        // Collection offer specific params
        uint256 totalCapacity;      // For collection offers: max capital lender wants to deploy
        uint256 maxPrincipalPerLoan; // For collection offers: max principal for an individual loan
        uint256 minNumberOfLoans;   // For collection offers: to distribute total capacity
    }

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
        uint256 accruedInterest;
        LoanStatus status;
    }

    // --- Events ---

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

    event OfferCancelled(bytes32 indexed offerId, address indexed lender);

    event LoanRepaid(
        bytes32 indexed loanId,
        address indexed borrower,
        address indexed lender,
        uint256 principalAmount,
        uint256 interestPaid
    );

    event LoanRefinanced(
        bytes32 indexed oldLoanId,
        bytes32 indexed newLoanId,
        address indexed borrower,
        address oldLender,
        address newLender,
        uint256 principalAmount,
        uint256 newInterestRateAPR,
        uint64 newDueTime
    );

    event LoanRenegotiated(
        bytes32 indexed loanId,
        address indexed borrower,
        address indexed lender,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint64 newDueTime
    );

    event CollateralClaimed(
        bytes32 indexed loanId,
        address indexed lender,
        address indexed nftContract,
        uint256 nftTokenId
    );

    event CollateralListedForSale(
        bytes32 indexed loanId,
        address indexed seller, // borrower
        address indexed nftContract,
        uint256 nftTokenId,
        uint256 price
    );

    event CollateralSaleCancelled(
        bytes32 indexed loanId,
        address indexed seller
    );

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
     * @notice Allows a lender to create a standard or collection loan offer.
     * @dev Emits OfferMade event.
     * @param params Struct containing all parameters for the offer.
     * @return offerId The ID of the newly created offer.
     */
    function makeLoanOffer(
        OfferParams calldata params
    ) external returns (bytes32 offerId);

    /**
     * @notice Allows a borrower to accept a loan offer and initiate a loan.
     * @dev Transfers NFT to escrow, transfers principal to borrower. Emits OfferAccepted.
     * @param offerId The ID of the offer to accept.
     * @param nftContract The specific NFT contract (if collection offer, borrower specifies).
     * @param nftTokenId The specific NFT token ID (if collection offer, borrower specifies).
     * @return loanId The ID of the newly created loan.
     */
    function acceptLoanOffer(
        bytes32 offerId,
        address nftContract, 
        uint256 nftTokenId   
    ) external returns (bytes32 loanId);

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
     * @notice Manages refinancing of an existing loan by a new (or same) lender with better terms.
     * @dev Can be initiated by a lender. If APR is better by >=5%, no borrower approval needed.
     * @dev Transfers principal + accrued interest to old lender, updates loan terms. Emits LoanRefinanced.
     * @param existingLoanId The ID of the loan to be refinanced.
     * @param newPrincipalAmount The new principal amount (can be same or higher if APR reduction is significant).
     * @param newInterestRateAPR The new APR (must be at least 5% lower for automatic refinancing).
     * @param newDurationSeconds The new duration (can be extended).
     * @param newOriginationFeeRate Optional new origination fee for the refinancer.
     * @return newLoanId The ID of the new loan terms (can be the same loanId with updated state).
     */
    function refinanceLoan(
        bytes32 existingLoanId,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) external returns (bytes32 newLoanId);

    /**
     * @notice Allows lenders to propose new terms for an existing loan, requiring borrower acceptance.
     * @dev This is for renegotiations that are not strictly better (e.g., APR increase, significant principal increase without sufficient APR drop).
     * @param loanId The ID of the loan to renegotiate.
     * @param proposedPrincipalAmount The newly proposed principal.
     * @param proposedInterestRateAPR The newly proposed APR.
     * @param proposedDurationSeconds The newly proposed duration.
     * @return proposalId A unique ID for this renegotiation proposal.
     */
    function proposeRenegotiation(
        bytes32 loanId,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) external returns (bytes32 proposalId);

    /**
     * @notice Allows a borrower to accept a renegotiation proposal.
     * @dev Emits LoanRenegotiated.
     * @param proposalId The ID of the renegotiation proposal to accept.
     */
    function acceptRenegotiation(bytes32 proposalId) external;

    /**
     * @notice For lenders to claim collateral upon default in single-tranche loans.
     * @dev Transfers NFT from escrow to lender. Emits CollateralClaimed.
     * @param loanId The ID of the defaulted loan.
     */
    function claimCollateral(bytes32 loanId) external;


    // --- Getters ---
    function getLoan(bytes32 loanId) external view returns (Loan memory);
    function getLoanOffer(bytes32 offerId) external view returns (LoanOffer memory);
    function calculateInterest(bytes32 loanId) external view returns (uint256 interestDue);
    function isLoanRepayable(bytes32 loanId) external view returns (bool);
    function isLoanInDefault(bytes32 loanId) external view returns (bool);

}
