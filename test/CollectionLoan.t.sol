// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol"; // ProtocolSetup inherits Test
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol"; // For instantiating unlistedCollection

contract CollectionLoanTest is ProtocolSetup {

    function test_CollectionOffer_LenderMakes_BorrowersAccept() public {
        // Alice (lender) makes a collection offer
        uint256 principalPerLoan = 1 ether;
        uint256 apr = 500; // 5%
        uint256 duration = 30 days;
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 originationFee = 100; // 1%
        uint256 totalOfferCapacity = 5 ether;
        uint256 maxLoanAmount = 1 ether; // Max principal per loan, should be >= principalPerLoan

        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), totalOfferCapacity);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(nftCollection),
            nftTokenId: 0, // Not used for collection offer targeting
            currency: address(weth),
            principalAmount: principalPerLoan,
            interestRateAPR: apr,
            durationSeconds: duration,
            expirationTimestamp: expiration,
            originationFeeRate: originationFee,
            totalCapacity: totalOfferCapacity,
            maxPrincipalPerLoan: maxLoanAmount,
            minNumberOfLoans: 1
        });

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(
            0, // offerId is dynamic, will be checked later
            alice,
            offerParams.offerType,
            offerParams.nftContract,
            offerParams.nftTokenId,
            offerParams.currency,
            offerParams.principalAmount,
            offerParams.interestRateAPR,
            offerParams.durationSeconds,
            offerParams.expirationTimestamp,
            offerParams.originationFeeRate,
            offerParams.totalCapacity,
            offerParams.maxPrincipalPerLoan,
            offerParams.minNumberOfLoans
        );
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.lender, alice, "Offer lender mismatch");
        assertEq(uint256(offer.offerType), uint256(ILendingProtocol.OfferType.COLLECTION), "Offer type mismatch");
        assertEq(offer.nftContract, address(nftCollection), "Offer NFT contract mismatch");
        assertEq(offer.currency, address(weth), "Offer currency mismatch");
        assertEq(offer.principalAmount, principalPerLoan, "Offer principal amount mismatch");
        assertEq(offer.totalCapacity, totalOfferCapacity, "Offer total capacity mismatch");
        assertEq(offer.maxPrincipalPerLoan, maxLoanAmount, "Offer max principal per loan mismatch");
        assertTrue(offer.isActive, "Offer should be active");
        vm.stopPrank();

        // Borrower 1 (Bob) accepts the offer
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1); // Bob's NFT ID 1

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(
            offerId,
            0, // loanId is dynamic
            bob,
            alice,
            address(nftCollection),
            1, // Bob's NFT ID
            address(weth),
            principalPerLoan,
            block.timestamp, // Approximate, will vary slightly
            offer.durationSeconds,
            offer.interestRateAPR,
            offer.originationFeeRate
        );
        bytes32 loanId1 = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        assertTrue(loanId1 != 0, "Loan ID 1 should not be zero");

        ILendingProtocol.Loan memory loan1 = lendingProtocol.getLoan(loanId1);
        assertEq(loan1.borrower, bob, "Loan 1 borrower mismatch");
        assertEq(loan1.lender, alice, "Loan 1 lender mismatch");
        assertEq(loan1.nftContract, address(nftCollection), "Loan 1 NFT contract mismatch");
        assertEq(loan1.nftTokenId, 1, "Loan 1 NFT ID mismatch");
        assertEq(loan1.currency, address(weth), "Loan 1 currency mismatch");
        assertEq(loan1.principalAmount, principalPerLoan, "Loan 1 principal amount mismatch");
        assertEq(uint256(loan1.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Loan 1 status should be ACTIVE");

        assertEq(nftCollection.ownerOf(1), address(lendingProtocol), "NFT 1 should be held by protocol");
        uint256 expectedBobWeth = bobInitialWethBalance + principalPerLoan - (principalPerLoan * originationFee / 10000);
        assertEq(weth.balanceOf(bob), expectedBobWeth, "Bob WETH balance incorrect after loan 1");
        assertEq(weth.balanceOf(alice), aliceInitialWethBalance - principalPerLoan, "Alice WETH balance incorrect after loan 1");
        vm.stopPrank();

        // Borrower 2 (Charlie) accepts the same offer with a different NFT
        uint256 charlieInitialWethBalance = weth.balanceOf(charlie);
        uint256 aliceBalanceBeforeLoan2 = weth.balanceOf(alice);

        vm.startPrank(charlie);
        nftCollection.approve(address(lendingProtocol), 3); // Charlie's NFT ID 3

        vm.expectEmit(true, true, true, true);
         emit ILendingProtocol.OfferAccepted(
            offerId,
            0, // loanId is dynamic
            charlie,
            alice,
            address(nftCollection),
            3, // Charlie's NFT ID
            address(weth),
            principalPerLoan,
            block.timestamp, // Approximate
            offer.durationSeconds,
            offer.interestRateAPR,
            offer.originationFeeRate
        );
        bytes32 loanId2 = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 3);
        assertTrue(loanId2 != 0, "Loan ID 2 should not be zero");
        assertTrue(loanId2 != loanId1, "Loan ID 2 should be different from Loan ID 1");

        ILendingProtocol.Loan memory loan2 = lendingProtocol.getLoan(loanId2);
        assertEq(loan2.borrower, charlie, "Loan 2 borrower mismatch");
        assertEq(loan2.lender, alice, "Loan 2 lender mismatch");
        assertEq(loan2.nftContract, address(nftCollection), "Loan 2 NFT contract mismatch");
        assertEq(loan2.nftTokenId, 3, "Loan 2 NFT ID mismatch");
        assertEq(loan2.principalAmount, principalPerLoan, "Loan 2 principal amount mismatch");
        assertEq(uint256(loan2.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Loan 2 status should be ACTIVE");

        assertEq(nftCollection.ownerOf(3), address(lendingProtocol), "NFT 3 should be held by protocol");
        uint256 expectedCharlieWeth = charlieInitialWethBalance + principalPerLoan - (principalPerLoan * originationFee / 10000);
        assertEq(weth.balanceOf(charlie), expectedCharlieWeth, "Charlie WETH balance incorrect after loan 2");
        assertEq(weth.balanceOf(alice), aliceBalanceBeforeLoan2 - principalPerLoan, "Alice WETH balance incorrect after loan 2");
        vm.stopPrank();

        // Check offer status after multiple loans
        offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.amountDrawn, principalPerLoan * 2, "Offer amount drawn incorrect");
        assertTrue(offer.isActive, "Offer should still be active if capacity not reached");
    }

    function test_CollectionOffer_Revert_LenderInsufficientBalanceForNextLoan() public {
        uint256 principalPerLoan = 1 ether;
        uint256 totalCapacityForOffer = 2 ether; // Alice will fund for 2 loans
        uint256 aliceActualFunding = 1.5 ether; // Alice only has 1.5 WETH

        deal(address(weth), alice, aliceActualFunding);
        assertEq(weth.balanceOf(alice), aliceActualFunding, "Alice initial WETH incorrect");

        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), totalCapacityForOffer);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(nftCollection),
            nftTokenId: 0,
            currency: address(weth),
            principalAmount: principalPerLoan,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 100, // 1%
            totalCapacity: totalCapacityForOffer,
            maxPrincipalPerLoan: principalPerLoan,
            minNumberOfLoans: 0
        });

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(0, alice, offerParams.offerType, offerParams.nftContract, 0, address(weth), principalPerLoan, 500, 30 days, uint64(block.timestamp + 1 days), 100, totalCapacityForOffer, principalPerLoan, 0);
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID should not be zero");
        vm.stopPrank();

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);

        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(offerId, 0, bob, alice, address(nftCollection), 1, address(weth), principalPerLoan, block.timestamp, 30 days, 500, 100);
        bytes32 loanId1 = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        assertTrue(loanId1 != 0, "Loan ID 1 should not be zero");

        assertEq(weth.balanceOf(alice), aliceInitialWeth - principalPerLoan, "Alice WETH balance incorrect after Bob's loan");
        uint256 expectedBobWeth = bobInitialWeth + principalPerLoan - (principalPerLoan * offerParams.originationFeeRate / 10000);
        assertEq(weth.balanceOf(bob), expectedBobWeth, "Bob WETH balance incorrect after loan");
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), 0.5 ether, "Alice should have 0.5 WETH remaining");

        vm.startPrank(charlie);
        nftCollection.approve(address(lendingProtocol), 3);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 3);
        vm.stopPrank();

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.amountDrawn, principalPerLoan, "Offer amountDrawn should only be for Bob's loan");
        assertTrue(offer.isActive, "Offer should still be active as total capacity not met, even if lender can't fund");
    }

    function test_CollectionOffer_OfferCreation_PrincipalCanBeGreaterThanMaxPrincipalPerLoan() public {
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 2 ether);

        uint256 offerPrincipal = 1 ether;
        uint256 offerMaxPrincipalPerLoan = 0.5 ether;
        uint256 offerTotalCapacity = 2 ether;

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(nftCollection),
            nftTokenId: 0,
            currency: address(weth),
            principalAmount: offerPrincipal,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 100,
            totalCapacity: offerTotalCapacity,
            maxPrincipalPerLoan: offerMaxPrincipalPerLoan,
            minNumberOfLoans: 0
        });

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(
            0,
            alice,
            offerParams.offerType,
            offerParams.nftContract,
            offerParams.nftTokenId,
            offerParams.currency,
            offerParams.principalAmount,
            offerParams.interestRateAPR,
            offerParams.durationSeconds,
            offerParams.expirationTimestamp,
            offerParams.originationFeeRate,
            offerParams.totalCapacity,
            offerParams.maxPrincipalPerLoan,
            offerParams.minNumberOfLoans
        );
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory createdOffer = lendingProtocol.getLoanOffer(offerId);
        assertEq(createdOffer.principalAmount, offerPrincipal, "Offer principalAmount incorrect in storage");
        assertEq(createdOffer.maxPrincipalPerLoan, offerMaxPrincipalPerLoan, "Offer maxPrincipalPerLoan incorrect in storage");
        vm.stopPrank();

        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(
            offerId,
            0,
            bob,
            alice,
            address(nftCollection),
            1,
            address(weth),
            offerPrincipal,
            block.timestamp,
            createdOffer.durationSeconds,
            createdOffer.interestRateAPR,
            createdOffer.originationFeeRate
        );
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        assertTrue(loanId != 0, "Loan ID should not be zero");

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.principalAmount, offerPrincipal, "Loan principalAmount should be offer.principalAmount, not capped by maxPrincipalPerLoan");

        uint256 expectedBobWeth = bobInitialWeth + offerPrincipal - (offerPrincipal * createdOffer.originationFeeRate / 10000);
        assertEq(weth.balanceOf(bob), expectedBobWeth, "Bob WETH balance incorrect");
        assertEq(weth.balanceOf(alice), aliceInitialWeth - offerPrincipal, "Alice WETH balance incorrect");
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol), "NFT should be held by protocol");
        vm.stopPrank();
    }

    function test_MakeLoanOffer_Revert_CollectionNotWhitelisted_CollectionOffer() public {
        ERC721Mock unlistedCollection = new ERC721Mock("Unlisted NFT", "UNFT");
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 5 ether);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(unlistedCollection),
            nftTokenId: 0,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 100,
            totalCapacity: 5 ether,
            maxPrincipalPerLoan: 1 ether,
            minNumberOfLoans: 1
        });
        vm.expectRevert("Collection not whitelisted");
        lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();
    }
}
