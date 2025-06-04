// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";

contract EdgeCasesTest is ProtocolSetup {

    // Helper to create a standard loan for edge case testing
    function _createInitialLoanForEdgeCaseTest() internal returns (bytes32 loanId) {
        // Based on the original _createInitialLoanForRefinance
        uint256 principal = 1 ether;
        uint256 apr = 500; // 5%
        uint256 duration = 30 days; // Default duration from original helper
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

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();
        return loanId;
    }

    function test_RepayLoan_AtExactDueTime() public {
        bytes32 loanId = _createInitialLoanForEdgeCaseTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime);

        vm.startPrank(bob);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID));
    }

    function test_RepayLoan_OneSecondPastDueTime_Revert_Defaulted() public {
        bytes32 loanId = _createInitialLoanForEdgeCaseTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 second);

        vm.startPrank(bob);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);

        vm.expectRevert("Loan past due (defaulted)");
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_ClaimCollateral_AtExactDueTime_Revert_NotDefaultedYet() public {
        bytes32 loanId = _createInitialLoanForEdgeCaseTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime);

        vm.startPrank(alice);
        vm.expectRevert("Loan not yet defaulted");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }

    function test_CalculateInterest_TimeTravel() public {
        bytes32 loanId = _createInitialLoanForEdgeCaseTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        uint256 principal = loan.principalAmount;
        uint256 apr = loan.interestRateAPR;

        uint256 expectedFullInterest = principal * apr * loan.durationSeconds / (10000 * 365 days);

        vm.warp(loan.startTime);
        uint256 interestAtT0 = lendingProtocol.calculateInterest(loanId);
        assertEq(interestAtT0, 0, "Interest at T0 should be 0");

        vm.warp(loan.startTime + 15 days);
        uint256 interestAtT15 = lendingProtocol.calculateInterest(loanId);
        assertTrue(interestAtT15 > 0 && interestAtT15 < expectedFullInterest, "Interest at T15 incorrect");
        assertApproxEqAbs(interestAtT15, expectedFullInterest / 2, 100 wei, "Interest at T15 should be approx half");


        vm.warp(loan.dueTime);
        uint256 interestAtT30 = lendingProtocol.calculateInterest(loanId);
        assertApproxEqAbs(interestAtT30, expectedFullInterest, 100 wei, "Interest at T30 (due time) incorrect");

        vm.warp(loan.dueTime + 15 days);
        uint256 interestAtT45 = lendingProtocol.calculateInterest(loanId);
        assertApproxEqAbs(interestAtT45, expectedFullInterest, 100 wei, "Interest at T45 (past due) should be capped at T30 interest");
    }
}
