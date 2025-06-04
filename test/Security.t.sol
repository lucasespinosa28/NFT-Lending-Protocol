// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProtocolSetup, ReentrantBorrowerRepay} from "./Setup.t.sol"; // ReentrantBorrowerRepay is needed for the test
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol"; // For instantiating new Cm
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol"; // For casting weth in reentrancy test

contract SecurityTest is ProtocolSetup {

    function test_Reentrancy_RepayLoan() public {
        // ReentrantBorrowerRepay is imported from Setup.t.sol
        ReentrantBorrowerRepay reentrantBorrower = new ReentrantBorrowerRepay(lendingProtocol, weth, nftCollection, address(this));

        // Mint NFT to the reentrant borrower contract directly
        nftCollection.mint(address(reentrantBorrower), 99);
        reentrantBorrower.setNftId(99); // Uses the renamed setter in ReentrantBorrowerRepay from Setup.t.sol

        // Alice makes an offer for the reentrant borrower's NFT
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 1 ether);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 99, // NFT held by ReentrantBorrowerRepay
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // ReentrantBorrower accepts the loan (as itself, the borrower)
        deal(address(weth), address(reentrantBorrower), 2 ether); // Use deal for funding
        vm.startPrank(address(reentrantBorrower));
        reentrantBorrower.approveNftToLP(address(lendingProtocol));
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 99);
        reentrantBorrower.setLoanId(loanId);
        vm.stopPrank();

        uint256 interest = lendingProtocol.calculateInterest(loanId);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;

        vm.startPrank(address(reentrantBorrower)); // Borrower initiates repay
        ERC20Mock(payable(address(weth))).approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID));
        assertEq(nftCollection.ownerOf(99), address(reentrantBorrower));
        assertTrue(reentrantBorrower.reentrantCallSucceeded(), "Reentrant call should have been made (and handled)");
    }

    function test_AccessControl_SetCurrencyManager_Revert_NotOwner() public {
        vm.startPrank(alice); // Alice is not the owner
        CurrencyManager newCm = new CurrencyManager(new address[](0));
        vm.expectRevert("Ownable: caller is not the owner");
        lendingProtocol.setCurrencyManager(address(newCm));
        vm.stopPrank();
    }
}
