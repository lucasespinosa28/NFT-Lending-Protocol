// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILendingProtocol} from "../../interfaces/ILendingProtocol.sol";
import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Placeholder for LoanManager's loans mapping and loanCounter.
interface ILoanManagerForRefinance {
    function getLoan(bytes32 loanId) external view returns (ILendingProtocol.Loan memory);
    function setLoanStatus(bytes32 loanId, ILendingProtocol.LoanStatus status) external;
    function incrementLoanCounter() external returns (uint256);
    function addLoan(bytes32 loanId, ILendingProtocol.Loan memory loanData) external; // Changed to memory
    function calculateInterest(bytes32 loanId) external view returns (uint256);
    function updateLoanAfterRenegotiation(
        bytes32 loanId,
        uint256 newPrincipal,
        uint256 newAPR,
        uint64 newDueTime
    ) external;
}

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

contract RefinanceManager is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- State Variables ---
    mapping(bytes32 => RenegotiationProposal) public renegotiationProposals; // Corrected
    uint256 internal renegotiationProposalCounter;

    // Event definitions are now taken from ILendingProtocol.sol

    // --- External Dependencies (assumed to be available from inheriting contract e.g. LendingProtocol) ---
    function _getLoan(bytes32 loanId) internal view virtual returns (ILendingProtocol.Loan memory) { revert("RM: LoanManager not set"); }
    function _setLoanStatus(bytes32 loanId, ILendingProtocol.LoanStatus status) internal virtual { revert("RM: LoanManager not set"); }
    function _incrementLoanCounter() internal virtual returns (uint256) { revert("RM: LoanManager not set"); }
    function _addLoan(bytes32 loanId, ILendingProtocol.Loan memory loanData) internal virtual { revert("RM: LoanManager not set"); } // Changed to memory
    function _calculateInterest(bytes32 loanId) internal view virtual returns (uint256) { revert("RM: LoanManager not set"); }
    function _updateLoanAfterRenegotiation(bytes32 loanId, uint256 newPrincipal, uint256 newAPR, uint64 newDueTime) internal virtual {
        revert("RM: LoanManager not set for renegotiation update");
    }
    function _getCurrencyManager() internal view virtual returns (ICurrencyManager) { revert("RM: CurrencyManager not set"); }


    // --- Functions ---

    function refinanceLoan(
        bytes32 existingLoanId,
        uint256 newPrincipalAmount,
        uint256 newInterestRateAPR,
        uint256 newDurationSeconds,
        uint256 newOriginationFeeRate
    ) public virtual nonReentrant returns (bytes32 newLoanId) { // Changed to public
        ILendingProtocol.Loan memory oldLoan = _getLoan(existingLoanId);
        require(oldLoan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender != address(0), "Invalid lender");
        require(newPrincipalAmount >= oldLoan.principalAmount, "Principal must be >= old");
        require(newDurationSeconds >= oldLoan.dueTime - oldLoan.startTime, "Duration must be >= old");
        require(newInterestRateAPR <= oldLoan.interestRateAPR * 95 / 100, "APR not improved by 5%");

        uint256 accruedInterest = _calculateInterest(existingLoanId);
        uint256 totalRepayToOldLender = oldLoan.principalAmount + accruedInterest;
        IERC20(oldLoan.currency).safeTransferFrom(msg.sender, oldLoan.lender, totalRepayToOldLender);

        uint256 currentLoanCounter = _incrementLoanCounter();
        newLoanId = keccak256(abi.encodePacked("loan", currentLoanCounter, oldLoan.borrower, existingLoanId));

        ILendingProtocol.Loan memory newLoanData = ILendingProtocol.Loan({
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
            status: ILendingProtocol.LoanStatus.ACTIVE,
            storyIpId: oldLoan.storyIpId,
            isStoryAsset: oldLoan.isStoryAsset
        });
        _addLoan(newLoanId, newLoanData);

        _setLoanStatus(existingLoanId, ILendingProtocol.LoanStatus.REPAID);

        emit ILendingProtocol.LoanRefinanced( // Qualified
            existingLoanId,
            newLoanId,
            oldLoan.borrower,
            oldLoan.lender,
            msg.sender,
            newPrincipalAmount,
            newInterestRateAPR,
            newLoanData.dueTime
        );
        return newLoanId;
    }

    function proposeRenegotiation(
        bytes32 loanId,
        uint256 proposedPrincipalAmount,
        uint256 proposedInterestRateAPR,
        uint256 proposedDurationSeconds
    ) public virtual nonReentrant returns (bytes32 proposalId) { // Changed to public
        ILendingProtocol.Loan memory loan = _getLoan(loanId);
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(msg.sender == loan.lender, "Only lender can propose");

        renegotiationProposalCounter++;
        proposalId = keccak256(abi.encodePacked("proposal", renegotiationProposalCounter, loanId, msg.sender));
        renegotiationProposals[proposalId] = RenegotiationProposal({ // Corrected
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
        return proposalId;
    }

    function acceptRenegotiation(bytes32 proposalId) public virtual nonReentrant { // Changed to public
        RenegotiationProposal storage proposal = renegotiationProposals[proposalId]; // Corrected
        require(proposal.exists, "Proposal does not exist");
        require(!proposal.accepted, "Already accepted");
        require(msg.sender == proposal.borrower, "Only borrower can accept");

        ILendingProtocol.Loan memory loan = _getLoan(proposal.loanId);
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");

        uint64 newDueTime = uint64(loan.startTime + proposal.proposedDurationSeconds);

        _updateLoanAfterRenegotiation(
            proposal.loanId,
            proposal.proposedPrincipalAmount,
            proposal.proposedInterestRateAPR,
            newDueTime
        );

        proposal.accepted = true;

        emit ILendingProtocol.LoanRenegotiated( // Qualified
            proposal.loanId,
            proposal.borrower,
            proposal.proposer,
            proposal.proposedPrincipalAmount,
            proposal.proposedInterestRateAPR,
            newDueTime
        );
    }
}
