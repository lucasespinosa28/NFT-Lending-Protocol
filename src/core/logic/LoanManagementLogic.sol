// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Import all top-level items from ILendingProtocol.sol
import "../../interfaces/ILendingProtocol.sol";
// Not directly using ICurrencyManager methods in these functions, but good for context or future needs
// import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {IVaultsFactory} from "../../interfaces/IVaultsFactory.sol";
// import {IRoyaltyManager} from "../../interfaces/IRoyaltyManager.sol"; // Moved to StoryIntegrationLogic
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import {StoryIntegrationLogic} from "./StoryIntegrationLogic.sol"; // Import new logic contract

/**
 * @title LoanManagementLogic
 * @author Your Name/Team
 * @notice Handles creation, tracking, and settlement of loans.
 * @dev Separated logic from the main LendingProtocol contract.
 */
contract LoanManagementLogic is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    mapping(bytes32 => ILendingProtocol.Loan) public loans;
    mapping(bytes32 => ILendingProtocol.RenegotiationProposal) public renegotiationProposals; // Assuming RenegotiationProposal will be moved to ILendingProtocol.sol

    uint256 private loanCounter;
    uint256 private renegotiationProposalCounter;

    // --- Structs ---
    // struct RenegotiationProposal moved to ILendingProtocol.sol (Natspec and definition removed from here)

    // --- Manager Contracts & Addresses ---
    // ICurrencyManager public currencyManager; // Not directly used in these functions
    IVaultsFactory public vaultsFactory;
    // IRoyaltyManager public royaltyManager; // Moved to StoryIntegrationLogic
    IIPAssetRegistry public ipAssetRegistry; // Still needed for createLoan and determining ipIdToUse
    address public lendingProtocolAddress; // Address of the main LendingProtocol contract
    StoryIntegrationLogic public storyIntegrationLogic;

    // --- Events (mirroring ILendingProtocol) ---
    event OfferAccepted(
        bytes32 indexed loanId,
        bytes32 indexed offerId,
        address indexed borrower,
        address lender,
        address nftContract, // This should be effectiveCollateralContract
        uint256 nftTokenId,  // This should be effectiveCollateralTokenId
        address currency,
        uint256 principalAmount,
        uint64 dueTime
    );

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
        uint256 newPrincipalAmount,
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
        address nftContract,
        uint256 nftTokenId
    );

    // Event for RenegotiationProposalMade - consider adding to ILendingProtocol
    event RenegotiationProposalMade(
        bytes32 indexed proposalId,
        bytes32 indexed loanId,
        address indexed proposer,
        address borrower,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    );

    // --- Constructor ---
    constructor(
        address _lendingProtocolAddress,
        // address _currencyManager, // Not directly used now
        address _vaultsFactory, // Can be address(0)
        // address _royaltyManagerAddress, // Replaced by storyIntegrationLogicAddress
        address _ipAssetRegistryAddress,
        address _storyIntegrationLogicAddress,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_lendingProtocolAddress != address(0), "LML: LendingProtocol zero address");
        // require(_currencyManager != address(0), "LML: CurrencyManager zero address");
        // require(_royaltyManagerAddress != address(0), "LML: RoyaltyManager zero address"); // Removed
        require(_ipAssetRegistryAddress != address(0), "LML: IPAssetRegistry zero address");
        require(_storyIntegrationLogicAddress != address(0), "LML: StoryIntegrationLogic zero address");

        lendingProtocolAddress = _lendingProtocolAddress;
        // currencyManager = ICurrencyManager(_currencyManager);
        if (_vaultsFactory != address(0)) {
            vaultsFactory = IVaultsFactory(_vaultsFactory);
        }
        // royaltyManager = IRoyaltyManager(_royaltyManagerAddress); // Removed
        ipAssetRegistry = IIPAssetRegistry(_ipAssetRegistryAddress);
        storyIntegrationLogic = StoryIntegrationLogic(_storyIntegrationLogicAddress);
    }

    // --- Modifiers (onlyLender, onlyBorrower are removed as auth is handled by LendingProtocol before calling) ---

    // --- Loan Creation Function (called by LendingProtocol) ---
    /**
     * @notice Creates a new loan. Called by LendingProtocol after offer validation and NFT transfer.
     * @dev Assumes NFT is already transferred to lendingProtocolAddress.
     */
    function createLoan(
        bytes32 offerId,
        address borrower, // msg.sender from LendingProtocol.acceptLoanOffer
        address lender,
        address currency,
        uint256 principalAmount,
        uint256 interestRateAPR,
        uint256 durationSeconds, // Changed from uint64 to uint256
        uint256 originationFeeRate,
        address effectiveCollateralContract,
        uint256 effectiveCollateralTokenId,
        bool isVault,
        address loanStoryIpId,
        bool loanIsStoryAsset
    ) external nonReentrant onlyOwner returns (bytes32 loanId) { // onlyOwner restricts to LendingProtocol
        loanCounter++;
        loanId = keccak256(abi.encodePacked("loan", loanCounter, borrower, offerId));
        uint64 startTime = uint64(block.timestamp);
        uint64 dueTime = startTime + uint64(durationSeconds); // Explicit cast if needed, though direct add usually works if types are compatible
        uint256 originationFee = (principalAmount * originationFeeRate) / 10000;

        loans[loanId] = ILendingProtocol.Loan({ // Use qualified name
            loanId: loanId,
            offerId: offerId,
            borrower: borrower,
            lender: lender,
            nftContract: effectiveCollateralContract,
            nftTokenId: effectiveCollateralTokenId,
            isVault: isVault,
            currency: currency,
            principalAmount: principalAmount,
            interestRateAPR: interestRateAPR,
            originationFeePaid: originationFee,
            startTime: startTime,
            dueTime: dueTime,
            accruedInterest: 0,
            status: ILendingProtocol.LoanStatus.ACTIVE, // Use qualified name
            storyIpId: loanStoryIpId,
            isStoryAsset: loanIsStoryAsset
        });

        // Perform fund transfers
        IERC20(currency).safeTransferFrom(lender, borrower, principalAmount - originationFee);
        if (originationFee > 0) {
            IERC20(currency).safeTransferFrom(lender, lender, originationFee);
            // Consider transferring fee to a treasury or the lendingProtocolAddress if it's not for the lender
        }

        emit OfferAccepted(
            loanId,
            offerId,
            borrower,
            lender,
            effectiveCollateralContract,
            effectiveCollateralTokenId,
            currency,
            principalAmount,
            dueTime
        );
        return loanId;
    }

    // --- Loan Management Functions ---

    function calculateInterest(bytes32 loanId) public view returns (uint256) {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Use qualified name
        // require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active"); // This check might be too restrictive if calculating for repaid/defaulted loans
        require(loan.borrower != address(0), "LML: Loan does not exist"); // Basic existence check

        uint256 timeElapsed;
        if (block.timestamp < loan.dueTime) {
            timeElapsed = block.timestamp - loan.startTime;
        } else {
            timeElapsed = loan.dueTime - loan.startTime;
        }
        // Ensure no negative time elapsed if clock is weird or loan.startTime is in future (should not happen)
        if (loan.startTime > block.timestamp && block.timestamp < loan.dueTime) timeElapsed = 0;


        uint256 interest = (loan.principalAmount * loan.interestRateAPR * timeElapsed) / (365 days * 10000);
        return interest;
    }

    function repayLoan(bytes32 loanId, address borrower) external nonReentrant onlyOwner {
        ILendingProtocol.Loan storage currentLoan = loans[loanId]; // Use qualified name
        require(currentLoan.borrower == borrower, "LML: Caller not borrower");
        require(currentLoan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active"); // Use qualified name
        require(block.timestamp <= currentLoan.dueTime, "LML: Loan past due (defaulted)");

        uint256 interest = calculateInterest(loanId);
        uint256 totalRepayment = currentLoan.principalAmount + interest;

        IERC20(currentLoan.currency).safeTransferFrom(borrower, currentLoan.lender, totalRepayment);
        IERC721(currentLoan.nftContract).safeTransferFrom(lendingProtocolAddress, borrower, currentLoan.nftTokenId);

        currentLoan.status = ILendingProtocol.LoanStatus.REPAID; // Use qualified name
        currentLoan.accruedInterest = interest;

        emit LoanRepaid(loanId, borrower, currentLoan.lender, currentLoan.principalAmount, interest);
    }

    function claimAndRepay(bytes32 loanId, address borrower) external nonReentrant onlyOwner {
        ILendingProtocol.Loan storage currentLoan = loans[loanId]; // Use qualified name
        require(currentLoan.borrower == borrower, "LML: Caller not borrower");
        require(currentLoan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active"); // Use qualified name
        // Note: block.timestamp <= currentLoan.dueTime check is not strictly needed if allowing early claim & repay

        address ipIdToUse;
        if (currentLoan.isStoryAsset) {
            require(currentLoan.storyIpId != address(0), "LML: Loan is Story asset but IP ID is missing");
            ipIdToUse = currentLoan.storyIpId;
        } else {
             // If not a story asset, but we still want to check for registration (e.g. for royalties)
            ipIdToUse = ipAssetRegistry.ipId(block.chainid, currentLoan.nftContract, currentLoan.nftTokenId); // Directly assign
            // We might only proceed with royalty logic if ipIdToUse is non-zero and registered.
            if (ipIdToUse != address(0) && !ipAssetRegistry.isRegistered(ipIdToUse)) {
                ipIdToUse = address(0); // Ensure we only use registered IP IDs
            }
        }

        uint256 originalPrincipal = currentLoan.principalAmount;
        uint256 interest = calculateInterest(loanId);
        uint256 totalRepaymentDue = originalPrincipal + interest;
        uint256 amountPaidFromRoyalty = 0;

        if (ipIdToUse != address(0)) {
            amountPaidFromRoyalty = storyIntegrationLogic.attemptRoyaltyPayment(
                loanId,
                ipIdToUse,
                currentLoan.currency,
                totalRepaymentDue,
                currentLoan.lender
            );
        }

        if (amountPaidFromRoyalty >= totalRepaymentDue) {
            // Full repayment via royalty
            currentLoan.accruedInterest = interest; // Or set to the portion of interest covered by royalty if needed
            currentLoan.status = ILendingProtocol.LoanStatus.REPAID; // Use qualified name
            // Royalty was directly sent to lender by StoryIntegrationLogic
            emit LoanRepaid(loanId, borrower, currentLoan.lender, originalPrincipal, interest); // msg.sender was borrower (passed param)
        } else {
            // Partial or no repayment from royalty
            uint256 remainingRepaymentByBorrower = totalRepaymentDue - amountPaidFromRoyalty;
            if (remainingRepaymentByBorrower > 0) {
                IERC20(currentLoan.currency).safeTransferFrom(
                    borrower, currentLoan.lender, remainingRepaymentByBorrower
                );
            }
            currentLoan.accruedInterest = interest; // Total interest due, covered by combo of royalty and borrower
            currentLoan.status = ILendingProtocol.LoanStatus.REPAID; // Use qualified name
            emit LoanRepaid(loanId, borrower, currentLoan.lender, originalPrincipal, interest);
        }

        IERC721(currentLoan.nftContract).safeTransferFrom(lendingProtocolAddress, borrower, currentLoan.nftTokenId);
    }

    function refinanceLoan(
        bytes32 existingLoanId,
        address actualNewLender,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) external nonReentrant onlyOwner returns (bytes32 newLoanId) {
        ILendingProtocol.Loan storage oldLoan = loans[existingLoanId]; // Use qualified name
        require(oldLoan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Old loan not active"); // Use qualified name
        require(actualNewLender != address(0), "LML: Invalid new lender");
        // Validations (e.g. principal, duration, APR improvement) are expected to be done by LendingProtocol before this call.

        // Repay old lender - this transfer comes from the newLender
        uint256 accruedInterest = calculateInterest(existingLoanId);
        uint256 totalRepayToOldLender = oldLoan.principalAmount + accruedInterest;
        IERC20(oldLoan.currency).safeTransferFrom(actualNewLender, oldLoan.lender, totalRepayToOldLender);

        loanCounter++;
        newLoanId = keccak256(abi.encodePacked("loan", loanCounter, oldLoan.borrower, existingLoanId));
        uint64 newStartTime = uint64(block.timestamp);
        uint64 newDueTime = newStartTime + uint64(newDurationSeconds);

        loans[newLoanId] = ILendingProtocol.Loan({ // Use qualified name
            loanId: newLoanId,
            offerId: oldLoan.offerId,
            borrower: oldLoan.borrower,
            lender: actualNewLender,
            nftContract: oldLoan.nftContract,
            nftTokenId: oldLoan.nftTokenId,
            isVault: oldLoan.isVault,
            currency: oldLoan.currency, // Assuming currency remains the same
            principalAmount: newPrincipalAmount,
            interestRateAPR: newInterestRateAPR,
            originationFeePaid: newOriginationFeeRate,
            startTime: newStartTime,
            dueTime: newDueTime,
            accruedInterest: 0,
            status: ILendingProtocol.LoanStatus.ACTIVE, // Use qualified name
            storyIpId: oldLoan.storyIpId,
            isStoryAsset: oldLoan.isStoryAsset
        });

        oldLoan.status = ILendingProtocol.LoanStatus.REPAID; // Or perhaps LoanStatus.REFINANCED // Use qualified name

        emit LoanRefinanced(
            existingLoanId,
            newLoanId,
            oldLoan.borrower,
            oldLoan.lender,
            actualNewLender,
            newPrincipalAmount,
            newInterestRateAPR,
            newDueTime
        );
        return newLoanId;
    }

    function proposeRenegotiation(
        bytes32 loanId,
        address actualProposer,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) external nonReentrant onlyOwner returns (bytes32 proposalId) {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Use qualified name
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active for renegotiation"); // Use qualified name
        require(actualProposer == loan.lender, "LML: Proposer is not the current lender");

        renegotiationProposalCounter++;
        proposalId = keccak256(abi.encodePacked("proposal", renegotiationProposalCounter, loanId, actualProposer));
        renegotiationProposals[proposalId] = ILendingProtocol.RenegotiationProposal({ // Use qualified name
            proposalId: proposalId,
            loanId: loanId,
            proposer: actualProposer,
            borrower: loan.borrower,
            proposedPrincipalAmount: proposedPrincipalAmount,
            proposedInterestRateAPR: proposedInterestRateAPR,
            proposedDurationSeconds: proposedDurationSeconds,
            accepted: false,
            exists: true
        });
        emit RenegotiationProposalMade(proposalId, loanId, actualProposer, loan.borrower, proposedPrincipalAmount, proposedInterestRateAPR, proposedDurationSeconds);
        return proposalId;
    }

    function acceptRenegotiation(bytes32 proposalId, address actualBorrower) external nonReentrant onlyOwner {
        ILendingProtocol.RenegotiationProposal storage proposal = renegotiationProposals[proposalId]; // Use qualified name
        require(proposal.exists, "LML: Proposal does not exist");
        require(!proposal.accepted, "LML: Already accepted");
        require(actualBorrower == proposal.borrower, "LML: Caller not the borrower of this proposal");

        ILendingProtocol.Loan storage loan = loans[proposal.loanId]; // Use qualified name
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active for accepting renegotiation"); // Use qualified name

        loan.principalAmount = proposal.proposedPrincipalAmount;
        loan.interestRateAPR = proposal.proposedInterestRateAPR;
        loan.dueTime = uint64(loan.startTime + proposal.proposedDurationSeconds);

        proposal.accepted = true;

        emit LoanRenegotiated(
            proposal.loanId,
            actualBorrower,
            proposal.proposer,
            proposal.proposedPrincipalAmount,
            proposal.proposedInterestRateAPR,
            loan.dueTime
        );
    }

    // Note: claimCollateral is now split. setLoanStatusDefaulted here, and NFT transfer in CollateralLogic.
    // This function is called by LendingProtocol after it verifies the lender.
    function setLoanStatusDefaulted(bytes32 loanId, address actualLender) external nonReentrant onlyOwner {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Use qualified name
        require(loan.lender == actualLender, "LML: Caller not the lender of this loan");
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active"); // Use qualified name
        require(block.timestamp > loan.dueTime, "LML: Loan not past due (defaulted)");

        loan.status = ILendingProtocol.LoanStatus.DEFAULTED; // Use qualified name
        // CollateralClaimed event will be emitted by CollateralLogic after NFT transfer.
        // Or, we can emit a LoanDefaulted event here. For now, relying on CollateralClaimed.
    }

    // New function to mark loan as repaid after a collateral sale by PurchaseBundler
    function markLoanRepaidBySale(bytes32 loanId, address actualBorrower, uint256 principalRepaid, uint256 interestRepaid) external nonReentrant onlyOwner {
        ILendingProtocol.Loan storage currentLoan = loans[loanId]; // Use qualified name
        // Basic validation, more might be needed depending on trust model with PurchaseBundler/CollateralLogic
        require(currentLoan.borrower == actualBorrower, "LML: Borrower mismatch");
        require(currentLoan.status == ILendingProtocol.LoanStatus.ACTIVE, "LML: Loan not active for sale settlement"); // Use qualified name
        // Assuming principalRepaid from sale is the original principal amount.
        // This might need adjustment if partial principal sales are possible.
        require(principalRepaid == currentLoan.principalAmount, "LML: Principal mismatch in sale settlement");

        currentLoan.accruedInterest = interestRepaid;
        currentLoan.status = ILendingProtocol.LoanStatus.REPAID; // Use qualified name

        emit LoanRepaid(loanId, actualBorrower, currentLoan.lender, currentLoan.principalAmount, interestRepaid);
    }

    // --- View Functions ---
    function getLoan(bytes32 loanId) external view returns (ILendingProtocol.Loan memory) { // Use qualified name
        return loans[loanId];
    }

    function isLoanRepayable(bytes32 loanId) external view returns (bool) {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Use qualified name
        return loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp <= loan.dueTime; // Use qualified name
    }

    function isLoanInDefault(bytes32 loanId) external view returns (bool) {
        ILendingProtocol.Loan storage loan = loans[loanId]; // Use qualified name
        return loan.status == ILendingProtocol.LoanStatus.ACTIVE && block.timestamp > loan.dueTime; // Use qualified name
    }

    function getRenegotiationProposal(bytes32 proposalId) external view returns (ILendingProtocol.RenegotiationProposal memory) { // Use qualified name
        return renegotiationProposals[proposalId];
    }

    // --- Admin functions for setting addresses if needed, though likely set in constructor ---
    // function setLendingProtocolAddress(address _newAddress) external onlyOwner {
    //     require(_newAddress != address(0), "LML: New address is zero");
    //     lendingProtocolAddress = _newAddress;
    // }

    // claimCollateral was removed, its logic is now split:
    // 1. LendingProtocol authenticates lender, checks default conditions.
    // 2. LendingProtocol calls LoanManagementLogic.setLoanStatusDefaulted.
    // 3. LendingProtocol calls CollateralLogic.transferCollateralToLender.
}
