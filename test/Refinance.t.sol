// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol"; // ProtocolSetup inherits Test
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";

contract RefinanceTest is ProtocolSetup {

    // Helper function moved from ProtocolTest
    function _createInitialLoanForRefinance() internal returns (bytes32 loanId) {
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
            nftTokenId: 1,
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

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.lender, alice, "Initial loan lender should be Alice");
        assertEq(loan.borrower, bob, "Initial loan borrower should be Bob");
        assertEq(loan.principalAmount, principal, "Initial loan principal mismatch");
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol), "NFT not held by protocol after initial loan");
    }

    function test_Refinance_Successful() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);

        // Warp time to accrue interest
        uint256 timeToWarp = 10 days;
        vm.warp(block.timestamp + timeToWarp);

        // Refinance Setup
        uint256 newPrincipalAmount = 1.1 ether; // Top-up
        uint256 newInterestRateAPR = 400; // 4%
        uint256 newDurationSeconds = 60 days;
        uint256 newOriginationFeeRate = 50; // 0.5%

        uint256 aliceInitialWeth = weth.balanceOf(alice);
        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 charlieInitialWeth = weth.balanceOf(charlie);

        vm.startPrank(charlie);
        uint256 interestForOldLender = lendingProtocol.calculateInterest(loanId);
        uint256 paymentToOldLender = oldLoan.principalAmount + interestForOldLender;
        uint256 diffToBorrower = newPrincipalAmount - oldLoan.principalAmount;
        uint256 newLenderOriginationFee = (newPrincipalAmount * newOriginationFeeRate) / 10000;

        uint256 totalCharlieApproval = paymentToOldLender + diffToBorrower; // Fee is self-paid
        weth.approve(address(lendingProtocol), totalCharlieApproval);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRefinanced(
            loanId, // oldLoanId
            loanId, // newLoanId (current behavior reuses ID)
            bob,    // borrower
            charlie,// newLender
            alice,  // oldLender
            newPrincipalAmount,
            newInterestRateAPR,
            newDurationSeconds,
            block.timestamp + newDurationSeconds, // newDueTime (approx)
            newLenderOriginationFee
        );

        bytes32 newLoanId = lendingProtocol.refinanceLoan(
            loanId,
            newPrincipalAmount,
            newInterestRateAPR,
            newDurationSeconds,
            newOriginationFeeRate
        );
        assertEq(newLoanId, loanId, "Refinance should reuse loanId");

        // Verify Post-Refinance State
        ILendingProtocol.Loan memory refinancedLoan = lendingProtocol.getLoan(loanId);
        assertEq(refinancedLoan.lender, charlie, "Refinanced lender mismatch");
        assertEq(refinancedLoan.borrower, bob, "Refinanced borrower mismatch");
        assertEq(refinancedLoan.principalAmount, newPrincipalAmount, "Refinanced principal mismatch");
        assertEq(refinancedLoan.interestRateAPR, newInterestRateAPR, "Refinanced APR mismatch");
        assertTrue(refinancedLoan.dueTime >= block.timestamp + newDurationSeconds - 1 && refinancedLoan.dueTime <= block.timestamp + newDurationSeconds + 1, "Refinanced due time incorrect");
        assertEq(refinancedLoan.originationFeePaid, newLenderOriginationFee, "Refinanced origination fee mismatch");
        assertEq(uint256(refinancedLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Refinanced loan status not ACTIVE");
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol), "NFT not held by protocol after refinance");

        // Verify Balances
        assertEq(weth.balanceOf(alice), aliceInitialWeth + paymentToOldLender, "Alice (old lender) balance incorrect");
        assertEq(weth.balanceOf(bob), bobInitialWeth + diffToBorrower, "Bob (borrower) balance incorrect after top-up");
        assertEq(weth.balanceOf(charlie), charlieInitialWeth - (paymentToOldLender + diffToBorrower), "Charlie (new lender) balance incorrect");
        vm.stopPrank();
    }

    function test_Refinance_Revert_PrincipalReduction() public {
        bytes32 loanId = _createInitialLoanForRefinance();

        vm.startPrank(charlie);
        uint256 newPrincipalAmountReduced = 0.9 ether;

        weth.approve(address(lendingProtocol), 2 ether);

        vm.expectRevert("Principal reduction not allowed in refinance");
        lendingProtocol.refinanceLoan(
            loanId,
            newPrincipalAmountReduced,
            400,
            60 days,
            50
        );
        vm.stopPrank();
    }

    function test_Refinance_Revert_OriginalLoanNotActive() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory loanDetails = lendingProtocol.getLoan(loanId);

        vm.warp(block.timestamp + 15 days);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loanDetails.principalAmount + interest;

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loanDetails = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loanDetails.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");

        vm.startPrank(charlie);
        weth.approve(address(lendingProtocol), 2 ether);

        vm.expectRevert("Original loan not active");
        lendingProtocol.refinanceLoan(
            loanId,
            1 ether,
            400,
            60 days,
            50
        );
        vm.stopPrank();
    }

    function test_Refinance_Successful_NewPrincipalSameAsOld() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);

        vm.warp(block.timestamp + 5 days);

        uint256 newPrincipalAmount = oldLoan.principalAmount;
        uint256 newInterestRateAPR = 300;
        uint256 newDurationSeconds = 20 days;
        uint256 newOriginationFeeRate = 0;

        uint256 aliceInitialWeth = weth.balanceOf(alice);
        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 charlieInitialWeth = weth.balanceOf(charlie);

        vm.startPrank(charlie);
        uint256 interestForOldLender = lendingProtocol.calculateInterest(loanId);
        uint256 paymentToOldLender = oldLoan.principalAmount + interestForOldLender;
        uint256 newLenderOriginationFee = 0;

        uint256 totalCharlieApproval = paymentToOldLender;
        weth.approve(address(lendingProtocol), totalCharlieApproval);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRefinanced(
            loanId,
            loanId,
            bob,
            charlie,
            alice,
            newPrincipalAmount,
            newInterestRateAPR,
            newDurationSeconds,
            block.timestamp + newDurationSeconds,
            newLenderOriginationFee
        );

        bytes32 newLoanId = lendingProtocol.refinanceLoan(
            loanId,
            newPrincipalAmount,
            newInterestRateAPR,
            newDurationSeconds,
            newOriginationFeeRate
        );
        assertEq(newLoanId, loanId, "Refinance should reuse loanId");

        ILendingProtocol.Loan memory refinancedLoan = lendingProtocol.getLoan(loanId);
        assertEq(refinancedLoan.lender, charlie, "Refinanced lender (same principal) mismatch");
        assertEq(refinancedLoan.principalAmount, newPrincipalAmount, "Refinanced principal (same principal) mismatch");
        assertEq(refinancedLoan.interestRateAPR, newInterestRateAPR, "Refinanced APR (same principal) mismatch");
        assertTrue(refinancedLoan.dueTime >= block.timestamp + newDurationSeconds -1 && refinancedLoan.dueTime <= block.timestamp + newDurationSeconds + 1, "Due time incorrect (same principal)");
        assertEq(uint256(refinancedLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Loan status not ACTIVE (same principal)");

        assertEq(weth.balanceOf(alice), aliceInitialWeth + paymentToOldLender, "Alice balance incorrect (same principal)");
        assertTrue(weth.balanceOf(bob) >= bobInitialWeth - 0.01 ether && weth.balanceOf(bob) <= bobInitialWeth + 0.01 ether, "Bob balance changed unexpectedly (same principal)");
        assertEq(weth.balanceOf(charlie), charlieInitialWeth - paymentToOldLender, "Charlie balance incorrect (same principal)");
        vm.stopPrank();
    }
}
