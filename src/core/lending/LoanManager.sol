// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILendingProtocol} from "../../interfaces/ILendingProtocol.sol"; // Corrected import
import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../../interfaces/ICollectionManager.sol";
import {IRoyaltyManager} from "../../interfaces/IRoyaltyManager.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import {IPurchaseBundler} from "../../interfaces/IPurchaseBundler.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// Placeholder for OfferManager's loanOffers mapping. This will be resolved when LoanManager and OfferManager
// are inherited by LendingProtocol. LendingProtocol will need to provide access to loanOffers.
interface IOfferManager {
    function getLoanOffer(bytes32 offerId) external view returns (ILendingProtocol.LoanOffer memory); // Corrected
    function setLoanOfferInactive(bytes32 offerId) external; // New function needed
}

contract LoanManager is ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    mapping(bytes32 => ILendingProtocol.Loan) public loans; // Corrected
    uint256 internal loanCounter; // internal for access by LendingProtocol or internal logic

    // Event definitions are now taken from ILendingProtocol.sol

    // --- Modifiers ---
    modifier onlyLender(bytes32 loanId) {
        require(loans[loanId].lender == msg.sender, "Not lender");
        _;
    }

    modifier onlyBorrower(bytes32 loanId) {
        require(loans[loanId].borrower == msg.sender, "Not borrower");
        _;
    }

    // --- External Dependencies (assumed to be available from inheriting contract e.g. LendingProtocol) ---
    // These functions will be overridden in LendingProtocol to return its state variables.
    function _getCurrencyManager() internal view virtual returns (ICurrencyManager) {
        /* revert("LM: CurrencyManager not set"); */
        return ICurrencyManager(address(0));
    }

    function _getCollectionManager() internal view virtual returns (ICollectionManager) {
        /* revert("LM: CollectionManager not set"); */
        return ICollectionManager(address(0));
    }

    function _getIpAssetRegistry() internal view virtual returns (IIPAssetRegistry) {
        /* revert("LM: IPAssetRegistry not set"); */
        return IIPAssetRegistry(address(0));
    }

    function _getRoyaltyManager() internal view virtual returns (IRoyaltyManager) {
        /* revert("LM: RoyaltyManager not set"); */
        return IRoyaltyManager(address(0));
    }

    function _getPurchaseBundler() internal view virtual returns (IPurchaseBundler) {
        /* revert("LM: PurchaseBundler not set"); */
        return IPurchaseBundler(address(0));
    }

    function _getLoanOffer(bytes32) internal view virtual returns (ILendingProtocol.LoanOffer memory) {
        return ILendingProtocol.LoanOffer({
            offerId: bytes32(0),
            lender: address(0),
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(0),
            nftTokenId: 0,
            currency: address(0),
            principalAmount: 0,
            interestRateAPR: 0,
            durationSeconds: 0,
            expirationTimestamp: 0,
            originationFeeRate: 0,
            maxSeniorRepayment: 0,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0,
            isActive: true
        });
    }

    function _setLoanOfferInactive(bytes32) internal virtual {
        revert("LM: OfferManager not set");
    }

    // --- Virtual functions for RequestManager interaction (to be implemented by LendingProtocol) ---
    function _getLoanRequest(bytes32) internal view virtual returns (ILendingProtocol.LoanRequest memory) {
        revert("LM: Bridge for getLoanRequest not implemented");
    }

    function _setLoanRequestInactive(bytes32) internal virtual {
        revert("LM: Bridge for _setLoanRequestInactive not implemented");
    }

    // --- Functions ---

    function acceptLoanOffer(bytes32 offerId, address nftContract, uint256 nftTokenId)
        public
        virtual
        nonReentrant
        returns (bytes32 loanId)
    {
        ILendingProtocol.LoanOffer memory offer = _getLoanOffer(offerId); // Corrected
        require(offer.isActive, "Offer not active");
        require(offer.expirationTimestamp > block.timestamp, "Offer expired");
        require(msg.sender != offer.lender, "Cannot accept own offer");

        ICurrencyManager currencyManager = _getCurrencyManager();
        ICollectionManager collectionManager = _getCollectionManager();
        IIPAssetRegistry ipAssetRegistry = _getIpAssetRegistry();

        address underlyingCollateralContract;
        uint256 underlyingCollateralTokenId;

        if (offer.offerType == ILendingProtocol.OfferType.STANDARD) {
            // Corrected
            underlyingCollateralContract = offer.nftContract;
            underlyingCollateralTokenId = offer.nftTokenId;
        } else {
            underlyingCollateralContract = nftContract;
            underlyingCollateralTokenId = nftTokenId;
            require(
                collectionManager.isCollectionWhitelisted(underlyingCollateralContract), "Collection not whitelisted"
            );
        }

        address loanStoryIpId = address(0);
        bool loanIsStoryAsset = false;
        address retrievedIpId =
            ipAssetRegistry.ipId(block.chainid, underlyingCollateralContract, underlyingCollateralTokenId);
        if (retrievedIpId != address(0) && ipAssetRegistry.isRegistered(retrievedIpId)) {
            loanIsStoryAsset = true;
            loanStoryIpId = retrievedIpId;
        }

        address effectiveCollateralContract = underlyingCollateralContract;
        uint256 effectiveCollateralTokenId = underlyingCollateralTokenId;

        // Removed vaultsFactory logic, only standard NFT collateral supported
        require(IERC721(effectiveCollateralContract).ownerOf(effectiveCollateralTokenId) == msg.sender, "Not NFT owner");

        IERC721(effectiveCollateralContract).safeTransferFrom(msg.sender, address(this), effectiveCollateralTokenId);

        loanCounter++;
        loanId = keccak256(abi.encodePacked("loan", loanCounter, msg.sender, offerId));
        uint64 startTime = uint64(block.timestamp);
        uint64 dueTime = startTime + uint64(offer.durationSeconds);
        uint256 originationFee = (offer.principalAmount * offer.originationFeeRate) / 10000;

        loans[loanId] = ILendingProtocol.Loan({ // Corrected
            loanId: loanId,
            offerId: offerId,
            borrower: msg.sender,
            lender: offer.lender,
            nftContract: effectiveCollateralContract,
            nftTokenId: effectiveCollateralTokenId,
            isVault: false, // Always false, vaults not supported
            currency: offer.currency,
            principalAmount: offer.principalAmount,
            interestRateAPR: offer.interestRateAPR,
            originationFeePaid: originationFee,
            startTime: startTime,
            dueTime: dueTime,
            accruedInterest: 0,
            status: ILendingProtocol.LoanStatus.ACTIVE, // Corrected
            storyIpId: loanStoryIpId,
            isStoryAsset: loanIsStoryAsset
        });

        _setLoanOfferInactive(offerId); // Mark offer as inactive in OfferManager

        IERC20(offer.currency).safeTransferFrom(offer.lender, msg.sender, offer.principalAmount - originationFee);
        if (originationFee > 0) {
            IERC20(offer.currency).safeTransferFrom(offer.lender, offer.lender, originationFee);
        }

        emit ILendingProtocol.OfferAccepted( // Qualified
            loanId,
            offerId,
            msg.sender,
            offer.lender,
            effectiveCollateralContract,
            effectiveCollateralTokenId,
            offer.currency,
            offer.principalAmount,
            dueTime
        );
        return loanId;
    }

    function calculateInterest(bytes32 loanId) public view virtual returns (uint256) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        uint256 timeElapsed =
            block.timestamp < loan.dueTime ? block.timestamp - loan.startTime : loan.dueTime - loan.startTime; // Renamed
        return (loan.principalAmount * loan.interestRateAPR * timeElapsed) / (365 days * 10000); // Renamed
    }

    function repayLoan(bytes32 loanId) public virtual nonReentrant onlyBorrower(loanId) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(block.timestamp <= loan.dueTime, "Loan past due (defaulted)");

        uint256 interest = this.calculateInterest(loanId); // Added this.
        uint256 totalRepayment = loan.principalAmount + interest;

        IERC20(loan.currency).safeTransferFrom(msg.sender, loan.lender, totalRepayment);
        IERC721(loan.nftContract).safeTransferFrom(address(this), loan.borrower, loan.nftTokenId);

        loan.status = ILendingProtocol.LoanStatus.REPAID;
        loan.accruedInterest = interest;
        emit ILendingProtocol.LoanRepaid(loanId, msg.sender, loan.lender, loan.principalAmount, interest); // Qualified
    }

    function claimAndRepay(bytes32 loanId) public virtual nonReentrant onlyBorrower(loanId) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");

        IRoyaltyManager royaltyManager = _getRoyaltyManager();
        IIPAssetRegistry ipAssetRegistry = _getIpAssetRegistry();

        address ipIdToUse =
            loan.isStoryAsset ? loan.storyIpId : ipAssetRegistry.ipId(block.chainid, loan.nftContract, loan.nftTokenId);

        if (loan.isStoryAsset) {
            require(loan.storyIpId != address(0), "Loan is Story asset but IP ID is missing");
        }

        royaltyManager.claimRoyalty(ipIdToUse, loan.currency);
        uint256 royaltyBalance = royaltyManager.getRoyaltyBalance(ipIdToUse, loan.currency);

        uint256 originalPrincipal = loan.principalAmount;
        uint256 interest = this.calculateInterest(loanId); // Added this.
        uint256 totalRepaymentDue = originalPrincipal + interest;

        if (royaltyBalance > 0) {
            uint256 amountToWithdrawFromRoyalty =
                royaltyBalance >= totalRepaymentDue ? totalRepaymentDue : royaltyBalance;
            royaltyManager.withdrawRoyalty(ipIdToUse, loan.currency, loan.lender, amountToWithdrawFromRoyalty);

            if (royaltyBalance >= totalRepaymentDue) {
                loan.accruedInterest = interest;
                loan.status = ILendingProtocol.LoanStatus.REPAID;
                emit ILendingProtocol.LoanRepaid(loanId, msg.sender, loan.lender, originalPrincipal, interest); // Qualified
            } else {
                loan.principalAmount = originalPrincipal - amountToWithdrawFromRoyalty;
                uint256 remainingRepaymentByBorrower = totalRepaymentDue - amountToWithdrawFromRoyalty;
                IERC20(loan.currency).safeTransferFrom(msg.sender, loan.lender, remainingRepaymentByBorrower);
                loan.accruedInterest = interest;
                loan.status = ILendingProtocol.LoanStatus.REPAID;
                emit ILendingProtocol.LoanRepaid(loanId, msg.sender, loan.lender, originalPrincipal, interest); // Qualified
            }
        } else {
            IERC20(loan.currency).safeTransferFrom(msg.sender, loan.lender, totalRepaymentDue);
            loan.accruedInterest = interest;
            loan.status = ILendingProtocol.LoanStatus.REPAID;
            emit ILendingProtocol.LoanRepaid(loanId, msg.sender, loan.lender, originalPrincipal, interest); // Qualified
        }
        IERC721(loan.nftContract).safeTransferFrom(address(this), loan.borrower, loan.nftTokenId);
    }

    function claimCollateral(bytes32 loanId) public virtual nonReentrant onlyLender(loanId) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(block.timestamp > loan.dueTime, "Loan not defaulted");

        loan.status = ILendingProtocol.LoanStatus.DEFAULTED;
        IERC721(loan.nftContract).safeTransferFrom(address(this), loan.lender, loan.nftTokenId);
        emit ILendingProtocol.CollateralClaimed(loanId, loan.lender, loan.nftContract, loan.nftTokenId); // Qualified
    }

    function getLoan(bytes32 loanId) public view virtual returns (ILendingProtocol.Loan memory) {
        // Changed to public
        return loans[loanId];
    }

    function isLoanRepayable(bytes32 loanId) public view virtual returns (bool) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        return loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp <= loan.dueTime;
    }

    function isLoanInDefault(bytes32 loanId) public view virtual returns (bool) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        return loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp > loan.dueTime;
    }

    function listCollateralForSale(bytes32 loanId, uint256 price) public virtual nonReentrant onlyBorrower(loanId) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        IPurchaseBundler purchaseBundler = _getPurchaseBundler();
        require(address(purchaseBundler) != address(0), "PurchaseBundler not set");

        IERC721(loan.nftContract).approve(address(purchaseBundler), loan.nftTokenId);
        purchaseBundler.listCollateralForSale(
            loanId, loan.nftContract, loan.nftTokenId, loan.isVault, price, loan.currency, loan.borrower
        );
        emit ILendingProtocol.CollateralListedForSale(loanId, msg.sender, loan.nftContract, loan.nftTokenId, price); // Qualified
    }

    function cancelCollateralSale(bytes32 loanId) public virtual nonReentrant onlyBorrower(loanId) {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active for sale cancellation");
        emit ILendingProtocol.CollateralSaleCancelled(loanId, msg.sender); // Qualified
    }

    function buyCollateralAndRepay(bytes32 loanId, uint256 salePrice) public virtual nonReentrant {
        // Changed to public
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        uint256 interest = this.calculateInterest(loanId); // Added this.
        uint256 totalRepayment = loan.principalAmount + interest;
        require(salePrice >= totalRepayment, "Sale price too low");

        IERC20(loan.currency).safeTransferFrom(msg.sender, loan.lender, totalRepayment);
        if (salePrice > totalRepayment) {
            IERC20(loan.currency).safeTransferFrom(msg.sender, loan.borrower, salePrice - totalRepayment);
        }
        IERC721(loan.nftContract).safeTransferFrom(address(this), msg.sender, loan.nftTokenId);

        loan.status = ILendingProtocol.LoanStatus.REPAID;
        loan.accruedInterest = interest;
        emit ILendingProtocol.CollateralSoldAndRepaid(
            loanId, msg.sender, loan.nftContract, loan.nftTokenId, salePrice, totalRepayment
        ); // Qualified
    }

    function recordLoanRepaymentViaSale(bytes32 loanId, uint256 principalRepaid, uint256 interestRepaid)
        public // Changed to public
        virtual
        nonReentrant
    {
        IPurchaseBundler purchaseBundler = _getPurchaseBundler();
        require(msg.sender == address(purchaseBundler), "LM: Caller not authorized PurchaseBundler");

        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LM: Loan not active for repayment via sale");
        require(principalRepaid == loan.principalAmount, "LM: Principal mismatch in sale settlement");

        IERC20(loan.currency).safeTransfer(loan.lender, principalRepaid + interestRepaid);
        loan.accruedInterest = interestRepaid;
        loan.status = ILendingProtocol.LoanStatus.REPAID;
        emit ILendingProtocol.LoanRepaid(loanId, loan.borrower, loan.lender, loan.principalAmount, interestRepaid); // Qualified
    }

    function onERC721Received(address, /*operator*/ address, /*from*/ uint256, /*tokenId*/ bytes calldata /*data*/ )
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    // --- Internal functions for other Managers (via LendingProtocol) ---

    function acceptLoanRequest(bytes32 requestId) public virtual nonReentrant returns (bytes32 loanId) {
        ILendingProtocol.LoanRequest memory request = _getLoanRequest(requestId); // Fetches from RequestManager via LendingProtocol

        require(request.isActive, "LM: Loan request not active");
        require(request.expirationTimestamp > block.timestamp, "LM: Loan request expired");
        require(msg.sender != request.borrower, "LM: Lender cannot be borrower");
        // Ensure currency is supported (though request creation should check this, good to double check if currencyManager is accessible)
        ICurrencyManager currencyManager = _getCurrencyManager();
        require(currencyManager.isCurrencySupported(request.currency), "LM: Currency not supported");

        // Check NFT ownership by the borrower
        require(
            IERC721(request.nftContract).ownerOf(request.nftTokenId) == request.borrower, "LM: Borrower not NFT owner"
        );

        // Check if LendingProtocol contract is approved to transfer the NFT
        // address(this) is the LoanManager instance, which is part of LendingProtocol
        require(
            IERC721(request.nftContract).getApproved(request.nftTokenId) == address(this)
                || IERC721(request.nftContract).isApprovedForAll(request.borrower, address(this)),
            "LM: LendingProtocol not approved for NFT transfer"
        );

        // Transfer NFT from borrower to this contract (LendingProtocol)
        IERC721(request.nftContract).safeTransferFrom(request.borrower, address(this), request.nftTokenId);

        // Increment loan counter (inherited or via bridge)
        loanCounter = _incrementLoanCounter(); // Ensure this is available/correctly inherited
        loanId = keccak256(abi.encodePacked("loan", loanCounter, request.borrower, requestId)); // Unique loanId

        uint64 startTime = uint64(block.timestamp);
        uint64 dueTime = startTime + uint64(request.durationSeconds);
        // For simplicity, origination fee is not included in borrower requests for now, can be added later.
        uint256 originationFee = 0; // (request.principalAmount * 0) / 10000; // Example if there was a fee rate

        loans[loanId] = ILendingProtocol.Loan({
            loanId: loanId,
            offerId: requestId, // Store requestId here; could rename field or use a union if OfferId vs RequestId matters elsewhere
            borrower: request.borrower,
            lender: msg.sender, // The one accepting the request is the lender
            nftContract: request.nftContract,
            nftTokenId: request.nftTokenId,
            isVault: false, // Assuming direct NFT loans, not vaults
            currency: request.currency,
            principalAmount: request.principalAmount,
            interestRateAPR: request.interestRateAPR,
            originationFeePaid: originationFee,
            startTime: startTime,
            dueTime: dueTime,
            accruedInterest: 0,
            status: ILendingProtocol.LoanStatus.ACTIVE,
            storyIpId: address(0), // Assuming not a Story Protocol asset by default for requests
            isStoryAsset: false // ^
        });

        // Mark the loan request as inactive
        _setLoanRequestInactive(requestId); // Calls RequestManager._setLoanRequestInactive via LendingProtocol

        // Transfer principal from lender (msg.sender) to borrower
        // Lender must have approved the currency transfer to this contract (LendingProtocol)
        // Or, lender sends funds with the call (if payable, but currency is ERC20)
        // For ERC20, standard is lender approves protocol, protocol transfersFrom.
        IERC20(request.currency).safeTransferFrom(msg.sender, request.borrower, request.principalAmount);
        // If origination fee was > 0 and paid to lender/protocol:
        // IERC20(request.currency).safeTransferFrom(msg.sender, feeAddress, originationFee);

        // Emit an event similar to OfferAccepted.
        // Re-using OfferAccepted event. Note: offerId in event is actually requestId.
        emit ILendingProtocol.OfferAccepted(
            loanId,
            requestId, // This is the loan request ID
            request.borrower,
            msg.sender, // Lender
            request.nftContract,
            request.nftTokenId,
            request.currency,
            request.principalAmount,
            dueTime
        );
        // A more specific LoanRequestAccepted event is defined in ILendingProtocol and should be emitted by LendingProtocol layer

        return loanId;
    }

    function _setLoanStatus(bytes32 loanId, ILendingProtocol.LoanStatus status) internal virtual {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.borrower != address(0), "LoanManager: Loan does not exist");
        loan.status = status;
    }

    function _incrementLoanCounter() internal virtual returns (uint256 newLoanCounter) {
        loanCounter++;
        return loanCounter;
    }

    function _addLoan(bytes32 loanId, ILendingProtocol.Loan memory newLoanData) internal virtual {
        // Corrected to memory from previous plan
        require(loans[loanId].borrower == address(0), "LoanManager: Loan ID already exists");
        loans[loanId] = newLoanData;
    }

    function _updateLoanAfterRenegotiation(bytes32 loanId, uint256 newPrincipal, uint256 newAPR, uint64 newDueTime)
        internal
        virtual
    {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Renamed for clarity, and corrected
        require(loan.borrower != address(0), "LoanManager: Loan does not exist for renegotiation");
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LoanManager: Loan not active for renegotiation");

        loan.principalAmount = newPrincipal;
        loan.interestRateAPR = newAPR;
        loan.dueTime = newDueTime;
    }
}
