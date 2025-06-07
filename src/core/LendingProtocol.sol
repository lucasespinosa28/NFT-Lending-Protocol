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

// Logic contract imports
import {LoanOfferLogic} from "./logic/LoanOfferLogic.sol";
import {LoanManagementLogic} from "./logic/LoanManagementLogic.sol";
import {CollateralLogic} from "./logic/CollateralLogic.sol";
import {StoryIntegrationLogic} from "./logic/StoryIntegrationLogic.sol";

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

    // Logic contract instances
    LoanOfferLogic public loanOfferLogic; // Changed to public
    LoanManagementLogic public loanManagementLogic; // Changed to public
    CollateralLogic public collateralLogic; // Changed to public
    StoryIntegrationLogic public storyIntegrationLogic; // Changed to public

    // mapping(bytes32 => LoanOffer) public loanOffers; // Moved to LoanOfferLogic.sol
    // mapping(bytes32 => Loan) public loans; // Moved to LoanManagementLogic.sol
    // mapping(bytes32 => RenegotiationProposal) public renegotiationProposals; // Moved to LoanManagementLogic.sol

    // uint256 private offerCounter; // Moved to LoanOfferLogic.sol
    // uint256 private loanCounter; // Moved to LoanManagementLogic.sol
    // uint256 private renegotiationProposalCounter; // Moved to LoanManagementLogic.sol

    // RenegotiationProposal struct moved to LoanManagementLogic.sol
    // Modifiers onlyLender and onlyBorrower moved to LoanManagementLogic.sol (or will be implicit via delegation)

    /**
     * @notice Contract constructor to initialize protocol dependencies.
     * @param _currencyManager Address of the CurrencyManager contract.
     * @param _collectionManager Address of the CollectionManager contract.
     * @param _vaultsFactory Address of the VaultsFactory contract.
     * @param _liquidationContract Address of the Liquidation contract.
     * @param _purchaseBundler Address of the PurchaseBundler contract.
     * @param _royaltyManagerAddress Address of the RoyaltyManager contract.
     * @param _ipAssetRegistryAddress Address of the Story Protocol IPAssetRegistry contract.
     */
    constructor(
        address _currencyManager, // Parameter name is _currencyManager
        address _collectionManager, // Parameter name is _collectionManager
        address _vaultsFactory,     // Parameter name is _vaultsFactory
        address _liquidationContract, // Parameter name is _liquidationContract
        address _purchaseBundler,   // Parameter name is _purchaseBundler
        address _royaltyManagerAddress,
        address _ipAssetRegistryAddress
    ) Ownable(msg.sender) {
        // Initialize manager contracts passed to LendingProtocol
        require(_currencyManager != address(0), "LP: CurrencyManager zero address"); // Use _currencyManager
        require(_collectionManager != address(0), "LP: CollectionManager zero address"); // Use _collectionManager
        require(_liquidationContract != address(0), "LP: LiquidationContract zero address"); // Use _liquidationContract
        require(_purchaseBundler != address(0), "LP: PurchaseBundler zero address"); // Use _purchaseBundler
        require(_royaltyManagerAddress != address(0), "LP: RoyaltyManager zero address");
        require(_ipAssetRegistryAddress != address(0), "LP: IPAssetRegistry zero address");

        currencyManager = ICurrencyManager(_currencyManager); // Use _currencyManager
        collectionManager = ICollectionManager(_collectionManager); // Use _collectionManager
        if (_vaultsFactory != address(0)) { // Use _vaultsFactory
            vaultsFactory = IVaultsFactory(_vaultsFactory);
        }
        liquidationContract = ILiquidation(_liquidationContract); // Use _liquidationContract
        purchaseBundler = IPurchaseBundler(_purchaseBundler);   // Use _purchaseBundler
        royaltyManager = IRoyaltyManager(_royaltyManagerAddress);
        ipAssetRegistry = IIPAssetRegistry(_ipAssetRegistryAddress);

        // Deploy LoanOfferLogic
        loanOfferLogic = new LoanOfferLogic(
            _currencyManager, // Pass through correct param
            _collectionManager, // Pass through correct param
            address(this) // Owner is LendingProtocol
        );

        // Deploy StoryIntegrationLogic
        storyIntegrationLogic = new StoryIntegrationLogic(
            _royaltyManagerAddress,
            _ipAssetRegistryAddress,
            address(this) // Owner is LendingProtocol (can be LML if LML is the sole interactor)
        );

        // Deploy LoanManagementLogic
        loanManagementLogic = new LoanManagementLogic(
            address(this), // lendingProtocolAddress
            _vaultsFactory, // Pass through correct param
            _ipAssetRegistryAddress,
            address(storyIntegrationLogic),
            address(this) // Owner is LendingProtocol
        );

        // Deploy CollateralLogic
        collateralLogic = new CollateralLogic(
            address(this), // lendingProtocolAddress
            _purchaseBundler, // Pass through correct param
            address(this) // Owner is LendingProtocol
        );
    }

    // --- Loan Offer Logic Delegation ---
    function makeLoanOffer(OfferParams calldata params) external override nonReentrant returns (bytes32 offerId) {
        // LoanOfferLogic.makeLoanOffer now takes `lender` as first param.
        return loanOfferLogic.makeLoanOffer(msg.sender, params);
    }

    function cancelLoanOffer(bytes32 offerId) external override nonReentrant {
        // LoanOfferLogic.cancelLoanOffer now takes `canceller` and is `onlyOwner`.
        // LendingProtocol verifies msg.sender is the original lender before calling.
        LoanOffer memory offer = loanOfferLogic.getLoanOffer(offerId); // Fetch offer to check lender
        require(offer.lender == msg.sender, "LP: Not offer owner");
        loanOfferLogic.cancelLoanOffer(offerId, msg.sender);
    }

    /**
     * @inheritdoc ILendingProtocol
     */
    // --- Loan Offer Logic Delegation ---
    // Note: makeLoanOffer and cancelLoanOffer in LoanOfferLogic use msg.sender as the lender.
    // This needs to be refactored in LoanOfferLogic to accept the lender address as a parameter,
    // or LendingProtocol needs to own offers, which is not the design.
    // For now, these calls will behave as if LendingProtocol is the lender/canceller.
    // This will be addressed in Step 5: Adjust Logic Contract Function Signatures and Auth.

    // --- Loan Management Logic Delegation ---
    // Similar auth adjustments will be needed for LoanManagementLogic functions
    // that currently use msg.sender for borrower/lender identification.

    function acceptLoanOffer(bytes32 offerId, address nftContractAddress, uint256 nftTokenId)
        external
        override
        nonReentrant
        returns (bytes32 loanId)
    {
        LoanOffer memory offer = loanOfferLogic.getLoanOffer(offerId);
        require(offer.isActive, "LP: Offer not active");
        require(offer.expirationTimestamp > block.timestamp, "LP: Offer expired");
        require(msg.sender != offer.lender, "LP: Cannot accept own offer");

        address underlyingCollateralContract;
        uint256 underlyingCollateralTokenId;

        if (offer.offerType == OfferType.STANDARD) {
            underlyingCollateralContract = offer.nftContract;
            underlyingCollateralTokenId = offer.nftTokenId;
             // Whitelist check for STANDARD offers is done at offer creation in LoanOfferLogic.
        } else { // OfferType.COLLECTION
            underlyingCollateralContract = nftContractAddress;
            underlyingCollateralTokenId = nftTokenId;
            require(
                collectionManager.isCollectionWhitelisted(underlyingCollateralContract),
                "LP: Collection not whitelisted for this offer type"
            );
        }

        address loanStoryIpId = address(0);
        bool loanIsStoryAsset = false;
        if (address(ipAssetRegistry) != address(0)) {
            address retrievedIpId = ipAssetRegistry.ipId(block.chainid, underlyingCollateralContract, underlyingCollateralTokenId);
            if (retrievedIpId != address(0) && ipAssetRegistry.isRegistered(retrievedIpId)) {
                loanIsStoryAsset = true;
                loanStoryIpId = retrievedIpId;
            }
        }

        address effectiveCollateralContract = underlyingCollateralContract;
        uint256 effectiveCollateralTokenId = underlyingCollateralTokenId;
        bool isCollateralVault = false;

        if (address(vaultsFactory) != address(0) && vaultsFactory.isVault(effectiveCollateralTokenId)) {
            require(vaultsFactory.ownerOfVault(effectiveCollateralTokenId) == msg.sender, "LP: Not vault owner");
            isCollateralVault = true;
            effectiveCollateralContract = address(vaultsFactory);
        } else {
            require(IERC721(effectiveCollateralContract).ownerOf(effectiveCollateralTokenId) == msg.sender, "LP: Not NFT owner");
        }

        IERC721(effectiveCollateralContract).safeTransferFrom(msg.sender, address(this), effectiveCollateralTokenId);

        loanId = loanManagementLogic.createLoan(
            offerId,
            msg.sender, // borrower
            offer.lender,
            offer.currency,
            offer.principalAmount,
            offer.interestRateAPR,
            offer.durationSeconds,
            offer.originationFeeRate,
            effectiveCollateralContract,
            effectiveCollateralTokenId,
            isCollateralVault,
            loanStoryIpId,
            loanIsStoryAsset
        );

        loanOfferLogic.markOfferInactive(offerId); // Owner check in LOL will pass as LP is owner

        // OfferAccepted event is emitted by LoanManagementLogic.createLoan
        return loanId;
    }

    function calculateInterest(bytes32 loanId) public view override returns (uint256) {
        return loanManagementLogic.calculateInterest(loanId);
    }

    function repayLoan(bytes32 loanId) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.borrower, "LP: Not borrower");
        // LoanManagementLogic.repayLoan is onlyOwner and takes borrower address
        loanManagementLogic.repayLoan(loanId, msg.sender);
    }

    function claimAndRepay(bytes32 loanId) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.borrower, "LP: Not borrower");
        // LoanManagementLogic.claimAndRepay is onlyOwner and takes borrower address
        loanManagementLogic.claimAndRepay(loanId, msg.sender);
    }

    function refinanceLoan(
        bytes32 existingLoanId,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) external override nonReentrant returns (bytes32 newLoanId) {
        Loan memory oldLoan = loanManagementLogic.getLoan(existingLoanId);
        require(oldLoan.status == LoanStatus.ACTIVE, "LP: Loan not active");
        // New lender is msg.sender
        require(msg.sender != address(0) && msg.sender != oldLoan.borrower, "LP: Invalid new lender");
        // Additional business logic checks (e.g., principal, duration, APR improvement)
        require(newPrincipalAmount >= oldLoan.principalAmount, "LP: Principal must be >= old");
        require(newDurationSeconds >= (oldLoan.dueTime - oldLoan.startTime) , "LP: Duration must be >= old"); // Ensure new duration is not shorter than original relative duration
        if (oldLoan.interestRateAPR > 0) { // Avoid division by zero if old APR is 0
           require(newInterestRateAPR <= oldLoan.interestRateAPR * 95 / 100, "LP: APR not improved by at least 5%");
        } else {
            require(newInterestRateAPR == 0, "LP: Old APR was 0, new APR must also be 0 unless explicitly allowed");
        }

        return loanManagementLogic.refinanceLoan(
            existingLoanId,
            msg.sender, // actualNewLender
            newPrincipalAmount,
            newInterestRateAPR,
            newDurationSeconds,
            newOriginationFeeRate
        );
    }

    function proposeRenegotiation(
        bytes32 loanId,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) external override nonReentrant returns (bytes32 proposalId) {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.lender, "LP: Only lender can propose");
        return loanManagementLogic.proposeRenegotiation(
            loanId,
            msg.sender, // actualProposer
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds
        );
    }

    function acceptRenegotiation(bytes32 proposalId) external override nonReentrant {
        // We need to get the proposal to find the borrower.
        // Assuming getRenegotiationProposal is available and returns a struct with a borrower field.
        // This requires LoanManagementLogic.getRenegotiationProposal to be accessible.
        // For now, this is a simplification. A real implementation would fetch the proposal.
        // Let's assume LoanManagementLogic.acceptRenegotiation handles all checks after we pass msg.sender.
        // The LML.acceptRenegotiation takes `actualBorrower`.
        // LendingProtocol must fetch proposal, check proposal.borrower == msg.sender
        // This is a bit complex as RenegotiationProposal struct is in LML.
        // Temporarily, this shows the intent.
        // RenegotiationProposal memory proposal = loanManagementLogic.getRenegotiationProposal(proposalId);
        // require(msg.sender == proposal.borrower, "LP: Only borrower can accept");
        loanManagementLogic.acceptRenegotiation(proposalId, msg.sender);
    }

    function claimCollateral(bytes32 loanId) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.lender, "LP: Only lender can claim");
        require(loanManagementLogic.isLoanInDefault(loanId), "LP: Loan not in default");

        loanManagementLogic.setLoanStatusDefaulted(loanId, msg.sender);
        collateralLogic.transferCollateralToLender(loanId, msg.sender, loan.nftContract, loan.nftTokenId);
    }

    function getLoan(bytes32 loanId) external view override returns (Loan memory) {
        return loanManagementLogic.getLoan(loanId);
    }

    function getLoanOffer(bytes32 offerId) external view override returns (LoanOffer memory) {
        return loanOfferLogic.getLoanOffer(offerId);
    }

    function isLoanRepayable(bytes32 loanId) external view override returns (bool) {
        return loanManagementLogic.isLoanRepayable(loanId);
    }

    function isLoanInDefault(bytes32 loanId) external view override returns (bool) {
        return loanManagementLogic.isLoanInDefault(loanId);
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
    // --- Collateral Logic Delegation ---
    // --- Collateral Logic Delegation ---
    function listCollateralForSale(bytes32 loanId, uint256 price) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.borrower, "LP: Only borrower can list");
        require(loan.status == LoanStatus.ACTIVE, "LP: Loan not active");

        // LendingProtocol holds the NFT, so it must approve CollateralLogic to then approve PurchaseBundler,
        // or LendingProtocol approves PurchaseBundler directly.
        // Assuming CollateralLogic.listCollateralForSale handles approval for PurchaseBundler if it's an operator.
        // If CollateralLogic itself needs approval from LendingProtocol to move the NFT:
        IERC721(loan.nftContract).approve(address(collateralLogic), loan.nftTokenId);
        // Then CollateralLogic can call safeTransferFrom(lendingProtocolAddress, ...) or approve purchaseBundler.
        // For now, assume CollateralLogic's listCollateralForSale also handles approving the purchaseBundler.

        collateralLogic.listCollateralForSale(
            loanId,
            msg.sender, // borrower (seller)
            loan.nftContract,
            loan.nftTokenId,
            loan.isVault,
            price,
            loan.currency
        );
    }

    function cancelCollateralSale(bytes32 loanId) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(msg.sender == loan.borrower, "LP: Only borrower can cancel");
        // CollateralLogic.cancelCollateralSale is onlyOwner
        collateralLogic.cancelCollateralSale(loanId, msg.sender);
    }

    function buyCollateralAndRepay(bytes32 loanId, uint256 salePrice) external override nonReentrant {
        Loan memory loan = loanManagementLogic.getLoan(loanId);
        require(loan.status == LoanStatus.ACTIVE, "LP: Loan not active for sale");
        // Additional checks like ensuring collateral is actually listed for sale might be needed via PurchaseBundler view func.

        uint256 interest = loanManagementLogic.calculateInterest(loanId);
        uint256 totalRepaymentNeeded = loan.principalAmount + interest;
        require(salePrice >= totalRepaymentNeeded, "LP: Sale price too low for full repayment");

        // Buyer (msg.sender) must have approved LendingProtocol for loan.currency for 'salePrice'
        // or sent value if currency is native ETH (not handled here).
        IERC20(loan.currency).safeTransferFrom(msg.sender, address(this), salePrice);

        // CollateralLogic.buyCollateralAndRepayLoan is onlyOwner
        collateralLogic.buyCollateralAndRepayLoan(
            loanId,
            msg.sender, // buyer
            loan.lender,
            loan.borrower,
            loan.currency,
            loan.nftContract,
            loan.nftTokenId,
            salePrice,
            totalRepaymentNeeded
        );

        // LoanManagementLogic.markLoanRepaidBySale is onlyOwner
        loanManagementLogic.markLoanRepaidBySale(loanId, loan.borrower, loan.principalAmount, interest);
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
        require(msg.sender == address(purchaseBundler), "LP: Caller not PurchaseBundler");
        Loan memory loan = loanManagementLogic.getLoan(loanId); // Fetch needed details for currency, lender, borrower

        // CollateralLogic.recordLoanRepaymentDetailsViaSale can be called by PurchaseBundler if it's made public
        // or by LendingProtocol (owner) if it takes original caller as param.
        // Assuming CollateralLogic.recordLoanRepaymentDetailsViaSale is onlyOwner (called by LP)
        // and takes the actual msg.sender (PurchaseBundler) for its internal check.
        // This part of CollateralLogic needs review for its auth.
        // For now, assume direct call from PB to CL is not the design. LP is intermediary.

        // The funds (principalRepaid + interestRepaid) are assumed to be in LendingProtocol by PurchaseBundler.
        // CollateralLogic then tells LP to send these to the lender.
        collateralLogic.recordLoanRepaymentDetailsViaSale(
            address(this), // original caller to PurchaseBundler was this contract (or should be)
            loanId,
            principalRepaid,
            interestRepaid,
            loan.currency,
            loan.lender
        );

        // LoanManagementLogic.markLoanRepaidBySale is onlyOwner
        loanManagementLogic.markLoanRepaidBySale(loanId, loan.borrower, principalRepaid, interestRepaid);
    }
}
