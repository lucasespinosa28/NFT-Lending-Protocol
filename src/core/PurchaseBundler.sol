// SPDX-License-Identifier: MIT
pragma solidity 0.8.30; // Assuming you want all files at 0.8.26

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
        // Removed: require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        // lendingProtocol will be set by setLendingProtocol()
        if (_lendingProtocolAddress != address(0)) {
            // Allow initialization if provided, but don't require
            lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
        }
    }

    function listCollateralForSale(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        uint256 price,
        address currency
    ) external override returns (bytes32 listingId) {
        require(address(lendingProtocol) != address(0), "LP not set");
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        require(loan.borrower == msg.sender, "Not borrower of this loan");
        require(loan.status == ILendingProtocol.LoanStatus.ACTIVE, "Loan not active");
        require(price > 0, "Price must be > 0");

        uint256 maxDebt = getMaximumDebt(loanId);
        require(price >= maxDebt, "Price too low to cover potential debt");

        listingId = loanId;
        require(!saleListings[listingId].isActive, "Listing already active for this loan");

        saleListings[listingId] = SaleListing({
            loanId: loanId,
            seller: msg.sender,
            nftContract: nftContract,
            nftTokenId: nftTokenId,
            isVault: isVault,
            price: price,
            currency: currency,
            isActive: true
        });

        emit CollateralListedForSale(listingId, msg.sender, nftContract, nftTokenId, price, currency);
        return listingId;
    }

    function buyListedCollateral(bytes32 listingId, uint256 paymentAmount) external payable override nonReentrant {
        require(address(lendingProtocol) != address(0), "LP not set");
        SaleListing storage listing = saleListings[listingId];
        require(listing.isActive, "Listing not active");
        require(paymentAmount >= listing.price, "Payment amount too low");

        if (listing.currency == address(0)) {
            require(msg.value == paymentAmount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "ETH sent for ERC20 sale");
            IERC20(listing.currency).safeTransferFrom(msg.sender, address(this), paymentAmount);
        }

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(listing.loanId);
        uint256 interest = lendingProtocol.calculateInterest(listing.loanId);
        uint256 totalDebt = loan.principalAmount + interest;

        require(
            paymentAmount >= totalDebt, "Internal: Payment less than total debt despite initial check. Price changed?"
        );

        if (listing.currency == address(0)) {
            revert("Native ETH repayment to LendingProtocol not fully implemented here");
        } else {
            IERC20(listing.currency).safeTransfer(address(lendingProtocol), totalDebt);
        }

        uint256 surplus = paymentAmount - totalDebt;
        if (surplus > 0) {
            if (listing.currency == address(0)) {
                payable(listing.seller).transfer(surplus);
            } else {
                IERC20(listing.currency).safeTransfer(listing.seller, surplus);
            }
        }

        listing.isActive = false;

        emit CollateralSoldAndRepaid(
            listing.loanId, msg.sender, listing.nftContract, listing.nftTokenId, paymentAmount, totalDebt, surplus
        );
    }

    function cancelSaleListing(bytes32 listingId) external override onlySeller(listingId) nonReentrant {
        SaleListing storage listing = saleListings[listingId];
        require(listing.isActive, "Listing not active");

        listing.isActive = false;

        emit SaleListingCancelled(listingId, msg.sender);
    }

    function getSaleListing(bytes32 listingId) external view override returns (SaleListing memory) {
        return saleListings[listingId];
    }

    function getMaximumDebt(bytes32 loanId) public view override returns (uint256) {
        require(address(lendingProtocol) != address(0), "LP not set");
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        if (loan.borrower == address(0)) return type(uint256).max;

        uint256 timeToEnd = loan.dueTime > uint64(block.timestamp) ? loan.dueTime - loan.startTime : 0;
        uint256 SECONDS_IN_YEAR = 365 days;
        uint256 maxInterest = (loan.principalAmount * loan.interestRateAPR * timeToEnd) / (10000 * SECONDS_IN_YEAR);
        return loan.principalAmount + maxInterest;
    }

    // --- Admin ---
    function setLendingProtocol(address _lendingProtocolAddress) external onlyOwner {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address for setter");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }
}
