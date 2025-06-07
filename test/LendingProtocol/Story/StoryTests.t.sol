// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LendingProtocolBaseTest} from "../LendingProtocolBase.t.sol";
import {ILendingProtocol} from "../../../src/interfaces/ILendingProtocol.sol";
// MockIIPAssetRegistry and MockRoyaltyModule are already in LendingProtocolBaseTest

contract StoryTests is LendingProtocolBaseTest {
    function test_AcceptLoanOffer_WithStoryAsset_Success() public {
        // 1. Register the NFT with Story Protocol mock
        vm.startPrank(borrower); // Borrower (or owner) registers their NFT
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address expectedIpId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);
        assertTrue(expectedIpId != address(0), "Mock IP ID should not be zero after registration");

        // 2. Lender makes an offer
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: BORROWER_NFT_ID,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // 3. Borrower accepts the offer
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 4. Verify loan details, including Story Protocol fields
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertTrue(loan.isStoryAsset, "Loan should be marked as Story asset");
        assertEq(loan.storyIpId, expectedIpId, "Loan storyIpId incorrect");
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        // Assuming effective collateral is the base NFT for standard offers after refactor
        assertEq(loan.nftContract, address(mockNft));
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE));
    }

    function test_ClaimAndRepay_StoryAsset_FullRepaymentByRoyalty() public {
        // 1. Register NFT & create loan (similar to test_AcceptLoanOffer_WithStoryAsset_Success)
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(
            ILendingProtocol.OfferParams({
                offerType: ILendingProtocol.OfferType.STANDARD,
                nftContract: address(mockNft),
                nftTokenId: BORROWER_NFT_ID,
                currency: address(weth),
                principalAmount: 1 ether,
                interestRateAPR: 36500, // 1% per day for easy calculation (365 * 100)
                durationSeconds: 1 days,
                expirationTimestamp: uint64(block.timestamp + 1 hours),
                originationFeeRate: 0, // Simpler test without origination fee
                totalCapacity: 0,
                maxPrincipalPerLoan: 0,
                minNumberOfLoans: 0
            })
        );
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // Advance time to the due date for interest accrual
        vm.warp(block.timestamp + 1 days);

        // 2. Setup royalty balance in MockRoyaltyModule
        uint256 expectedInterest = (1 ether * 36500 * 1 days) / (365 days * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;

        // Fund MockRoyaltyModule through the test contract itself (which is an owner of WETH)
        // weth.mint(address(this), totalRepaymentDue); // Already funded in setUp of base
        // weth.approve(address(mockRoyaltyModule), totalRepaymentDue); // Already approved in setUp
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), totalRepaymentDue);

        // 3. Borrower calls claimAndRepay
        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        vm.expectEmit(true, true, true, true, address(lendingProtocol)); // Event from LendingProtocol
        emit ILendingProtocol.LoanRepaid(loanId, borrower, lender, 1 ether, expectedInterest);

        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        // 4. Verify state
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue, "Lender did not receive full repayment");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT not returned to borrower");
        assertEq(
            royaltyManager.getRoyaltyBalance(ipId, address(weth)), 0, "Royalty balance in RoyaltyManager not cleared"
        );
    }

    function test_ClaimAndRepay_StoryAsset_PartialRepaymentByRoyalty() public {
        // 1. Register NFT & create loan
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(
            ILendingProtocol.OfferParams({
                offerType: ILendingProtocol.OfferType.STANDARD,
                nftContract: address(mockNft),
                nftTokenId: BORROWER_NFT_ID,
                currency: address(weth),
                principalAmount: 1 ether,
                interestRateAPR: 36500,
                durationSeconds: 1 days,
                expirationTimestamp: uint64(block.timestamp + 1 hours),
                originationFeeRate: 0,
                totalCapacity: 0,
                maxPrincipalPerLoan: 0,
                minNumberOfLoans: 0
            })
        );
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // Advance time to the due date for interest accrual
        vm.warp(block.timestamp + 1 days);

        // 2. Setup partial royalty balance
        uint256 expectedInterest = (1 ether * 36500 * 1 days) / (365 days * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;
        uint256 royaltyAvailable = 0.5 ether; // Less than total due

        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), royaltyAvailable);

        // Borrower needs to have funds for the remaining amount
        uint256 remainingForBorrower = totalRepaymentDue - royaltyAvailable;
        weth.mint(borrower, remainingForBorrower);
        vm.startPrank(borrower);
        weth.approve(address(lendingProtocol), remainingForBorrower);
        vm.stopPrank();

        // 3. Borrower calls claimAndRepay
        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        uint256 borrowerWethBefore = weth.balanceOf(borrower);

        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        // 4. Verify state
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue, "Lender did not receive full repayment");
        assertEq(weth.balanceOf(borrower), borrowerWethBefore - remainingForBorrower, "Borrower balance incorrect");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT not returned to borrower");
        assertEq(loan.accruedInterest, expectedInterest, "Accrued interest on loan struct incorrect");
    }

    function test_ClaimAndRepay_StoryAsset_NoRoyaltyBalance() public {
        // 1. Register NFT & create loan
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(
            ILendingProtocol.OfferParams({
                offerType: ILendingProtocol.OfferType.STANDARD,
                nftContract: address(mockNft),
                nftTokenId: BORROWER_NFT_ID,
                currency: address(weth),
                principalAmount: 1 ether,
                interestRateAPR: 36500,
                durationSeconds: 1 days,
                expirationTimestamp: uint64(block.timestamp + 1 hours),
                originationFeeRate: 0,
                totalCapacity: 0,
                maxPrincipalPerLoan: 0,
                minNumberOfLoans: 0
            })
        );
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // Advance time to the due date for interest accrual
        vm.warp(block.timestamp + 1 days);

        // 2. Setup NO royalty balance
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), 0);

        uint256 expectedInterest = (1 ether * 36500 * 1 days) / (365 days * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;

        // Borrower needs to have funds for the full amount
        weth.mint(borrower, totalRepaymentDue);
        vm.startPrank(borrower);
        weth.approve(address(lendingProtocol), totalRepaymentDue);
        vm.stopPrank();

        // 3. Borrower calls claimAndRepay
        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        uint256 borrowerWethBefore = weth.balanceOf(borrower);

        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        // 4. Verify state
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue, "Lender did not receive full repayment");
        assertEq(weth.balanceOf(borrower), borrowerWethBefore - totalRepaymentDue, "Borrower balance incorrect");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT not returned to borrower");
    }
}
