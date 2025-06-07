// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "../../interfaces/ILendingProtocol.sol"; // Import all top-level items
import {IPurchaseBundler} from "../../interfaces/IPurchaseBundler.sol";
// Forward declaration for LoanManagementLogic if direct calls were needed, but prefer parameters or LP mediation
// interface ILoanManagementLogic {
// function calculateInterest(bytes32 loanId) external view returns (uint256);
// function markLoanRepaid(bytes32 loanId, uint256 interestPaid) external;
// function markLoanDefaulted(bytes32 loanId) external;
// }

contract CollateralLogic is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public lendingProtocolAddress; // Address of the main LendingProtocol contract (NFT holder)
    IPurchaseBundler public purchaseBundler;
    // address public loanManagementLogicAddress; // If direct calls are made

    // --- Events (mirroring ILendingProtocol) ---
    event CollateralClaimed(
        bytes32 indexed loanId,
        address indexed lender,
        address nftContract,
        uint256 nftTokenId
    );

    event CollateralListedForSale(
        bytes32 indexed loanId,
        address indexed seller, // borrower
        address nftContract,
        uint256 nftTokenId,
        uint256 price
    );

    event CollateralSaleCancelled(bytes32 indexed loanId, address indexed seller); // borrower

    event CollateralSoldAndRepaid(
        bytes32 indexed loanId,
        address indexed buyer,
        address nftContract,
        uint256 nftTokenId,
        uint256 salePrice,
        uint256 repaymentAmount // principal + interest
    );

    constructor(
        address _lendingProtocolAddress,
        address _purchaseBundlerAddress,
        // address _loanManagementLogicAddress,
        address _initialOwner // LendingProtocol address
    ) Ownable(_initialOwner) {
        require(_lendingProtocolAddress != address(0), "CL: LendingProtocol zero address");
        require(_purchaseBundlerAddress != address(0), "CL: PurchaseBundler zero address");
        // require(_loanManagementLogicAddress != address(0), "CL: LoanManagementLogic zero address");

        lendingProtocolAddress = _lendingProtocolAddress;
        purchaseBundler = IPurchaseBundler(_purchaseBundlerAddress);
        // loanManagementLogicAddress = _loanManagementLogicAddress;
    }

    /**
     * @notice Transfers collateral to the lender for a defaulted loan.
     * @dev Called by LendingProtocol after verifying loan default status with LoanManagementLogic.
     * Loan status should be set to DEFAULTED by LoanManagementLogic prior to this call or as part of the same LP tx.
     */
    function transferCollateralToLender(
        bytes32 loanId, // For event
        address lender,
        address nftContract,
        uint256 nftTokenId
    ) external nonReentrant onlyOwner { // onlyOwner: callable by LendingProtocol
        IERC721(nftContract).safeTransferFrom(lendingProtocolAddress, lender, nftTokenId);
        emit CollateralClaimed(loanId, lender, nftContract, nftTokenId);
    }

    /**
     * @notice Lists collateral for sale via the PurchaseBundler.
     * @dev Called by LendingProtocol on behalf of the borrower.
     */
    function listCollateralForSale(
        // Loan calldata currentLoan, // Pass necessary loan fields instead of full struct for clarity
        bytes32 loanId,
        address borrower, // msg.sender from LP
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        uint256 price,
        address currency // For PurchaseBundler listing
    ) external nonReentrant onlyOwner { // onlyOwner: callable by LendingProtocol
        // Approve PurchaseBundler to take the NFT on sale
        // Approval must be done on lendingProtocolAddress itself, or this contract needs approval authority
        // For now, assume LendingProtocol handles approvals if needed, or this contract is an operator
        IERC721(nftContract).approve(address(purchaseBundler), nftTokenId); // This needs to be called from LP context or CL needs approval

        purchaseBundler.listCollateralForSale(
            loanId,
            nftContract,
            nftTokenId,
            isVault,
            price,
            currency,
            borrower // actualSeller
        );

        emit CollateralListedForSale(loanId, borrower, nftContract, nftTokenId, price);
    }

    /**
     * @notice Cancels an active collateral sale listing.
     * @dev Called by LendingProtocol on behalf of the borrower.
     *      Actual cancellation logic might be in PurchaseBundler.
     */
    function cancelCollateralSale(
        bytes32 loanId,
        address borrower // msg.sender from LP
        // Potentially needs parameters for PurchaseBundler.cancelCollateralSale if any
    ) external nonReentrant onlyOwner { // onlyOwner: callable by LendingProtocol
        // Call PurchaseBundler to cancel it, if such a direct function exists.
        // Often, cancellation might mean unlisting or PurchaseBundler having its own cancel mechanism.
        // For now, just emitting event as per ILendingProtocol.
        // purchaseBundler.cancelListing(loanId); // Example if such a function existed

        emit CollateralSaleCancelled(loanId, borrower);
    }

    /**
     * @notice Handles the purchase of collateral and repays the loan.
     * @dev Called by LendingProtocol. Buyer (msg.sender in LP) sends funds.
     *      This function orchestrates payments and NFT transfer.
     *      Loan status update (REPAID) should be handled by LoanManagementLogic,
     *      potentially called by LendingProtocol after this.
     * @param loanId The ID of the loan associated with the collateral.
     * @param buyer The address of the buyer (msg.sender from LP).
     * @param loanLender The address of the original lender.
     * @param loanBorrower The address of the original borrower.
     * @param loanCurrency The currency of the loan.
     * @param loanNftContract The contract address of the collateral NFT.
     * @param loanNftTokenId The token ID of the collateral NFT.
     * @param salePrice The price at which the collateral is sold.
     * @param totalRepaymentNeeded Principal + interest for the loan.
     */
    function buyCollateralAndRepayLoan(
        bytes32 loanId,
        address buyer,
        address loanLender,
        address loanBorrower,
        address loanCurrency,
        address loanNftContract,
        uint256 loanNftTokenId,
        uint256 salePrice, // Amount buyer sent to LP
        uint256 totalRepaymentNeeded
    ) external nonReentrant onlyOwner { // onlyOwner: callable by LendingProtocol
        // require(salePrice >= totalRepaymentNeeded, "CL: Sale price too low"); // This check is now expected to be done by LendingProtocol before calling.

        // Funds are with LendingProtocol. This function just dictates transfers.
        // LendingProtocol will execute these transfers based on events or return values if preferred.
        // For now, assuming CollateralLogic has authority or LP will make transfers based on emitted event data.

        // 1. Buyer pays totalRepayment to Lender (from salePrice)
        IERC20(loanCurrency).safeTransferFrom(buyer, loanLender, totalRepaymentNeeded); // This implies buyer's funds are here or approved

        // 2. Buyer pays remainder (salePrice - totalRepayment) to Borrower
        if (salePrice > totalRepaymentNeeded) {
            IERC20(loanCurrency).safeTransferFrom(buyer, loanBorrower, salePrice - totalRepaymentNeeded);
        }

        // 3. Transfer NFT from LendingProtocol to Buyer
        IERC721(loanNftContract).safeTransferFrom(lendingProtocolAddress, buyer, loanNftTokenId);

        // LP is responsible for calling LoanManagementLogic to mark loan as REPAID.
        // currentLoan.status = LoanStatus.REPAID; (in LoanManagementLogic)
        // currentLoan.accruedInterest = interest; (in LoanManagementLogic)

        emit CollateralSoldAndRepaid(loanId, buyer, loanNftContract, loanNftTokenId, salePrice, totalRepaymentNeeded);
    }

    /**
     * @notice Records loan repayment details after a sale processed by PurchaseBundler.
     * @dev Callable only by the PurchaseBundler contract.
     *      LendingProtocol is responsible for calling LoanManagementLogic to update loan status.
     * @param principalRepaid The amount of principal repaid from the sale.
     * @param interestRepaid The amount of interest repaid from the sale.
     * @param loanCurrency The currency of the loan, for transfer.
     * @param loanLender The lender to whom funds should be transferred.
     */
    function recordLoanRepaymentDetailsViaSale(
        address, // caller - Original msg.sender to PurchaseBundler, for validation (now unused)
        bytes32, // loanId - (now unused)
        uint256 principalRepaid,
        uint256 interestRepaid,
        address loanCurrency,
        address loanLender
        // address currentLoanBorrower // For event, if needed, but LP has this
    ) external nonReentrant {
        require(msg.sender == address(purchaseBundler), "CL: Caller not PurchaseBundler");
        // require(caller == lendingProtocolAddress, "CL: Original caller not LendingProtocol"); // Optional: ensure PB was called by LP

        // PurchaseBundler should have already sent funds (principalRepaid + interestRepaid) to lendingProtocolAddress.
        // This function tells LendingProtocol to forward those specific amounts to the lender.
        IERC20(loanCurrency).safeTransfer(loanLender, principalRepaid + interestRepaid); // Transfer from LP to lender

        // LendingProtocol is responsible for calling LoanManagementLogic to update loan status.
        // emit LoanRepaid(loanId, currentLoanBorrower, loanLender, principalRepaid, interestRepaid); // This event is from LML
        // This function might not need to emit its own event if LP emits a broader one or LML's LoanRepaid is sufficient.
    }
}
