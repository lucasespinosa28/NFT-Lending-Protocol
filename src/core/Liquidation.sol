// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";
import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol"; // To interact back if needed
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title Liquidation
 * @author Your Name/Team
 * @notice Manages liquidation of defaulted loan collateral via auctions or buyouts.
 * @dev Implements ILiquidation. This is a placeholder implementation.
 */
contract Liquidation is ILiquidation, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ILendingProtocol public lendingProtocol; // Address of the main lending protocol

    mapping(bytes32 => Auction) public auctions; // auctionId => Auction details
    mapping(bytes32 => Buyout) public buyouts;   // loanId => Buyout details

    uint256 private auctionCounter;

    struct Buyout {
        bytes32 loanId;
        address largestLender;
        uint256 buyoutPrice; // Total to pay other tranches
        uint64 buyoutDeadline;
        bool isActive;
        bool completed;
    }

    // --- Modifiers ---
    modifier onlyLendingProtocol() {
        require(msg.sender == address(lendingProtocol), "Caller not LendingProtocol");
        _;
    }

    constructor(address _lendingProtocolAddress) Ownable(msg.sender) {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }

    // --- Buyout Logic ---
    function initiateBuyout(
        bytes32 loanId,
        address largestLender,
        uint256 buyoutPrice,
        uint64 buyoutDeadline
    ) external override onlyLendingProtocol { // Or restricted access
        require(!buyouts[loanId].isActive, "Buyout already active");
        buyouts[loanId] = Buyout({
            loanId: loanId,
            largestLender: largestLender,
            buyoutPrice: buyoutPrice,
            buyoutDeadline: buyoutDeadline,
            isActive: true,
            completed: false
        });
        emit BuyoutInitiated(loanId, largestLender, buyoutPrice, buyoutDeadline);
    }

    function executeBuyout(bytes32 loanId) external payable override nonReentrant {
        Buyout storage currentBuyout = buyouts[loanId];
        require(currentBuyout.isActive, "Buyout not active");
        require(!currentBuyout.completed, "Buyout already completed");
        require(msg.sender == currentBuyout.largestLender, "Not largest lender");
        require(block.timestamp <= currentBuyout.buyoutDeadline, "Buyout deadline passed");

        // This function needs to know the currency and the tranches to pay.
        // Assuming currency is msg.value if native, or ERC20 transfer.
        // For simplicity, this placeholder doesn't handle ERC20 payment or tranche distribution.
        // It would require more details on loan structure from ILendingProtocol.
        // Example: ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        // IERC20(loan.currency).safeTransferFrom(msg.sender, address(this), currentBuyout.buyoutPrice);
        // Then distribute to other lenders based on their shares.

        // Placeholder: Assume payment is handled and verified.
        // This part is highly dependent on how tranches are structured and paid.

        currentBuyout.completed = true;
        currentBuyout.isActive = false;

        // After buyout, the largestLender effectively owns the whole loan/collateral.
        // The LendingProtocol might need to update its state or transfer collateral.
        // lendingProtocol.finalizeBuyoutAndTransferCollateral(loanId, msg.sender);

        emit BuyoutCompleted(loanId, msg.sender, currentBuyout.buyoutPrice);
    }

    function isBuyoutActive(bytes32 loanId) external view override returns (bool) {
        return buyouts[loanId].isActive && block.timestamp <= buyouts[loanId].buyoutDeadline;
    }


    // --- Auction Logic ---
    function startAuction(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        address currency,
        uint256 startingBid,
        uint64 auctionDuration,
        address[] calldata lenders, // For multi-tranche distribution
        uint256[] calldata lenderShares // Pro-rata shares
    ) external override onlyLendingProtocol returns (bytes32 auctionId) { // Or restricted access
        auctionCounter++;
        auctionId = keccak256(abi.encodePacked("auction", auctionCounter, loanId));

        require(auctionDuration > 0, "Duration must be > 0");
        require(startingBid > 0, "Starting bid must be > 0"); // Or allow 0 for some strategies

        auctions[auctionId] = Auction({
            loanId: loanId,
            nftContract: nftContract,
            nftTokenId: nftTokenId,
            isVault: isVault,
            currency: currency,
            startingBid: startingBid,
            highestBid: 0, // No bids yet
            highestBidder: address(0),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp) + auctionDuration,
            status: AuctionStatus.ACTIVE,
            lenders: lenders,
            lenderShares: lenderShares
        });

        emit AuctionStarted(auctionId, loanId, nftContract, nftTokenId, startingBid, auctions[auctionId].endTime);
        return auctionId;
    }

    function placeBid(bytes32 auctionId, uint256 amount) external payable override nonReentrant {
        Auction storage currentAuction = auctions[auctionId];
        require(currentAuction.status == AuctionStatus.ACTIVE, "Auction not active");
        require(block.timestamp < currentAuction.endTime, "Auction ended");
        require(amount > currentAuction.highestBid, "Bid too low"); // Simple check
        // Add min bid increment rule: e.g. amount >= currentAuction.highestBid * 105 / 100

        // Handle payment
        if (currentAuction.currency == address(0)) { // Native ETH
            require(msg.value == amount, "Incorrect ETH amount");
        } else { // ERC20
            require(msg.value == 0, "ETH sent for ERC20 auction");
            IERC20(currentAuction.currency).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Refund previous highest bidder
        if (currentAuction.highestBidder != address(0)) {
            if (currentAuction.currency == address(0)) {
                payable(currentAuction.highestBidder).transfer(currentAuction.highestBid);
            } else {
                IERC20(currentAuction.currency).safeTransfer(currentAuction.highestBidder, currentAuction.highestBid);
            }
        }

        currentAuction.highestBid = amount;
        currentAuction.highestBidder = msg.sender;

        emit BidPlaced(auctionId, msg.sender, amount);
    }

    function endAuction(bytes32 auctionId) external override nonReentrant {
        Auction storage currentAuction = auctions[auctionId];
        require(currentAuction.status == AuctionStatus.ACTIVE, "Auction not ended or already processed");
        require(block.timestamp >= currentAuction.endTime, "Auction not yet ended");

        if (currentAuction.highestBidder == address(0)) {
            // No bids
            currentAuction.status = AuctionStatus.ENDED_NO_BIDS;
            emit AuctionEnded(auctionId, address(0), 0);
            // Collateral might be claimable by original lender(s) via claimCollateralPostAuction
        } else {
            // Auction successful
            currentAuction.status = AuctionStatus.ENDED_SOLD;

            // Transfer NFT to highestBidder
            // The NFT is held by LendingProtocol, so it needs to make the transfer
            // This contract signals LendingProtocol or LendingProtocol pulls NFT from itself
            // For simplicity, assume this contract can instruct LendingProtocol, or has temporary custody.
            // A better design: LendingProtocol calls endAuction, then handles NFT transfer.
            // If NFT is held here:
            // IERC721(currentAuction.nftContract).safeTransferFrom(address(this), currentAuction.highestBidder, currentAuction.nftTokenId);

            emit AuctionEnded(auctionId, currentAuction.highestBidder, currentAuction.highestBid);
            // Next step is distributeProceeds
        }
    }

    function distributeProceeds(bytes32 auctionId) external override nonReentrant {
        Auction storage currentAuction = auctions[auctionId];
        require(currentAuction.status == AuctionStatus.ENDED_SOLD, "Auction not sold or already distributed");

        uint256 totalProceeds = currentAuction.highestBid;
        // Logic to distribute totalProceeds to currentAuction.lenders based on currentAuction.lenderShares
        // This requires careful handling of pro-rata or senior/junior tranche logic.
        // Example: Pro-rata based on lenderShares summing to total debt or a fixed share percentage.
        // For simplicity, let's assume lenderShares are amounts owed and we distribute proportionally if proceeds are less.

        uint256 totalShares = 0;
        for(uint i=0; i < currentAuction.lenderShares.length; i++){
            totalShares += currentAuction.lenderShares[i];
        }

        if (totalShares > 0) { // Avoid division by zero
            for (uint i = 0; i < currentAuction.lenders.length; i++) {
                if (currentAuction.lenders[i] != address(0)) {
                    uint256 paymentAmount = (totalProceeds * currentAuction.lenderShares[i]) / totalShares;
                    if (paymentAmount > 0) {
                        if (currentAuction.currency == address(0)) {
                            payable(currentAuction.lenders[i]).transfer(paymentAmount);
                        } else {
                            IERC20(currentAuction.currency).safeTransfer(currentAuction.lenders[i], paymentAmount);
                        }
                    }
                }
            }
        }


        currentAuction.status = AuctionStatus.SETTLED;
        emit ProceedsDistributed(auctionId, totalProceeds);
    }

    function claimCollateralPostAuction(bytes32 auctionId) external override nonReentrant {
        Auction storage currentAuction = auctions[auctionId];
        require(currentAuction.status == AuctionStatus.ENDED_NO_BIDS, "Auction did not end with no bids");
        // require(msg.sender is one of the original lenders for this loanId) - complex check involving LendingProtocol

        // Logic for original lender(s) to claim collateral.
        // If multiple lenders, how is it decided? Pro-rata NFT ownership (complex) or one claims?
        // This part is highly protocol-specific.
        // For simplicity, assume a single original lender can claim or it's managed via LendingProtocol.
        // Example: lendingProtocol.handleFailedAuctionCollateralClaim(currentAuction.loanId, msg.sender);

        emit CollateralClaimedPostAuction(auctionId, msg.sender);
        // NFT transfer would be handled by LendingProtocol or here if it holds collateral.
        currentAuction.status = AuctionStatus.SETTLED; // Or a new status like "CLAIMED_POST_AUCTION"
    }


    function getAuction(bytes32 auctionId) external view override returns (Auction memory) {
        return auctions[auctionId];
    }

    // --- Admin ---
    function setLendingProtocol(address _lendingProtocolAddress) external onlyOwner {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }
}

