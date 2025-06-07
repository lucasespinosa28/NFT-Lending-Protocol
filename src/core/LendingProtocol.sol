// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol";
import {ICurrencyManager} from "../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../interfaces/ICollectionManager.sol";
import {IVaultsFactory} from "../interfaces/IVaultsFactory.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";
import {IPurchaseBundler} from "../interfaces/IPurchaseBundler.sol";
import {IRoyaltyManager} from "../interfaces/IRoyaltyManager.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

/**
 * @title LendingProtocol
 * @author Lucas Espinosa
 * @notice Core contract for NFT lending protocol, managing loan offers, acceptance, repayment, refinancing, and collateral claims.
 * @dev Implements ILendingProtocol and interacts with managers and external modules.
 */
contract LendingProtocol is ILendingProtocol, Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    ICurrencyManager public currencyManager;
    ICollectionManager public collectionManager;
    IVaultsFactory public vaultsFactory;
    ILiquidation public liquidationContract;
    IPurchaseBundler public purchaseBundler;
    IRoyaltyManager public royaltyManager;
    IIPAssetRegistry public ipAssetRegistry;

    mapping(bytes32 => LoanOffer) public loanOffers;
    mapping(bytes32 => Loan) public loans;
    mapping(bytes32 => RenegotiationProposal) public renegotiationProposals;

    uint256 private offerCounter;
    uint256 private loanCounter;
    uint256 private renegotiationProposalCounter;

    /**
     * @notice Struct representing a renegotiation proposal for a loan.
     * @param proposalId Unique identifier for the proposal.
     * @param loanId The ID of the loan being renegotiated.
     * @param proposer The address of the lender proposing new terms.
     * @param borrower The address of the borrower.
     * @param proposedPrincipalAmount The new proposed principal.
     * @param proposedInterestRateAPR The new proposed APR.
     * @param proposedDurationSeconds The new proposed duration.
     * @param accepted True if the proposal has been accepted.
     * @param exists True if the proposal exists.
     */
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

    /**
     * @notice Modifier to restrict function to the lender of a loan.
     * @param loanId The ID of the loan.
     */
    modifier onlyLender(bytes32 loanId) {
        require(loans[loanId].lender == msg.sender, "Not lender");
        _;
    }

    /**
     * @notice Modifier to restrict function to the borrower of a loan.
     * @param loanId The ID of the loan.
     */
    modifier onlyBorrower(bytes32 loanId) {
        require(loans[loanId].borrower == msg.sender, "Not borrower");
        _;
    }

    /**
     * @notice Contract constructor to initialize protocol dependencies.
     * @param _currencyManager Address of the CurrencyManager contract.
     * @param _collectionManager Address of the CollectionManager contract.
     * @param _vaultsFactory Address of the VaultsFactory contract.
     * @param _liquidationContract Address of the Liquidation contract.
     * @param _purchaseBundler Address of the PurchaseBundler contract.
     * @param _royaltyManager Address of the RoyaltyManager contract.
     * @param _ipAssetRegistry Address of the Story Protocol IPAssetRegistry contract.
     */
    constructor(
        address _currencyManager,
        address _collectionManager,
        address _vaultsFactory,
        address _liquidationContract,
        address _purchaseBundler,
        address _royaltyManager,
        address _ipAssetRegistry
    ) Ownable(msg.sender) {
        require(_currencyManager != address(0), "CurrencyManager zero address");
        require(_collectionManager != address(0), "CollectionManager zero address");
        require(_liquidationContract != address(0), "LiquidationContract zero address");
        require(_purchaseBundler != address(0), "PurchaseBundler zero address");
        require(_royaltyManager != address(0), "RoyaltyManager zero address");
        require(_ipAssetRegistry != address(0), "IPAssetRegistry zero address");

        currencyManager = ICurrencyManager(_currencyManager);
        collectionManager = ICollectionManager(_collectionManager);
        if (_vaultsFactory != address(0)) {
            vaultsFactory = IVaultsFactory(_vaultsFactory);
        }
        liquidationContract = ILiquidation(_liquidationContract);
        purchaseBundler = IPurchaseBundler(_purchaseBundler);
        royaltyManager = IRoyaltyManager(_royaltyManager);
        ipAssetRegistry = IIPAssetRegistry(_ipAssetRegistry);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
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

    /**
     * @inheritdoc ILendingProtocol
     */
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

        // Determine the actual NFT being proposed for collateral (underlying asset)
        address underlyingCollateralContract;
        uint256 underlyingCollateralTokenId;

        if (offer.offerType == OfferType.STANDARD) {
            underlyingCollateralContract = offer.nftContract;
            underlyingCollateralTokenId = offer.nftTokenId;
            // Whitelist check for STANDARD offers is typically done at offer creation.
        } else {
            // OfferType.COLLECTION or other types that specify NFT at acceptance
            underlyingCollateralContract = nftContract; // from function arguments
            underlyingCollateralTokenId = nftTokenId; // from function arguments
            require(
                collectionManager.isCollectionWhitelisted(underlyingCollateralContract),
                "Collection not whitelisted for this offer type"
            );
        }

        address loanStoryIpId = address(0);
        bool loanIsStoryAsset = false;

        // Check if the underlying asset is registered with Story Protocol
        address retrievedIpId =
            ipAssetRegistry.ipId(block.chainid, underlyingCollateralContract, underlyingCollateralTokenId);
        if (retrievedIpId != address(0)) {
            // A non-zero address from ipId does not guarantee it is registered AND valid.
            // Explicitly call isRegistered.
            if (ipAssetRegistry.isRegistered(retrievedIpId)) {
                loanIsStoryAsset = true;
                loanStoryIpId = retrievedIpId;
            }
        }

        address effectiveCollateralContract = underlyingCollateralContract;
        uint256 effectiveCollateralTokenId = underlyingCollateralTokenId;
        // bool isCollateralVault = false; // This is declared later in the original function

        address collateralContract; // This will be effectively replaced by effectiveCollateralContract
        uint256 collateralTokenId; // This will be effectively replaced by effectiveCollateralTokenId
        bool isCollateralVault = false; // This will be used and correctly set

        // The logic for determining underlyingCollateralContract and underlyingCollateralTokenId is already inserted above.
        // The following lines will now use effectiveCollateralContract and effectiveCollateralTokenId,
        // which are initialized from underlyingCollateralContract and underlyingCollateralTokenId.

        // Note: The original if/else for offer.offerType to set collateralContract/TokenId is now
        // handled by the logic setting underlyingCollateralContract/TokenId, which then feed into effectiveCollateralContract/TokenId.
        // The whitelist check for COLLECTION offers is also handled in the new section.

        if (address(vaultsFactory) != address(0) && vaultsFactory.isVault(effectiveCollateralTokenId)) {
            // Use effectiveCollateralTokenId
            require(vaultsFactory.ownerOfVault(effectiveCollateralTokenId) == msg.sender, "Not vault owner");
            isCollateralVault = true;
            effectiveCollateralContract = address(vaultsFactory); // Update effectiveCollateralContract
        } else {
            // For non-vault, effectiveCollateralContract is already underlyingCollateralContract
            require(
                IERC721(effectiveCollateralContract).ownerOf(effectiveCollateralTokenId) == msg.sender, "Not NFT owner"
            );
        }

        IERC721(effectiveCollateralContract).safeTransferFrom(msg.sender, address(this), effectiveCollateralTokenId);

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
            nftContract: effectiveCollateralContract, // Use effective collateral contract
            nftTokenId: effectiveCollateralTokenId, // Use effective collateral token ID
            isVault: isCollateralVault, // Correctly reflects if it's a vault
            currency: offer.currency,
            principalAmount: offer.principalAmount,
            interestRateAPR: offer.interestRateAPR,
            originationFeePaid: originationFee,
            startTime: startTime,
            dueTime: dueTime,
            accruedInterest: 0,
            status: LoanStatus.ACTIVE,
            storyIpId: loanStoryIpId, // Add Story IP ID
            isStoryAsset: loanIsStoryAsset // Add Story asset flag
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

    /**
     * @inheritdoc ILendingProtocol
     */
    function cancelLoanOffer(bytes32 offerId) external override nonReentrant {
        LoanOffer storage offer = loanOffers[offerId];
        require(offer.lender == msg.sender, "Not offer owner");
        require(offer.isActive, "Offer not active");

        offer.isActive = false;

        emit OfferCancelled(offerId, msg.sender);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function calculateInterest(bytes32 loanId) public view override returns (uint256) {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");

        uint256 timeElapsed =
            block.timestamp < loan.dueTime ? block.timestamp - loan.startTime : loan.dueTime - loan.startTime;

        uint256 interest = (loan.principalAmount * loan.interestRateAPR * timeElapsed) / (365 days * 10000);

        return interest;
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function repayLoan(bytes32 loanId) external override nonReentrant {
        Loan storage currentLoan = loans[loanId];
        require(currentLoan.borrower == msg.sender, "Not borrower");
        require(currentLoan.status == LoanStatus.ACTIVE, "Loan not active");
        require(block.timestamp <= currentLoan.dueTime, "Loan past due (defaulted)");

        uint256 interest = calculateInterest(loanId);
        uint256 totalRepayment = currentLoan.principalAmount + interest;

        IERC20(currentLoan.currency).safeTransferFrom(msg.sender, currentLoan.lender, totalRepayment);

        IERC721(currentLoan.nftContract).safeTransferFrom(address(this), currentLoan.borrower, currentLoan.nftTokenId);

        currentLoan.status = LoanStatus.REPAID;
        currentLoan.accruedInterest = interest;

        emit LoanRepaid(loanId, msg.sender, currentLoan.lender, currentLoan.principalAmount, interest);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function claimAndRepay(bytes32 loanId) external override nonReentrant {
        Loan storage currentLoan = loans[loanId];
        require(currentLoan.borrower == msg.sender, "Not borrower");
        require(currentLoan.status == LoanStatus.ACTIVE, "Loan not active");

        address ipIdToUse;
        if (currentLoan.isStoryAsset) {
            require(currentLoan.storyIpId != address(0), "Loan is Story asset but IP ID is missing");
            ipIdToUse = currentLoan.storyIpId;
        } else {
            ipIdToUse = ipAssetRegistry.ipId(block.chainid, currentLoan.nftContract, currentLoan.nftTokenId);
        }

        // Call updated RoyaltyManager functions
        royaltyManager.claimRoyalty(ipIdToUse, currentLoan.currency);
        uint256 royaltyBalance = royaltyManager.getRoyaltyBalance(ipIdToUse, currentLoan.currency);

        uint256 originalPrincipal = currentLoan.principalAmount; // Store original principal for event and calculations
        uint256 interest = calculateInterest(loanId); // Interest calculation might use currentLoan.principalAmount, ensure this is intended if principal can change before this.
        uint256 totalRepaymentDue = originalPrincipal + interest;

        if (royaltyBalance > 0) {
            uint256 amountToWithdrawFromRoyalty =
                royaltyBalance >= totalRepaymentDue ? totalRepaymentDue : royaltyBalance;

            // Withdraw from RoyaltyManager to the lender
            royaltyManager.withdrawRoyalty(
                ipIdToUse, currentLoan.currency, currentLoan.lender, amountToWithdrawFromRoyalty
            );

            if (royaltyBalance >= totalRepaymentDue) {
                // Full repayment via royalty
                // currentLoan.principalAmount remains originalPrincipal, it's fully paid.
                currentLoan.accruedInterest = interest;
                currentLoan.status = LoanStatus.REPAID;
                emit LoanRepaid(loanId, msg.sender, currentLoan.lender, originalPrincipal, interest);
            } else {
                // Partial repayment from royalty
                // Reduce principal outstanding on the loan record
                // The amount paid from royalty directly reduces the principal part of the loan first.
                currentLoan.principalAmount = originalPrincipal - amountToWithdrawFromRoyalty;

                uint256 remainingRepaymentByBorrower = totalRepaymentDue - amountToWithdrawFromRoyalty;
                IERC20(currentLoan.currency).safeTransferFrom(
                    msg.sender, currentLoan.lender, remainingRepaymentByBorrower
                );

                currentLoan.accruedInterest = interest; // Total interest due has been covered (part by royalty, part by borrower)
                currentLoan.status = LoanStatus.REPAID;
                // Emitting originalPrincipal, as that was the principal at the start of this transaction.
                emit LoanRepaid(loanId, msg.sender, currentLoan.lender, originalPrincipal, interest);
            }
        } else {
            // No royalty balance, borrower pays all
            IERC20(currentLoan.currency).safeTransferFrom(msg.sender, currentLoan.lender, totalRepaymentDue);
            currentLoan.accruedInterest = interest;
            currentLoan.status = LoanStatus.REPAID;
            emit LoanRepaid(loanId, msg.sender, currentLoan.lender, originalPrincipal, interest);
        }

        // Transfer NFT back to borrower only after loan is settled
        IERC721(currentLoan.nftContract).safeTransferFrom(address(this), currentLoan.borrower, currentLoan.nftTokenId);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function refinanceLoan(
        bytes32 existingLoanId,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) external override nonReentrant returns (bytes32 newLoanId) {
        Loan storage oldLoan = loans[existingLoanId];
        require(oldLoan.status == LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender != address(0), "Invalid lender");
        require(newPrincipalAmount >= oldLoan.principalAmount, "Principal must be >= old");
        require(newDurationSeconds >= oldLoan.dueTime - oldLoan.startTime, "Duration must be >= old");

        // Only allow if APR is at least 5% lower or borrower approval is required (not implemented here)
        require(newInterestRateAPR <= oldLoan.interestRateAPR * 95 / 100, "APR not improved by 5%");

        // Repay old lender
        uint256 accruedInterest = calculateInterest(existingLoanId);
        uint256 totalRepay = oldLoan.principalAmount + accruedInterest;
        IERC20(oldLoan.currency).safeTransferFrom(msg.sender, oldLoan.lender, totalRepay);

        // Update loan terms (new loanId for simplicity)
        loanCounter++;
        newLoanId = keccak256(abi.encodePacked("loan", loanCounter, oldLoan.borrower, existingLoanId));
        loans[newLoanId] = Loan({
            loanId: newLoanId,
            offerId: oldLoan.offerId,
            borrower: oldLoan.borrower,
            lender: msg.sender,
            nftContract: oldLoan.nftContract,
            nftTokenId: oldLoan.nftTokenId,
            isVault: oldLoan.isVault,
            currency: oldLoan.currency,
            principalAmount: newPrincipalAmount,
            interestRateAPR: newInterestRateAPR,
            originationFeePaid: newOriginationFeeRate,
            startTime: uint64(block.timestamp),
            dueTime: uint64(block.timestamp) + uint64(newDurationSeconds),
            accruedInterest: 0,
            status: LoanStatus.ACTIVE,
            storyIpId: oldLoan.storyIpId,
            isStoryAsset: oldLoan.isStoryAsset
        });

        oldLoan.status = LoanStatus.REPAID;

        emit LoanRefinanced(
            existingLoanId,
            newLoanId,
            oldLoan.borrower,
            oldLoan.lender,
            msg.sender,
            newPrincipalAmount,
            newInterestRateAPR,
            uint64(block.timestamp) + uint64(newDurationSeconds)
        );
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function proposeRenegotiation(
        bytes32 loanId,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) external override nonReentrant returns (bytes32 proposalId) {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender == loan.lender, "Only lender can propose");

        renegotiationProposalCounter++;
        proposalId = keccak256(abi.encodePacked("proposal", renegotiationProposalCounter, loanId, msg.sender));
        renegotiationProposals[proposalId] = RenegotiationProposal({
            proposalId: proposalId,
            loanId: loanId,
            proposer: msg.sender,
            borrower: loan.borrower,
            proposedPrincipalAmount: proposedPrincipalAmount,
            proposedInterestRateAPR: proposedInterestRateAPR,
            proposedDurationSeconds: proposedDurationSeconds,
            accepted: false,
            exists: true
        });
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function acceptRenegotiation(bytes32 proposalId) external override nonReentrant {
        RenegotiationProposal storage proposal = renegotiationProposals[proposalId];
        require(proposal.exists, "Proposal does not exist");
        require(!proposal.accepted, "Already accepted");
        require(msg.sender == proposal.borrower, "Only borrower can accept");

        Loan storage loan = loans[proposal.loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");

        // Update loan terms
        loan.principalAmount = proposal.proposedPrincipalAmount;
        loan.interestRateAPR = proposal.proposedInterestRateAPR;
        loan.dueTime = uint64(loan.startTime + proposal.proposedDurationSeconds);

        proposal.accepted = true;

        emit LoanRenegotiated(
            proposal.loanId,
            proposal.borrower,
            proposal.proposer,
            proposal.proposedPrincipalAmount,
            proposal.proposedInterestRateAPR,
            loan.dueTime
        );
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function claimCollateral(bytes32 loanId) external override nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        require(block.timestamp > loan.dueTime, "Loan not defaulted");
        require(msg.sender == loan.lender, "Only lender can claim");

        loan.status = LoanStatus.DEFAULTED;

        IERC721(loan.nftContract).safeTransferFrom(address(this), loan.lender, loan.nftTokenId);

        emit CollateralClaimed(loanId, loan.lender, loan.nftContract, loan.nftTokenId);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function getLoan(bytes32 loanId) external view override returns (Loan memory) {
        return loans[loanId];
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function getLoanOffer(bytes32 offerId) external view override returns (LoanOffer memory) {
        return loanOffers[offerId];
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function isLoanRepayable(bytes32 loanId) external view override returns (bool) {
        Loan storage loan = loans[loanId];
        return loan.status == LoanStatus.ACTIVE && block.timestamp <= loan.dueTime;
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function isLoanInDefault(bytes32 loanId) external view override returns (bool) {
        Loan storage loan = loans[loanId];
        return loan.status == LoanStatus.ACTIVE && block.timestamp > loan.dueTime;
    }

    /**
     * @notice Sets a new CurrencyManager contract address.
     * @param newManager The address of the new CurrencyManager.
     */
    function setCurrencyManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        currencyManager = ICurrencyManager(newManager);
    }

    /**
     * @notice Sets a new CollectionManager contract address.
     * @param newManager The address of the new CollectionManager.
     */
    function setCollectionManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        collectionManager = ICollectionManager(newManager);
    }

    /**
     * @notice Sets a new VaultsFactory contract address.
     * @param newFactory The address of the new VaultsFactory.
     */
    function setVaultsFactory(address newFactory) external onlyOwner {
        require(newFactory != address(0), "zero address");
        vaultsFactory = IVaultsFactory(newFactory);
    }

    /**
     * @notice Sets a new Liquidation contract address.
     * @param newContract The address of the new Liquidation contract.
     */
    function setLiquidationContract(address newContract) external onlyOwner {
        require(newContract != address(0), "zero address");
        liquidationContract = ILiquidation(newContract);
    }

    /**
     * @notice Sets a new PurchaseBundler contract address.
     * @param newBundler The address of the new PurchaseBundler.
     */
    function setPurchaseBundler(address newBundler) external onlyOwner {
        require(newBundler != address(0), "zero address");
        purchaseBundler = IPurchaseBundler(newBundler);
    }

    /**
     * @notice Sets a new RoyaltyManager contract address.
     * @param newManager The address of the new RoyaltyManager.
     */
    function setRoyaltyManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        royaltyManager = IRoyaltyManager(newManager);
    }

    /**
     * @notice Sets a new IPAssetRegistry contract address.
     * @param newRegistry The address of the new IPAssetRegistry.
     */
    function setIpAssetRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "zero address");
        ipAssetRegistry = IIPAssetRegistry(newRegistry);
    }

    /**
     * @notice Emergency function to withdraw ERC20 tokens from the contract.
     * @param token The address of the ERC20 token.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Emergency function to withdraw ERC721 tokens from the contract.
     * @param nftContract The address of the NFT contract.
     * @param to The recipient address.
     * @param tokenId The token ID to withdraw.
     */
    function emergencyWithdrawERC721(address nftContract, address to, uint256 tokenId) external onlyOwner {
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }

    /**
     * @notice Emergency function to withdraw native ETH from the contract.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawNative(address payable to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Receive function to allow contract to accept ETH.
     */
    receive() external payable {}

    /**
     * @inheritdoc ILendingProtocol
     */
    function listCollateralForSale(bytes32 loanId, uint256 price) external override nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender == loan.borrower, "Only borrower can list");

        // Approve PurchaseBundler to take the NFT on sale
        IERC721(loan.nftContract).approve(address(purchaseBundler), loan.nftTokenId);

        // Call PurchaseBundler to list it
        // Ensure purchaseBundler address is set and valid
        require(address(purchaseBundler) != address(0), "PurchaseBundler not set");

        bytes32 listingId = IPurchaseBundler(address(purchaseBundler)).listCollateralForSale(
            loanId,
            loan.nftContract,
            loan.nftTokenId,
            loan.isVault,
            price,
            loan.currency,
            loan.borrower // Pass the original borrower as actualSeller
        );

        // Optional: Check if listingId from purchaseBundler matches loanId or handle as needed.
        // For now, assume they are consistent or PurchaseBundler uses loanId as listingId.

        // LendingProtocol emits its own event as well, or relies on PurchaseBundler's event.
        // The interface already has this event.
        emit CollateralListedForSale(loanId, msg.sender, loan.nftContract, loan.nftTokenId, price);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function cancelCollateralSale(bytes32 loanId) external override nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender == loan.borrower, "Only borrower can cancel");
        emit CollateralSaleCancelled(loanId, msg.sender);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function buyCollateralAndRepay(bytes32 loanId, uint256 salePrice) external override nonReentrant {
        Loan storage loan = loans[loanId];
        require(loan.status == LoanStatus.ACTIVE, "Loan not active");
        // In a real implementation, check that collateral is listed, price matches, etc.
        uint256 interest = calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        require(salePrice >= totalRepayment, "Sale price too low");

        // Transfer sale price from buyer to borrower (minus repayment)
        IERC20(loan.currency).safeTransferFrom(msg.sender, loan.lender, totalRepayment);
        if (salePrice > totalRepayment) {
            IERC20(loan.currency).safeTransferFrom(msg.sender, loan.borrower, salePrice - totalRepayment);
        }

        // Transfer NFT to buyer
        IERC721(loan.nftContract).safeTransferFrom(address(this), msg.sender, loan.nftTokenId);

        loan.status = LoanStatus.REPAID;
        loan.accruedInterest = interest;

        emit CollateralSoldAndRepaid(loanId, msg.sender, loan.nftContract, loan.nftTokenId, salePrice, totalRepayment);
    }

    /**
     * @notice Handles receipt of ERC721 tokens.
     * @dev Required for safeTransferFrom.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    function recordLoanRepaymentViaSale(bytes32 loanId, uint256 principalRepaid, uint256 interestRepaid)
        external
        override
        nonReentrant
    {
        // Ensure caller is authorized (e.g., the PurchaseBundler contract)
        // This assumes purchaseBundler is the only one that should call this.
        // If other mechanisms can repay this way, a more general authorization is needed.
        require(msg.sender == address(purchaseBundler), "LP: Caller not authorized PurchaseBundler");

        Loan storage currentLoan = loans[loanId];
        require(currentLoan.status == LoanStatus.ACTIVE, "LP: Loan not active for repayment via sale");

        // The principal and interest amounts are what the PurchaseBundler determined were paid to the lender.
        // The LendingProtocol trusts the PurchaseBundler's accounting for this flow.
        // We should verify that principalRepaid matches currentLoan.principalAmount if full principal is always expected.
        // For now, let's assume principalRepaid is the original principal.
        require(principalRepaid == currentLoan.principalAmount, "LP: Principal mismatch in sale settlement");

        // Transfer the repaid funds (which PurchaseBundler sent to this contract) to the lender
        IERC20(currentLoan.currency).safeTransfer(currentLoan.lender, principalRepaid + interestRepaid);

        currentLoan.accruedInterest = interestRepaid;
        currentLoan.status = LoanStatus.REPAID;

        // Note: The LoanRepaid event is typically emitted by the function that processes the actual repayment actions.
        // PurchaseBundler emits CollateralSoldAndRepaid. LendingProtocol could emit its own LoanRepaid event here too,
        // or the system relies on PurchaseBundler's event for this flow.
        // For consistency with other repayment functions, let's emit LoanRepaid.
        // The `msg.sender` for `emit LoanRepaid` would be `address(purchaseBundler)`.
        // The `borrower` is `currentLoan.borrower`.
        emit LoanRepaid(loanId, currentLoan.borrower, currentLoan.lender, currentLoan.principalAmount, interestRepaid);
    }
}
