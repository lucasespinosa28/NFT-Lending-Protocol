// SPDX-License-Identifier: MIT
pragma solidity 0.8.30; // Assuming you want all files at 0.8.26

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol"; // Keep if direct 1155 support is planned
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol"; // Added import
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol"; // For supportsInterface

import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol";
import {ICurrencyManager} from "../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../interfaces/ICollectionManager.sol";
import {IVaultsFactory} from "../interfaces/IVaultsFactory.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";
import {IPurchaseBundler} from "../interfaces/IPurchaseBundler.sol";

/**
 * @title LendingProtocol
 * @author Your Name/Team
 * @notice Core contract for managing NFT-backed loans.
 * @dev Implements ILendingProtocol. This is a placeholder implementation.
 */
contract LendingProtocol is
    ILendingProtocol,
    Ownable,
    ReentrancyGuard,
    IERC721Receiver // Added IERC721Receiver
{
    using SafeERC20 for IERC20;

    // --- State Variables ---

    ICurrencyManager public currencyManager;
    ICollectionManager public collectionManager;
    IVaultsFactory public vaultsFactory;
    ILiquidation public liquidationContract;
    IPurchaseBundler public purchaseBundler;

    mapping(bytes32 => LoanOffer) public loanOffers;
    mapping(bytes32 => Loan) public loans;
    mapping(bytes32 => RenegotiationProposal) public renegotiationProposals;

    uint256 private offerCounter;
    uint256 private loanCounter;
    uint256 private renegotiationProposalCounter;

    struct RenegotiationProposal {
        bytes32 proposalId;
        bytes32 loanId;
        address proposer;
        address borrower;
        uint256 proposedPrincipalAmount;
        uint256 proposedInterestRateAPR;
        uint256 proposedDurationSeconds;
        bool accepted;
        bool exists;
    }

    // --- Modifiers ---
    modifier onlyLender(bytes32 loanId) {
        require(loans[loanId].lender == msg.sender, "Not lender");
        _;
    }

    modifier onlyBorrower(bytes32 loanId) {
        require(loans[loanId].borrower == msg.sender, "Not borrower");
        _;
    }

    // --- Constructor ---
    constructor(
        address _currencyManager,
        address _collectionManager,
        address _vaultsFactory,
        address _liquidationContract,
        address _purchaseBundler
    ) Ownable(msg.sender) {
        require(_currencyManager != address(0), "CurrencyManager zero address");
        require(_collectionManager != address(0), "CollectionManager zero address");
        require(_liquidationContract != address(0), "LiquidationContract zero address");
        require(_purchaseBundler != address(0), "PurchaseBundler zero address");

        currencyManager = ICurrencyManager(_currencyManager);
        collectionManager = ICollectionManager(_collectionManager);
        if (_vaultsFactory != address(0)) {
            vaultsFactory = IVaultsFactory(_vaultsFactory);
        }
        liquidationContract = ILiquidation(_liquidationContract);
        purchaseBundler = IPurchaseBundler(_purchaseBundler);
    }

    // --- ILendingProtocol Implementation ---

    function makeLoanOffer(OfferParams calldata params) external override nonReentrant returns (bytes32 offerId) {
        require(currencyManager.isCurrencySupported(params.currency), "Currency not supported");
        require(params.principalAmount > 0, "Principal must be > 0");
        require(params.durationSeconds > 0, "Duration must be > 0");
        require(params.expirationTimestamp > block.timestamp, "Expiration in past");

        if (params.offerType == OfferType.STANDARD) {
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

        loanOffers[offerId] = LoanOffer({
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
            maxSeniorRepayment: 0,
            totalCapacity: params.totalCapacity,
            maxPrincipalPerLoan: params.maxPrincipalPerLoan,
            minNumberOfLoans: params.minNumberOfLoans,
            isActive: true
        });

        emit OfferMade(
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

    function acceptLoanOffer(bytes32 offerId, address nftContract, uint256 nftTokenId)
        external
        override
        nonReentrant
        returns (bytes32 loanId)
    {
        LoanOffer storage offer = loanOffers[offerId];
        require(offer.isActive, "Offer not active");
        require(offer.expirationTimestamp > block.timestamp, "Offer expired");
        require(msg.sender != offer.lender, "Cannot accept own offer");

        address collateralContract;
        uint256 collateralTokenId;
        bool isCollateralVault = false;

        if (offer.offerType == OfferType.STANDARD) {
            collateralContract = offer.nftContract;
            collateralTokenId = offer.nftTokenId;
        } else {
            // Collection Offer
            collateralContract = nftContract;
            collateralTokenId = nftTokenId;
            require(collectionManager.isCollectionWhitelisted(collateralContract), "Collection not whitelisted");
        }

        if (address(vaultsFactory) != address(0) && vaultsFactory.isVault(collateralTokenId)) {
            require(vaultsFactory.ownerOfVault(collateralTokenId) == msg.sender, "Not vault owner");
            isCollateralVault = true;
            // Ensure collateralContract is the address of the vault token contract (which is vaultsFactory itself if it's the ERC721)
            // If vaults are separate ERC721s, this needs to be the vault's contract address.
            // Assuming VaultsFactory IS the ERC721 contract for vaults:
            collateralContract = address(vaultsFactory);
        } else {
            require(IERC721(collateralContract).ownerOf(collateralTokenId) == msg.sender, "Not NFT owner");
        }

        // Transfer NFT to this contract (escrow)
        // collateralContract should be the address of the ERC721 token being transferred
        IERC721(collateralContract).safeTransferFrom(msg.sender, address(this), collateralTokenId);

        loanCounter++;
        loanId = keccak256(abi.encodePacked("loan", loanCounter, msg.sender, offerId));
        uint64 startTime = uint64(block.timestamp);
        uint64 dueTime = startTime + uint64(offer.durationSeconds);
        uint256 originationFee = (offer.principalAmount * offer.originationFeeRate) / 10000;

        loans[loanId] = Loan({
            loanId: loanId,
            offerId: offerId,
            borrower: msg.sender,
            lender: offer.lender,
            nftContract: collateralContract, // Storing the actual contract address of the collateral
            nftTokenId: collateralTokenId,
            isVault: isCollateralVault,
            currency: offer.currency,
            principalAmount: offer.principalAmount,
            interestRateAPR: offer.interestRateAPR,
            originationFeePaid: originationFee,
            startTime: startTime,
            dueTime: dueTime,
            accruedInterest: 0,
            status: LoanStatus.ACTIVE
        });

        offer.isActive = false;

        IERC20(offer.currency).safeTransferFrom(offer.lender, msg.sender, offer.principalAmount - originationFee);
        if (originationFee > 0) {
            IERC20(offer.currency).safeTransferFrom(offer.lender, offer.lender, originationFee);
        }

        emit OfferAccepted(
            loanId,
            offerId,
            msg.sender,
            offer.lender,
            collateralContract,
            collateralTokenId,
            offer.currency,
            offer.principalAmount,
            dueTime
        );
        return loanId;
    }

    function cancelLoanOffer(bytes32 offerId) external override nonReentrant {
        LoanOffer storage offer = loanOffers[offerId];
        require(offer.lender == msg.sender, "Not offer owner");
        require(offer.isActive, "Offer not active");

        offer.isActive = false;

        emit OfferCancelled(offerId, msg.sender);
    }

    function repayLoan(bytes32 loanId) external override nonReentrant {
        Loan storage currentLoan = loans[loanId];
        require(currentLoan.borrower == msg.sender, "Not borrower");
        require(currentLoan.status == LoanStatus.ACTIVE, "Loan not active");
        require(block.timestamp <= currentLoan.dueTime, "Loan past due (defaulted)");

        uint256 interest = calculateInterest(loanId);
        uint256 totalRepayment = currentLoan.principalAmount + interest;

        IERC20(currentLoan.currency).safeTransferFrom(msg.sender, currentLoan.lender, totalRepayment);

        // currentLoan.nftContract holds the address of the ERC721 token (either original NFT or VaultsFactory)
        IERC721(currentLoan.nftContract).safeTransferFrom(address(this), currentLoan.borrower, currentLoan.nftTokenId);

        currentLoan.status = LoanStatus.REPAID;
        currentLoan.accruedInterest = interest;

        emit LoanRepaid(loanId, msg.sender, currentLoan.lender, currentLoan.principalAmount, interest);
    }

    function refinanceLoan(
        bytes32 existingLoanId,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) external override nonReentrant returns (bytes32 newLoanId) {
        Loan storage oldLoan = loans[existingLoanId];
        require(oldLoan.status == LoanStatus.ACTIVE, "Original loan not active");

        uint256 interestForOldLender = calculateInterest(existingLoanId);
        uint256 paymentToOldLender = oldLoan.principalAmount + interestForOldLender;

        IERC20(oldLoan.currency).safeTransferFrom(msg.sender, oldLoan.lender, paymentToOldLender);

        if (newPrincipalAmount > oldLoan.principalAmount) {
            uint256 diffToBorrower = newPrincipalAmount - oldLoan.principalAmount;
            IERC20(oldLoan.currency).safeTransferFrom(msg.sender, oldLoan.borrower, diffToBorrower);
        } else if (newPrincipalAmount < oldLoan.principalAmount) {
            revert("Principal reduction in refinance not simply handled");
        }

        oldLoan.lender = msg.sender;
        oldLoan.principalAmount = newPrincipalAmount;
        oldLoan.interestRateAPR = newInterestRateAPR;
        oldLoan.startTime = uint64(block.timestamp);
        oldLoan.dueTime = uint64(block.timestamp) + uint64(newDurationSeconds);
        oldLoan.originationFeePaid = (newPrincipalAmount * newOriginationFeeRate) / 10000;
        oldLoan.accruedInterest = 0;

        if (oldLoan.originationFeePaid > 0) {
            IERC20(oldLoan.currency).safeTransferFrom(msg.sender, msg.sender, oldLoan.originationFeePaid);
        }

        emit LoanRefinanced(
            existingLoanId,
            existingLoanId,
            oldLoan.borrower,
            oldLoan.lender,
            msg.sender,
            newPrincipalAmount,
            newInterestRateAPR,
            oldLoan.dueTime
        );
        return existingLoanId;
    }

    function proposeRenegotiation(
        bytes32 loanId,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) external override onlyLender(loanId) nonReentrant returns (bytes32 proposalId) {
        Loan storage currentLoan = loans[loanId];
        require(currentLoan.status == LoanStatus.ACTIVE, "Loan not active");

        renegotiationProposalCounter++;
        proposalId = keccak256(abi.encodePacked("reneg", renegotiationProposalCounter, loanId));

        renegotiationProposals[proposalId] = RenegotiationProposal({
            proposalId: proposalId,
            loanId: loanId,
            proposer: msg.sender,
            borrower: currentLoan.borrower,
            proposedPrincipalAmount: proposedPrincipalAmount,
            proposedInterestRateAPR: proposedInterestRateAPR,
            proposedDurationSeconds: proposedDurationSeconds,
            accepted: false,
            exists: true
        });

        return proposalId;
    }

    function acceptRenegotiation(bytes32 proposalId) external override nonReentrant {
        RenegotiationProposal storage proposal = renegotiationProposals[proposalId];
        require(proposal.exists, "Proposal not found");
        require(!proposal.accepted, "Proposal already actioned");
        Loan storage currentLoan = loans[proposal.loanId];
        require(currentLoan.borrower == msg.sender, "Not borrower");
        require(currentLoan.status == LoanStatus.ACTIVE, "Loan not active");

        if (proposal.proposedPrincipalAmount > currentLoan.principalAmount) {
            uint256 diffToBorrower = proposal.proposedPrincipalAmount - currentLoan.principalAmount;
            IERC20(currentLoan.currency).safeTransferFrom(currentLoan.lender, msg.sender, diffToBorrower);
        } else if (proposal.proposedPrincipalAmount < currentLoan.principalAmount) {
            uint256 diffToLender = currentLoan.principalAmount - proposal.proposedPrincipalAmount;
            IERC20(currentLoan.currency).safeTransferFrom(msg.sender, currentLoan.lender, diffToLender);
        }

        currentLoan.principalAmount = proposal.proposedPrincipalAmount;
        currentLoan.interestRateAPR = proposal.proposedInterestRateAPR;
        currentLoan.dueTime = currentLoan.startTime + uint64(proposal.proposedDurationSeconds);
        currentLoan.accruedInterest = 0;

        proposal.accepted = true;

        emit LoanRenegotiated(
            proposal.loanId,
            msg.sender,
            currentLoan.lender,
            currentLoan.principalAmount,
            currentLoan.interestRateAPR,
            currentLoan.dueTime
        );
    }

    function claimCollateral(bytes32 loanId) external override nonReentrant {
        Loan storage currentLoan = loans[loanId];
        require(currentLoan.lender == msg.sender, "Not lender");
        require(
            currentLoan.status == LoanStatus.ACTIVE || currentLoan.status == LoanStatus.DEFAULTED,
            "Loan not active/defaulted"
        );
        require(block.timestamp > currentLoan.dueTime, "Loan not yet defaulted");

        currentLoan.status = LoanStatus.DEFAULTED;

        IERC721(currentLoan.nftContract).safeTransferFrom(address(this), msg.sender, currentLoan.nftTokenId);

        emit CollateralClaimed(loanId, msg.sender, currentLoan.nftContract, currentLoan.nftTokenId);
    }

    // --- Getters ---
    function getLoan(bytes32 loanId) external view override returns (Loan memory) {
        return loans[loanId];
    }

    function getLoanOffer(bytes32 offerId) external view override returns (LoanOffer memory) {
        return loanOffers[offerId];
    }

    function calculateInterest(bytes32 loanId) public view override returns (uint256 interestDue) {
        Loan storage currentLoan = loans[loanId];
        if (currentLoan.status != LoanStatus.ACTIVE && currentLoan.status != LoanStatus.DEFAULTED) {
            return currentLoan.accruedInterest;
        }

        uint256 timeElapsed = block.timestamp > currentLoan.dueTime
            ? currentLoan.dueTime - currentLoan.startTime
            : block.timestamp - currentLoan.startTime;

        uint256 SECONDS_IN_YEAR = 365 days;
        interestDue =
            (currentLoan.principalAmount * currentLoan.interestRateAPR * timeElapsed) / (10000 * SECONDS_IN_YEAR);
        return interestDue;
    }

    function isLoanRepayable(bytes32 loanId) external view override returns (bool) {
        Loan storage currentLoan = loans[loanId];
        return currentLoan.status == LoanStatus.ACTIVE && block.timestamp <= currentLoan.dueTime;
    }

    function isLoanInDefault(bytes32 loanId) external view override returns (bool) {
        Loan storage currentLoan = loans[loanId];
        if (currentLoan.status == LoanStatus.DEFAULTED) return true;
        return currentLoan.status == LoanStatus.ACTIVE && block.timestamp > currentLoan.dueTime;
    }

    // --- Admin Functions ---
    function setCurrencyManager(address _currencyManager) external onlyOwner {
        require(_currencyManager != address(0), "Zero address");
        currencyManager = ICurrencyManager(_currencyManager);
    }

    function setCollectionManager(address _collectionManager) external onlyOwner {
        require(_collectionManager != address(0), "Zero address");
        collectionManager = ICollectionManager(_collectionManager);
    }

    function setVaultsFactory(address _vaultsFactory) external onlyOwner {
        vaultsFactory = IVaultsFactory(_vaultsFactory);
    }

    function setLiquidationContract(address _liquidationContract) external onlyOwner {
        require(_liquidationContract != address(0), "Zero address");
        liquidationContract = ILiquidation(_liquidationContract);
    }

    function setPurchaseBundler(address _purchaseBundler) external onlyOwner {
        require(_purchaseBundler != address(0), "Zero address");
        purchaseBundler = IPurchaseBundler(_purchaseBundler);
    }

    // --- IERC721Receiver Implementation ---
    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always accept ERC721 tokens.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        // You can add logic here to check if the transfer is expected,
        // e.g., if it matches an active loan acceptance process.
        // For now, we accept all transfers to this contract.
        // Ensure msg.sender is a trusted NFT contract if needed, though safeTransferFrom handles this.
        return IERC721Receiver.onERC721Received.selector;
    }

    // --- IERC165 Support ---
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(ILendingProtocol).interfaceId || interfaceId == type(IERC721Receiver).interfaceId;
    }
}
