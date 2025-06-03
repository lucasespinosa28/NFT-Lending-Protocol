// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPurchaseBundler} from "../interfaces/IPurchaseBundler.sol";
import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title PurchaseBundler (SellAndRepay)
 * @author Your Name/Team
 * @notice Facilitates selling collateralized NFTs to repay loans.
 * @dev Implements IPurchaseBundler. This is a placeholder implementation.
 */
contract PurchaseBundler is IPurchaseBundler, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ILendingProtocol public lendingProtocol;
    mapping(bytes32 => SaleListing) public saleListings; // listingId (loanId) => SaleListing

    // --- Modifiers ---
    modifier onlyLendingProtocol() {
        require(msg.sender == address(lendingProtocol), "Caller not LendingProtocol");
        _;
    }
     modifier onlySeller(bytes32 listingId) {
        require(saleListings[listingId].seller == msg.sender, "Not seller");
        _;
    }


    constructor(address _lendingProtocolAddress) Ownable(msg.sender) {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }

    function listCollateralForSale(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        uint256 price,
        address currency
        // address specificBuyer // Optional
    ) external override returns (bytes32 listingId) {
        // This function might be called by the borrower directly,
        // or by the LendingProtocol on behalf of the borrower.
        // Let's assume borrower calls it, and this contract verifies with LendingProtocol.
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        require(loan.borrower == msg.sender, "Not borrower of this loan");
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(price > 0, "Price must be > 0");

        // Check if price is sufficient to cover max debt (call LendingProtocol or have it here)
        uint256 maxDebt = getMaximumDebt(loanId); // Implement this getter
        require(price >= maxDebt, "Price too low to cover potential debt");

        listingId = loanId; // Use loanId as listingId for simplicity
        require(!saleListings[listingId].isActive, "Listing already active for this loan");

        saleListings[listingId] = SaleListing({
            loanId: loanId,
            seller: msg.sender, // Borrower
            nftContract: nftContract,
            nftTokenId: nftTokenId,
            isVault: isVault,
            price: price,
            currency: currency,
            isActive: true
            // specificBuyer: specificBuyer
        });

        // LendingProtocol might need to be notified to prevent other actions on the loan/collateral
        // lendingProtocol.markCollateralAsListed(loanId);

        emit CollateralListedForSale(listingId, msg.sender, nftContract, nftTokenId, price, currency);
        return listingId;
    }

    function buyListedCollateral(bytes32 listingId, uint256 paymentAmount) external payable override nonReentrant {
        SaleListing storage listing = saleListings[listingId];
        require(listing.isActive, "Listing not active");
        require(paymentAmount >= listing.price, "Payment amount too low");
        // If specificBuyer is set, require(msg.sender == listing.specificBuyer || listing.specificBuyer == address(0))

        // Handle payment
        if (listing.currency == address(0)) { // Native ETH
            require(msg.value == paymentAmount, "Incorrect ETH amount");
        } else { // ERC20
            require(msg.value == 0, "ETH sent for ERC20 sale");
            IERC20(listing.currency).safeTransferFrom(msg.sender, address(this), paymentAmount);
        }

        // At this point, this contract holds the payment.
        // The NFT is still in escrow in the LendingProtocol contract.

        // 1. Calculate amount needed to repay the loan
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(listing.loanId);
        uint256 interest = lendingProtocol.calculateInterest(listing.loanId);
        uint256 totalDebt = loan.principalAmount + interest;

        require(paymentAmount >= totalDebt, "Internal: Payment less than total debt despite initial check. Price changed?");

        // 2. Transfer debt amount to LendingProtocol to repay the loan.
        // LendingProtocol will handle paying the lender.
        if (listing.currency == address(0)) {
            // This is tricky. LendingProtocol needs to be payable and handle this.
            // Or this contract pays lender directly if it knows who it is.
            // For now, assume LendingProtocol has a payable function to receive repayment.
            // payable(address(lendingProtocol)).call{value: totalDebt}(""); // Simplified, needs proper handling
            revert("Native ETH repayment to LendingProtocol not fully implemented here");
        } else {
            IERC20(listing.currency).safeTransfer(address(lendingProtocol), totalDebt);
        }
        // LendingProtocol needs a function like `receiveRepaymentFromBundler(loanId, totalDebt)`

        // 3. LendingProtocol transfers NFT from its escrow to the buyer (msg.sender)
        // This must be coordinated. LendingProtocol needs to expose a function for this.
        // lendingProtocol.transferSoldCollateral(listing.loanId, msg.sender);

        // 4. Transfer surplus to seller (borrower)
        uint256 surplus = paymentAmount - totalDebt;
        if (surplus > 0) {
            if (listing.currency == address(0)) {
                payable(listing.seller).transfer(surplus);
            } else {
                IERC20(listing.currency).safeTransfer(listing.seller, surplus);
            }
        }

        listing.isActive = false; // Mark listing as completed

        // This event should ideally be emitted by LendingProtocol after it confirms repayment and NFT transfer
        emit CollateralSoldAndRepaid(listing.loanId, msg.sender, listing.nftContract, listing.nftTokenId, paymentAmount, totalDebt, surplus);

        // For a real implementation, the interaction with LendingProtocol needs to be robust,
        // potentially using a specific function on LendingProtocol that handles these steps atomically
        // e.g., lendingProtocol.executeSaleAndRepay(listing.loanId, msg.sender (buyer), paymentAmount);
        // And this `buyListedCollateral` function would just transfer funds to LendingProtocol.
    }

    function cancelSaleListing(bytes32 listingId) external override onlySeller(listingId) nonReentrant {
        SaleListing storage listing = saleListings[listingId];
        require(listing.isActive, "Listing not active");

        listing.isActive = false;
        // Notify LendingProtocol if needed: lendingProtocol.markCollateralAsUnlisted(listingId);

        emit SaleListingCancelled(listingId, msg.sender);
    }

    function getSaleListing(bytes32 listingId) external view override returns (SaleListing memory) {
        return saleListings[listingId];
    }

    function getMaximumDebt(bytes32 loanId) public view override returns (uint256) {
        // This needs to calculate principal + max possible interest until due date.
        // It should ideally call a view function on LendingProtocol or replicate its interest logic.
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        if(loan.borrower == address(0)) return type(uint256).max; // Loan doesn't exist or no access

        uint256 timeToEnd = loan.dueTime > uint64(block.timestamp) ? loan.dueTime - loan.startTime : 0;
        // Using the same interest calculation as in LendingProtocol (simplified)
        uint256 SECONDS_IN_YEAR = 365 days;
        uint256 maxInterest = (loan.principalAmount * loan.interestRateAPR * timeToEnd) / (10000 * SECONDS_IN_YEAR);
        return loan.principalAmount + maxInterest;
    }

    // --- Admin ---
    function setLendingProtocol(address _lendingProtocolAddress) external onlyOwner {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }
}
