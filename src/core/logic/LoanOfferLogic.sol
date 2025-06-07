// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ICurrencyManager } from "../../interfaces/ICurrencyManager.sol";
import { ICollectionManager } from "../../interfaces/ICollectionManager.sol";
import { ILendingProtocol } from "../../interfaces/ILendingProtocol.sol"; // Import the interface
// Import the structs and enums individually if needed, or reference via ILendingProtocol.StructName
// For clarity, let's try importing them directly after ensuring they are correctly defined at file level in ILendingProtocol.sol
// Re-evaluating the error: it says "Declaration not found IN src/interfaces/ILendingProtocol.sol".
// This means the compiler *is* finding the file, but not the symbols *within* it.
// The file ILendingProtocol.sol DOES define these at the top level.
// This is very strange. Let's try a qualified import first.

import "../../interfaces/ILendingProtocol.sol"; // This will import all top-level items.

contract LoanOfferLogic is Ownable, ReentrancyGuard {
    mapping(bytes32 => ILendingProtocol.LoanOffer) public loanOffers;
    uint256 private offerCounter;

    ICurrencyManager public currencyManager;
    ICollectionManager public collectionManager;

    // Event forwarders or direct emissions if ILendingProtocol is inherited
    event OfferMade(
        bytes32 indexed offerId,
        address indexed lender,
        ILendingProtocol.OfferType offerType, // Use qualified name
        address nftContract,
        uint256 nftTokenId,
        address currency,
        uint256 principalAmount,
        uint256 interestRateAPR,
        uint256 durationSeconds,
        uint256 expirationTimestamp
    );

    event OfferCancelled(bytes32 indexed offerId, address indexed lender);

    constructor(address _currencyManager, address _collectionManager, address _initialOwner) Ownable(_initialOwner) {
        require(_currencyManager != address(0), "CurrencyManager zero address");
        require(_collectionManager != address(0), "CollectionManager zero address");
        currencyManager = ICurrencyManager(_currencyManager);
        collectionManager = ICollectionManager(_collectionManager);
    }

    /**
     * @notice Makes a new loan offer.
     * @param params Parameters for the loan offer.
     * @return offerId The ID of the newly created loan offer.
     * @dev Corresponds to makeLoanOffer in ILendingProtocol.
     *      The lender is passed as a parameter because this function is called by LendingProtocol.
     */
    function makeLoanOffer(address lender, ILendingProtocol.OfferParams calldata params) external nonReentrant returns (bytes32 offerId) { // Use qualified name
        require(lender != address(0), "LOL: Invalid lender address");
        require(currencyManager.isCurrencySupported(params.currency), "Currency not supported");
        require(params.principalAmount > 0, "Principal must be > 0");
        require(params.durationSeconds > 0, "Duration must be > 0");
        require(params.expirationTimestamp > block.timestamp, "Expiration in past");

        if (params.offerType == ILendingProtocol.OfferType.STANDARD) { // Use qualified name
            require(params.nftContract != address(0), "NFT contract address needed");
            require(collectionManager.isCollectionWhitelisted(params.nftContract), "Collection not whitelisted");
        } else {
            // Collection Offer
            require(collectionManager.isCollectionWhitelisted(params.nftContract), "Collection not whitelisted");
            require(params.totalCapacity > 0, "Total capacity must be > 0");
            require(
                params.maxPrincipalPerLoan > 0 && params.maxPrincipalPerLoan <= params.totalCapacity,
                "Invalid max principal per loan"
            );
        }

        offerCounter++;
        // Use lender address for offerId generation to ensure uniqueness if lender makes similar offers quickly.
        offerId = keccak256(abi.encodePacked("offer", offerCounter, lender, block.timestamp));

        loanOffers[offerId] = ILendingProtocol.LoanOffer({ // Use qualified name
            offerId: offerId,
            lender: lender, // Use the passed lender address
            offerType: params.offerType,
            nftContract: params.nftContract,
            nftTokenId: params.nftTokenId,
            currency: params.currency,
            principalAmount: params.principalAmount,
            interestRateAPR: params.interestRateAPR,
            durationSeconds: params.durationSeconds,
            expirationTimestamp: params.expirationTimestamp,
            originationFeeRate: params.originationFeeRate,
            maxSeniorRepayment: 0, // Assuming 0 as per original, adjust if logic changes
            totalCapacity: params.totalCapacity,
            maxPrincipalPerLoan: params.maxPrincipalPerLoan,
            minNumberOfLoans: params.minNumberOfLoans,
            isActive: true
        });

        emit OfferMade(
            offerId,
            lender, // Emit the actual lender
            params.offerType,
            params.nftContract,
            params.nftTokenId,
            params.currency,
            params.principalAmount,
            params.interestRateAPR,
            params.durationSeconds,
            params.expirationTimestamp
        );
        return offerId;
    }

    /**
     * @notice Cancels an existing loan offer.
     * @param offerId The ID of the loan offer to cancel.
     * @dev Corresponds to cancelLoanOffer in ILendingProtocol.
     *      The canceller (offer owner) is passed as a parameter.
     */
    function cancelLoanOffer(bytes32 offerId, address canceller) external nonReentrant onlyOwner {
        // onlyOwner: Only LendingProtocol (owner of this contract) can call this.
        // LendingProtocol is responsible for verifying that `canceller` is indeed msg.sender on its side.
        ILendingProtocol.LoanOffer storage offer = loanOffers[offerId]; // Use qualified name
        require(offer.lender == canceller, "LOL: Not offer owner");
        require(offer.isActive, "LOL: Offer not active");

        offer.isActive = false;

        emit OfferCancelled(offerId, canceller); // Emit the actual canceller
    }

    /**
     * @notice Retrieves a loan offer by its ID.
     * @param offerId The ID of the loan offer.
     * @return The LoanOffer struct.
     * @dev Corresponds to getLoanOffer in ILendingProtocol.
     */
    function getLoanOffer(bytes32 offerId) external view returns (ILendingProtocol.LoanOffer memory) { // Use qualified name
        return loanOffers[offerId];
    }

    /**
     * @notice Marks a loan offer as inactive. Typically called when an offer is accepted.
     * @param offerId The ID of the loan offer to mark as inactive.
     * @dev This is an internal-facing function to be called by LendingProtocol.
     *      Consider access control if LendingProtocol is not the owner or a designated caller.
     *      For now, making it external but restricted by Ownable's owner (which will be LendingProtocol).
     */
    function markOfferInactive(bytes32 offerId) external onlyOwner {
        ILendingProtocol.LoanOffer storage offer = loanOffers[offerId]; // Use qualified name
        require(offer.isActive, "Offer not active to mark inactive"); // Should be active to be accepted
        offer.isActive = false;
        // Note: OfferAccepted event is emitted by LendingProtocol after calling this
    }

    // --- Admin functions ---
    function setCurrencyManager(address newManager) external onlyOwner {
        require(newManager != address(0), "LOL: zero address");
        currencyManager = ICurrencyManager(newManager);
    }

    function setCollectionManager(address newManager) external onlyOwner {
        require(newManager != address(0), "LOL: zero address");
        collectionManager = ICollectionManager(newManager);
    }
}
