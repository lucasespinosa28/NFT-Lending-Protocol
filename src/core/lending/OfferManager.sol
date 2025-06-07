// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILendingProtocol} from "../../interfaces/ILendingProtocol.sol";
import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../../interfaces/ICollectionManager.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For nonReentrant

contract OfferManager is ReentrancyGuard {
    // --- State Variables ---
    mapping(bytes32 => ILendingProtocol.LoanOffer) public loanOffers;
    uint256 internal offerCounter; // internal to be accessible by LendingProtocol or for internal logic

    // Event definitions are now taken from ILendingProtocol.sol

    // --- External Dependencies (assumed to be available from inheriting contract e.g. LendingProtocol) ---
    // ICurrencyManager public currencyManager;
    // ICollectionManager public collectionManager;
    // These will be inherited from LendingProtocol.sol, so they don't need to be declared here again.
    // However, to make this contract potentially standalone or easier to test,
    // they could be passed in constructor or set via internal functions.
    // For this refactoring, we assume they are accessible from parent LendingProtocol.

    // Access to LendingProtocol's state variables (currencyManager, collectionManager)
    // This requires them to be at least `internal` in LendingProtocol.
    // We'll use a placeholder for now and ensure LendingProtocol provides them.
    function _getCurrencyManager() internal view virtual returns (ICurrencyManager) {
        // This will be overridden in LendingProtocol to return its state variable
        revert("OfferManager: CurrencyManager not set");
    }

    function _getCollectionManager() internal view virtual returns (ICollectionManager) {
        // This will be overridden in LendingProtocol to return its state variable
        revert("OfferManager: CollectionManager not set");
    }


    // --- Functions ---

    /**
     * @notice Makes a loan offer.
     * @param params Parameters for the loan offer.
     * @return offerId The ID of the newly created loan offer.
     */
    function makeLoanOffer(ILendingProtocol.OfferParams calldata params) public virtual nonReentrant returns (bytes32 offerId) { // external to public
        ICurrencyManager currencyManager = _getCurrencyManager();
        ICollectionManager collectionManager = _getCollectionManager();

        require(currencyManager.isCurrencySupported(params.currency), "Currency not supported");
        require(params.principalAmount > 0, "Principal must be > 0");
        require(params.durationSeconds > 0, "Duration must be > 0");
        require(params.expirationTimestamp > block.timestamp, "Expiration in past");

        if (params.offerType == ILendingProtocol.OfferType.STANDARD) {
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
        offerId = keccak256(abi.encodePacked("offer", offerCounter, msg.sender, block.timestamp));

        loanOffers[offerId] = ILendingProtocol.LoanOffer({
            offerId: offerId,
            lender: msg.sender,
            offerType: params.offerType,
            nftContract: params.nftContract,
            nftTokenId: params.nftTokenId,
            currency: params.currency,
            principalAmount: params.principalAmount,
            interestRateAPR: params.interestRateAPR,
            durationSeconds: params.durationSeconds,
            expirationTimestamp: params.expirationTimestamp,
            originationFeeRate: params.originationFeeRate,
            maxSeniorRepayment: 0, // Should this be part of params? For now, default.
            totalCapacity: params.totalCapacity,
            maxPrincipalPerLoan: params.maxPrincipalPerLoan,
            minNumberOfLoans: params.minNumberOfLoans,
            isActive: true
        });

        emit ILendingProtocol.OfferMade( // Qualified event name
            offerId,
            msg.sender,
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
     * @notice Cancels an active loan offer.
     * @param offerId The ID of the loan offer to cancel.
     */
    function cancelLoanOffer(bytes32 offerId) public virtual nonReentrant { // external to public
        ILendingProtocol.LoanOffer storage offer = loanOffers[offerId];
        require(offer.lender == msg.sender, "Not offer owner");
        require(offer.isActive, "Offer not active");

        offer.isActive = false;

        emit ILendingProtocol.OfferCancelled(offerId, msg.sender); // Qualified event name
    }

    /**
     * @notice Retrieves details of a specific loan offer.
     * @param offerId The ID of the loan offer.
     * @return The LoanOffer struct.
     */
    function getLoanOffer(bytes32 offerId) public view virtual returns (ILendingProtocol.LoanOffer memory) { // external to public
        return loanOffers[offerId];
    }

    // --- Internal functions for other Managers (via LendingProtocol) ---

    /**
     * @notice Sets a loan offer as inactive. Typically called when an offer is accepted.
     * @dev Meant to be called internally by LoanManager through LendingProtocol.
     * @param offerId The ID of the loan offer to deactivate.
     */
    function _setLoanOfferInactive(bytes32 offerId) internal virtual {
        // This function will be called by LendingProtocol, which in turn is called by LoanManager.
        // It needs to effectively do: loanOffers[offerId].isActive = false;
        // The `virtual` keyword allows LendingProtocol to override if needed, though direct call is also fine.
        ILendingProtocol.LoanOffer storage offer = loanOffers[offerId];
        require(offer.isActive, "OfferManager: Offer already inactive or does not exist");
        offer.isActive = false;
    }
}
