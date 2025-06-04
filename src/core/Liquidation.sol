// SPDX-License-Identifier: MIT
pragma solidity 0.8.30; // Assuming you want all files at 0.8.26

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";
import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol";
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
    mapping(bytes32 => Buyout) public buyouts; // loanId => Buyout details

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
        // Removed: require(_lendingProtocolAddress != address(0), "Lending protocol zero address");
        // lendingProtocol will be set by setLendingProtocol()
        if (_lendingProtocolAddress != address(0)) {
            // Allow initialization if provided, but don't require
            lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
        }
    }

    // --- Buyout Logic ---
    function initiateBuyout(bytes32 loanId, address largestLender, uint256 buyoutPrice, uint64 buyoutDeadline)
        external
        override
        onlyLendingProtocol
    {
        require(address(lendingProtocol) != address(0), "LP not set");
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
        require(address(lendingProtocol) != address(0), "LP not set");
        Buyout storage currentBuyout = buyouts[loanId];
        require(currentBuyout.isActive, "Buyout not active");
        require(!currentBuyout.completed, "Buyout already completed");
        require(msg.sender == currentBuyout.largestLender, "Not largest lender");
        require(block.timestamp <= currentBuyout.buyoutDeadline, "Buyout deadline passed");

        currentBuyout.completed = true;
        currentBuyout.isActive = false;

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
        address[] calldata lenders,
        uint256[] calldata lenderShares
    ) external override onlyLendingProtocol returns (bytes32 auctionId) {
        require(address(lendingProtocol) != address(0), "LP not set");
        auctionCounter++;
        auctionId = keccak256(abi.encodePacked("auction", auctionCounter, loanId));

        require(auctionDuration > 0, "Duration must be > 0");
        require(startingBid > 0, "Starting bid must be > 0");

        auctions[auctionId] = Auction({
            loanId: loanId,
            nftContract: nftContract,
            nftTokenId: nftTokenId,
            isVault: isVault,
            currency: currency,
            startingBid: startingBid,
            highestBid: 0,
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
        require(amount > currentAuction.highestBid, "Bid too low");

        if (currentAuction.currency == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "ETH sent for ERC20 auction");
            IERC20(currentAuction.currency).safeTransferFrom(msg.sender, address(this), amount);
        }

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
            currentAuction.status = AuctionStatus.ENDED_NO_BIDS;
            emit AuctionEnded(auctionId, address(0), 0);
        } else {
            currentAuction.status = AuctionStatus.ENDED_SOLD;
            emit AuctionEnded(auctionId, currentAuction.highestBidder, currentAuction.highestBid);
        }
    }

    function distributeProceeds(bytes32 auctionId) external override nonReentrant {
        Auction storage currentAuction = auctions[auctionId];
        require(currentAuction.status == AuctionStatus.ENDED_SOLD, "Auction not sold or already distributed");
        require(address(lendingProtocol) != address(0), "LP not set"); // Ensure LP is set for safety

        uint256 totalProceeds = currentAuction.highestBid;

        uint256 totalShares = 0;
        for (uint256 i = 0; i < currentAuction.lenderShares.length; i++) {
            totalShares += currentAuction.lenderShares[i];
        }

        if (totalShares > 0) {
            for (uint256 i = 0; i < currentAuction.lenders.length; i++) {
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
        require(address(lendingProtocol) != address(0), "LP not set");

        emit CollateralClaimedPostAuction(auctionId, msg.sender);
        currentAuction.status = AuctionStatus.SETTLED;
    }

    function getAuction(bytes32 auctionId) external view override returns (Auction memory) {
        return auctions[auctionId];
    }

    // --- Admin ---
    function setLendingProtocol(address _lendingProtocolAddress) external onlyOwner {
        require(_lendingProtocolAddress != address(0), "Lending protocol zero address for setter");
        lendingProtocol = ILendingProtocol(_lendingProtocolAddress);
    }
}
