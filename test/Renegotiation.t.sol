// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol"; // ProtocolSetup inherits Test
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";

contract RenegotiationTest is ProtocolSetup {

    // Helper function to create a loan specifically for renegotiation tests
    function _createInitialLoanForRenegotiation() internal returns (bytes32 loanId) {
        // This logic is a copy of _createInitialLoanForRefinance
        // Alice (lender) makes an offer for NFT ID 1 (owned by Bob)
        uint256 principal = 1 ether;
        uint256 apr = 500; // 5%
        uint256 duration = 30 days;
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 originationFee = 100; // 1%

        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), principal + (principal * originationFee / 10000));

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 1, // Bob's NFT
            currency: address(weth),
            principalAmount: principal,
            interestRateAPR: apr,
            durationSeconds: duration,
            expirationTimestamp: expiration,
            originationFeeRate: originationFee,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // Bob (borrower) accepts the offer
        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();

        // Basic validation of the created loan
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.lender, alice, "Initial loan lender for renegotiation should be Alice");
        assertEq(loan.borrower, bob, "Initial loan borrower for renegotiation should be Bob");
    }

    function test_Renegotiation_Successful_LenderProposes_BorrowerAccepts_IncreasedPrincipal() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);
        uint256 originalLoanStartTime = oldLoan.startTime;

        vm.warp(block.timestamp + 7 days);

        uint256 proposedPrincipalAmount = 1.2 ether;
        uint256 proposedInterestRateAPR = 550;
        uint256 proposedDurationSeconds = 45 days;

        uint256 additionalPrincipal = proposedPrincipalAmount - oldLoan.principalAmount;
        if (weth.balanceOf(alice) < additionalPrincipal) {
             deal(address(weth), alice, weth.balanceOf(alice) + additionalPrincipal);
        }
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), additionalPrincipal);

        bytes32 proposalId = lendingProtocol.proposeRenegotiation(
            loanId,
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds
        );
        assertTrue(proposalId != 0, "Proposal ID should not be zero");
        vm.stopPrank();

        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRenegotiated(
            proposalId,
            loanId,
            bob,
            alice,
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds,
            originalLoanStartTime + proposedDurationSeconds,
            0
        );
        lendingProtocol.acceptRenegotiation(proposalId);

        ILendingProtocol.Loan memory renegotiatedLoan = lendingProtocol.getLoan(loanId);
        assertEq(renegotiatedLoan.principalAmount, proposedPrincipalAmount, "Principal mismatch after renegotiation");
        assertEq(renegotiatedLoan.interestRateAPR, proposedInterestRateAPR, "APR mismatch after renegotiation");
        assertEq(renegotiatedLoan.startTime, originalLoanStartTime, "Start time should not change");
        assertEq(renegotiatedLoan.dueTime, originalLoanStartTime + proposedDurationSeconds, "Due time mismatch after renegotiation");
        assertEq(renegotiatedLoan.accruedInterest, 0, "Accrued Interest should be reset");
        assertEq(uint256(renegotiatedLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Status not ACTIVE after renegotiation");

        assertEq(weth.balanceOf(bob), bobInitialWeth + additionalPrincipal, "Bob WETH balance incorrect after increased principal");
        assertEq(weth.balanceOf(alice), aliceInitialWeth - additionalPrincipal, "Alice WETH balance incorrect after increased principal");
        vm.stopPrank();
    }

    function test_Renegotiation_Successful_LenderProposes_BorrowerAccepts_DecreasedPrincipal() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);
        uint256 originalLoanStartTime = oldLoan.startTime;

        vm.warp(block.timestamp + 3 days);

        uint256 proposedPrincipalAmount = 0.8 ether;
        uint256 proposedInterestRateAPR = 450;
        uint256 proposedDurationSeconds = 25 days;

        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(
            loanId,
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds
        );
        assertTrue(proposalId != 0, "Proposal ID should not be zero for decreased principal");
        vm.stopPrank();

        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);
        uint256 principalReduction = oldLoan.principalAmount - proposedPrincipalAmount;

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), principalReduction);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRenegotiated(
            proposalId,
            loanId,
            bob,
            alice,
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds,
            originalLoanStartTime + proposedDurationSeconds,
            0
        );
        lendingProtocol.acceptRenegotiation(proposalId);

        ILendingProtocol.Loan memory renegotiatedLoan = lendingProtocol.getLoan(loanId);
        assertEq(renegotiatedLoan.principalAmount, proposedPrincipalAmount, "Principal mismatch (decreased)");
        assertEq(renegotiatedLoan.interestRateAPR, proposedInterestRateAPR, "APR mismatch (decreased)");
        assertEq(renegotiatedLoan.startTime, originalLoanStartTime, "Start time should not change (decreased)");
        assertEq(renegotiatedLoan.dueTime, originalLoanStartTime + proposedDurationSeconds, "Due time mismatch (decreased)");
        assertEq(renegotiatedLoan.accruedInterest, 0, "Accrued Interest reset (decreased)");
        assertEq(uint256(renegotiatedLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Status not ACTIVE (decreased)");

        assertEq(weth.balanceOf(bob), bobInitialWeth - principalReduction, "Bob WETH balance incorrect (decreased principal)");
        assertEq(weth.balanceOf(alice), aliceInitialWeth + principalReduction, "Alice WETH balance incorrect (decreased principal)");
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_NotLenderProposes() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        vm.startPrank(charlie);
        vm.expectRevert("Not lender");
        lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_NotBorrowerAccepts() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();

        vm.startPrank(charlie);
        vm.expectRevert("Not borrower");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_ProposalNotFound() public {
        _createInitialLoanForRenegotiation();
        vm.startPrank(bob);
        bytes32 fakeProposalId = keccak256(abi.encodePacked("fake_id"));
        vm.expectRevert("Proposal not found or not for this loan");
        lendingProtocol.acceptRenegotiation(fakeProposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_LoanNotActiveForPropose() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        vm.startPrank(bob);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        weth.approve(address(lendingProtocol), loan.principalAmount + interest);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Loan not active");
        lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_LoanNotActiveForAccept() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 550, 40 days);
        vm.stopPrank();

        vm.startPrank(bob);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        weth.approve(address(lendingProtocol), loan.principalAmount + interest);

        deal(address(weth), alice, weth.balanceOf(alice) + 0.1 ether);
        vm.prank(alice);
        weth.approve(address(lendingProtocol), 0.1 ether);

        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("Loan not active");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_ProposalAlreadyActioned() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 0.9 ether, 450, 20 days);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), 0.1 ether);
        lendingProtocol.acceptRenegotiation(proposalId);

        vm.expectRevert("Proposal already actioned");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }
}
