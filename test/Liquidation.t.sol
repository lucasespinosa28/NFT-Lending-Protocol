// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {ILiquidation} from "../src/interfaces/ILiquidation.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";
// Minimal LendingProtocol interface for onERC721Received if needed,
// but Liquidation contract doesn't seem to require it for these tests.

contract LiquidationTest is Test {
    Liquidation liquidationContract;
    ERC20Mock weth;
    ERC721Mock nftCollection;

    address owner = vm.addr(1); // Owner of Liquidation contract
    address lendingProtocolMock = vm.addr(2); // Mock address for LendingProtocol
    address bidder1 = vm.addr(3);
    address bidder2 = vm.addr(4);
    address originalLender = vm.addr(5); // For distributing proceeds
    address nftHolder = vm.addr(6); // Entity holding the NFT, e.g., LendingProtocol itself

    bytes32 testLoanId = keccak256(abi.encodePacked("testLoanId123"));
    uint256 nftIdToAuction = 1;
    uint256 auctionCounter = 0; // To help predict auctionId

    function setUp() public {
        vm.startPrank(owner);
        liquidationContract = new Liquidation(address(0)); // Deploy with owner as initial setter
        liquidationContract.setLendingProtocol(lendingProtocolMock);
        vm.stopPrank();

        weth = new ERC20Mock("Wrapped Ether", "WETH");
        nftCollection = new ERC721Mock("Test NFT", "TNFT");

        // Mint NFT to an entity that would represent where the NFT is before auction settlement.
        // Liquidation contract itself does not take custody of the NFT at auction start.
        // LendingProtocol (nftHolder here) would transfer it upon successful auction settlement.
        nftCollection.mint(nftHolder, nftIdToAuction);

        // Fund bidders
        weth.mint(bidder1, 100 ether);
        weth.mint(bidder2, 100 ether);

        // Approve Liquidation contract by bidders
        vm.startPrank(bidder1);
        weth.approve(address(liquidationContract), 50 ether);
        vm.stopPrank();

        vm.startPrank(bidder2);
        weth.approve(address(liquidationContract), 50 ether);
        vm.stopPrank();

        auctionCounter = 0; // Reset counter for predictable auction IDs per test
    }

    // Helper to start an auction
    function _startAuction(uint256 startingBid, uint64 duration) internal returns (bytes32 auctionId) {
        vm.startPrank(lendingProtocolMock); // Only LendingProtocol can start auctions
        address[] memory lenders = new address[](1);
        lenders[0] = originalLender;
        uint256[] memory lenderShares = new uint256[](1);
        lenderShares[0] = 10000; // 100.00% share (assuming basis points)

        auctionCounter++; // Increment for unique auction ID prediction
        bytes32 expectedAuctionId = keccak256(abi.encodePacked(address(liquidationContract), auctionCounter));


        vm.expectEmit(true, true, true, true);
        emit ILiquidation.AuctionStarted(
            expectedAuctionId,
            testLoanId,
            address(nftCollection),
            nftIdToAuction,
            startingBid,
            uint64(block.timestamp + duration)
        );
        auctionId = liquidationContract.startAuction(
            testLoanId,
            address(nftCollection),
            nftIdToAuction,
            false, // isVault
            address(weth), // currency
            startingBid,
            duration,
            lenders,
            lenderShares
        );
        assertEq(auctionId, expectedAuctionId, "Auction ID mismatch");
        vm.stopPrank();
    }

    function test_Auction_Successful_SingleBidder_EndAuction_Distribute() public {
        uint256 startingBid = 1 ether;
        uint64 auctionDuration = 1 days;
        bytes32 auctionId = _startAuction(startingBid, auctionDuration);
        assertTrue(auctionId != 0, "Auction ID is zero");

        // Bidder1 places a bid
        vm.startPrank(bidder1);
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.BidPlaced(auctionId, bidder1, startingBid);
        liquidationContract.placeBid(auctionId, startingBid);
        vm.stopPrank();

        ILiquidation.Auction memory auction = liquidationContract.getAuction(auctionId);
        assertEq(auction.highestBidder, bidder1, "Highest bidder incorrect");
        assertEq(auction.highestBid, startingBid, "Highest bid incorrect");

        // End auction
        vm.warp(block.timestamp + auctionDuration + 1 hours); // Warp time past auction end

        vm.startPrank(lendingProtocolMock); // endAuction can be called by anyone, but let's use LP
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.AuctionEnded(auctionId, bidder1, startingBid);
        liquidationContract.endAuction(auctionId);
        vm.stopPrank();

        auction = liquidationContract.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(ILiquidation.AuctionStatus.ENDED_SOLD), "Auction status should be ENDED_SOLD");

        // Distribute proceeds
        uint256 originalLenderInitialBalance = weth.balanceOf(originalLender);

        vm.startPrank(lendingProtocolMock); // distributeProceeds can be called by anyone
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.ProceedsDistributed(auctionId, startingBid);
        liquidationContract.distributeProceeds(auctionId);
        vm.stopPrank();

        assertEq(weth.balanceOf(originalLender), originalLenderInitialBalance + startingBid, "Original lender proceeds incorrect");
        auction = liquidationContract.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(ILiquidation.AuctionStatus.SETTLED), "Auction status should be SETTLED");
    }

    function test_Auction_MultipleBids_End_Distribute() public {
        uint256 startingBid = 1 ether;
        uint64 auctionDuration = 1 days;
        bytes32 auctionId = _startAuction(startingBid, auctionDuration);

        // Bidder1 places bid
        vm.startPrank(bidder1);
        liquidationContract.placeBid(auctionId, 1 ether); // Bid 1: 1 ETH
        vm.stopPrank();
        uint256 bidder1InitialBalance = weth.balanceOf(bidder1);

        // Bidder2 outbids
        uint256 bidder2Bid = 2 ether;
        vm.startPrank(bidder2);
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.BidPlaced(auctionId, bidder2, bidder2Bid);
        liquidationContract.placeBid(auctionId, bidder2Bid);
        vm.stopPrank();

        assertEq(weth.balanceOf(bidder1), bidder1InitialBalance + 1 ether, "Bidder1 should be refunded previous bid");

        ILiquidation.Auction memory auction = liquidationContract.getAuction(auctionId);
        assertEq(auction.highestBidder, bidder2, "Highest bidder should be bidder2");
        assertEq(auction.highestBid, bidder2Bid, "Highest bid should be 2 ether");

        vm.warp(block.timestamp + auctionDuration + 1 hours);
        vm.startPrank(lendingProtocolMock);
        liquidationContract.endAuction(auctionId);
        vm.stopPrank();

        uint256 originalLenderInitialBalance = weth.balanceOf(originalLender);
        vm.startPrank(lendingProtocolMock);
        liquidationContract.distributeProceeds(auctionId);
        vm.stopPrank();
        assertEq(weth.balanceOf(originalLender), originalLenderInitialBalance + bidder2Bid, "Original lender proceeds from bidder2 bid incorrect");
    }

    function test_Auction_Revert_BidTooLow() public {
        uint256 firstBidAmount = 1 ether;
        bytes32 auctionId = _startAuction(firstBidAmount, 1 days);

        vm.startPrank(bidder1);
        liquidationContract.placeBid(auctionId, firstBidAmount);
        vm.stopPrank();

        vm.startPrank(bidder2);
        vm.expectRevert("Bid amount too low"); // Match exact error string from Liquidation.sol
        liquidationContract.placeBid(auctionId, firstBidAmount - 0.1 ether); // Lower bid
        vm.stopPrank();
    }

    function test_Auction_Revert_AuctionEnded_PlaceBid() public {
        bytes32 auctionId = _startAuction(1 ether, 1 days);
        vm.warp(block.timestamp + 2 days); // End auction by time passing

        vm.startPrank(lendingProtocolMock);
        liquidationContract.endAuction(auctionId); // Explicitly end it
        vm.stopPrank();

        vm.startPrank(bidder1);
        vm.expectRevert("Auction not active"); // Match exact error string
        liquidationContract.placeBid(auctionId, 2 ether);
        vm.stopPrank();
    }

    function test_Auction_EndedNoBids_ClaimCollateralPostAuction() public {
        uint256 startingBid = 1 ether;
        uint64 auctionDuration = 1 days;
        bytes32 auctionId = _startAuction(startingBid, auctionDuration);

        vm.warp(block.timestamp + auctionDuration + 1 hours);
        vm.startPrank(lendingProtocolMock);
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.AuctionEnded(auctionId, address(0), 0);
        liquidationContract.endAuction(auctionId);
        vm.stopPrank();

        ILiquidation.Auction memory auction = liquidationContract.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(ILiquidation.AuctionStatus.ENDED_NO_BIDS), "Auction status should be ENDED_NO_BIDS");

        vm.startPrank(originalLender); // Can be called by anyone as per current contract
        vm.expectEmit(true, true, true, true);
        emit ILiquidation.CollateralClaimedPostAuction(auctionId, originalLender);
        liquidationContract.claimCollateralPostAuction(auctionId);
        vm.stopPrank();

        auction = liquidationContract.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(ILiquidation.AuctionStatus.SETTLED), "Auction status should be SETTLED after no-bid claim");
    }

    function test_Auction_Revert_EndAuctionTwice() public {
        bytes32 auctionId = _startAuction(1 ether, 1 days);
        vm.warp(block.timestamp + 2 days);

        vm.startPrank(lendingProtocolMock);
        liquidationContract.endAuction(auctionId); // First end
        vm.expectRevert("Auction not active"); // Status is ENDED_NO_BIDS or ENDED_SOLD
        liquidationContract.endAuction(auctionId); // Second end
        vm.stopPrank();
    }

    function test_Auction_Revert_DistributeProceeds_NotSold() public {
        bytes32 auctionId = _startAuction(1 ether, 1 days);
        vm.warp(block.timestamp + 2 days);
        vm.startPrank(lendingProtocolMock);
        liquidationContract.endAuction(auctionId); // Ends with NO_BIDS
        vm.stopPrank();

        ILiquidation.Auction memory auction = liquidationContract.getAuction(auctionId);
        assertEq(uint8(auction.status), uint8(ILiquidation.AuctionStatus.ENDED_NO_BIDS));

        vm.startPrank(lendingProtocolMock);
        vm.expectRevert("Auction not sold or already distributed");
        liquidationContract.distributeProceeds(auctionId);
        vm.stopPrank();
    }

    function test_Auction_Revert_DistributeProceeds_Twice() public {
        bytes32 auctionId = _startAuction(1 ether, 1 days);

        vm.startPrank(bidder1);
        liquidationContract.placeBid(auctionId, 1 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        vm.startPrank(lendingProtocolMock);
        liquidationContract.endAuction(auctionId); // Ends SOLD
        liquidationContract.distributeProceeds(auctionId); // First distribution

        vm.expectRevert("Auction not sold or already distributed"); // Status is SETTLED now
        liquidationContract.distributeProceeds(auctionId); // Second distribution
        vm.stopPrank();
    }
}
