// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13; // Matching pragma from original Protocol.t.sol (0.8.30 actually)
// Let's use 0.8.30 to be consistent with Protocol.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol"; // ProtocolSetup inherits Test
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
// import {ERC20Mock} from "../src/mocks/ERC20Mock.sol"; // Not strictly needed if not instantiating new ones
// import {ERC721Mock} from "../src/mocks/ERC721Mock.sol"; // Not strictly needed if not instantiating new ones

contract StandardLoanTest is ProtocolSetup {

    function test_LenderMakesOffer_BorrowerAccepts_RepaysLoan() public {
        // Alice (lender) makes an offer
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
            totalCapacity: 0, // Not used for standard offer
            maxPrincipalPerLoan: 0, // Not used for standard offer
            minNumberOfLoans: 0 // Not used for standard offer
        });

        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertTrue(offer.isActive);
        assertEq(offer.lender, alice);

        // Bob (borrower) accepts the offer
        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.borrower, bob);
        assertEq(loan.lender, alice);
        assertEq(loan.principalAmount, principal);
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol));

        uint bobBalanceBeforeLoan = WETH_STARTING_BALANCE; // Constant from ProtocolSetup
        uint expectedBalanceAfterReceivingPrincipal = bobBalanceBeforeLoan + principal - (principal * originationFee / 10000);

        assertTrue(
            weth.balanceOf(bob) >= expectedBalanceAfterReceivingPrincipal - 1000 wei && // Loosen for gas
            weth.balanceOf(bob) <= expectedBalanceAfterReceivingPrincipal
        );

        // Fast forward time (but not past due date)
        vm.warp(block.timestamp + 15 days);

        // Bob repays the loan
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = principal + interest;

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");
        assertEq(nftCollection.ownerOf(1), bob);
        assertTrue(weth.balanceOf(alice) > WETH_STARTING_BALANCE);
    }

    function test_Fail_AcceptExpiredOffer() public {
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 1 ether);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 1,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 hours),
            originationFeeRate: 0,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours); // Expire the offer

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        vm.expectRevert("Offer expired");
        lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();
    }

    function test_AccessControl_CancelLoanOffer_Revert_NotOfferOwner() public {
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 1 ether);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection), nftTokenId: 1, currency: address(weth),
            principalAmount: 1 ether, interestRateAPR: 500, durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        vm.startPrank(bob); // Bob is not the offer owner
        vm.expectRevert("Not offer owner");
        lendingProtocol.cancelLoanOffer(offerId);
        vm.stopPrank();
    }

    // Note: The following two tests might need ERC20Mock/ERC721Mock if ProtocolSetup doesn't expose them
    // or if these tests create *new* mock instances.
    // For now, assuming ProtocolSetup provides `weth`, `nftCollection` that are sufficient.
    // If `new ERC20Mock` or `new ERC721Mock` is needed, those imports must be uncommented.
    // And `CurrencyManager` if `new CurrencyManager` is used.
    // The current ProtocolTest imports these, so StandardLoanTest might also need them if it creates new instances.
    // Let's add them to be safe, as ProtocolTest had them for a reason.
    // import {CurrencyManager} from "../src/core/CurrencyManager.sol"; // Added if needed
    // import {ERC20Mock} from "../src/mocks/ERC20Mock.sol"; // Added if needed
    // import {ERC721Mock} from "../src/mocks/ERC721Mock.sol"; // Added if needed

    function test_MakeLoanOffer_Revert_UnsupportedCurrency() public {
        // This test creates a new ERC20Mock instance, so the import is needed.
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UST");
        vm.startPrank(alice);
        deal(address(unsupportedToken), alice, 1 ether);
        unsupportedToken.approve(address(lendingProtocol), 1 ether);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection), nftTokenId: 1, currency: address(unsupportedToken),
            principalAmount: 1 ether, interestRateAPR: 500, durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        vm.expectRevert("Currency not supported");
        lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();
    }

    function test_MakeLoanOffer_Revert_CollectionNotWhitelisted_StandardOffer() public {
        // This test creates a new ERC721Mock instance.
        ERC721Mock unlistedCollection = new ERC721Mock("Unlisted NFT", "UNFT");
        unlistedCollection.mint(bob, 1);
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 1 ether);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(unlistedCollection), nftTokenId: 1, currency: address(weth),
            principalAmount: 1 ether, interestRateAPR: 500, durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        vm.expectRevert("Collection not whitelisted");
        lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();
    }
}
