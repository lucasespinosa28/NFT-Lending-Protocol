// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LendingProtocolBaseTest} from "../LendingProtocolBase.t.sol";
import {ILendingProtocol} from "../../../src/interfaces/ILendingProtocol.sol";

contract LifecycleTests is LendingProtocolBaseTest {
    bytes32 internal offerId; // To store offerId for multiple tests relating to the same offer
    uint256 internal constant DEFAULT_PRINCIPAL = 1 ether;
    uint256 internal constant DEFAULT_INTEREST_APR = 500; // 5%
    uint256 internal constant DEFAULT_DURATION_SECONDS = 7 days;
    uint256 internal constant DEFAULT_ORIGINATION_FEE_RATE = 100; // 1%

    // Helper to create a standard offer
    function _makeStandardOfferParams(
        address nftAddr,
        uint256 tokenId,
        address currencyAddr,
        uint64 expirationTimestampOffset
    ) internal view returns (ILendingProtocol.OfferParams memory) {
        return ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: nftAddr,
            nftTokenId: tokenId,
            currency: currencyAddr,
            principalAmount: DEFAULT_PRINCIPAL,
            interestRateAPR: DEFAULT_INTEREST_APR,
            durationSeconds: DEFAULT_DURATION_SECONDS,
            expirationTimestamp: uint64(block.timestamp + expirationTimestampOffset),
            originationFeeRate: DEFAULT_ORIGINATION_FEE_RATE,
            totalCapacity: 0, // Not used for standard offers
            maxPrincipalPerLoan: 0, // Not used for standard offers
            minNumberOfLoans: 0 // Not used for standard offers
        });
    }

    // Helper to make and return an offer ID
    function _makeAndGetStandardOfferId(address offerLender, ILendingProtocol.OfferParams memory params)
        internal
        returns (bytes32)
    {
        vm.startPrank(offerLender);
        bytes32 newOfferId = lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
        return newOfferId;
    }

    function test_AcceptStandardLoanOffer_Success() public {
        // 1. Lender makes an offer
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);

        // 2. Borrower accepts the offer
        vm.startPrank(borrower);

        uint256 lenderWethBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBefore = weth.balanceOf(borrower);

        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        assertTrue(loanId != bytes32(0), "Loan ID should not be zero");
        vm.stopPrank();

        // 3. Verify states
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.borrower, borrower, "Loan borrower incorrect");
        assertEq(loan.lender, lender, "Loan lender incorrect");
        assertEq(loan.nftContract, address(mockNft), "Loan NFT contract incorrect");
        assertEq(loan.nftTokenId, BORROWER_NFT_ID, "Loan NFT token ID incorrect");
        assertEq(loan.principalAmount, DEFAULT_PRINCIPAL, "Loan principal incorrect");
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan status not ACTIVE");

        // Verify NFT transfer
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), address(lendingProtocol), "NFT not escrowed by protocol");

        // Verify WETH transfers
        uint256 originationFee = (DEFAULT_PRINCIPAL * DEFAULT_ORIGINATION_FEE_RATE) / 10000;
        uint256 netAmountToBorrower = DEFAULT_PRINCIPAL - originationFee;

        // Lender pays out `principalAmount - originationFee` to the borrower.
        // The `originationFee` is a self-transfer from lender to lender, so it doesn't change the lender's balance.
        // Thus, the lender's balance should decrease by `principalAmount - originationFee`.
        assertEq(
            weth.balanceOf(lender),
            lenderWethBalanceBefore - (DEFAULT_PRINCIPAL - originationFee),
            "Lender WETH balance after loan incorrect"
        );
        assertEq(
            weth.balanceOf(borrower),
            borrowerWethBalanceBefore + netAmountToBorrower,
            "Borrower WETH balance after loan incorrect"
        );

        // Verify offer state
        ILendingProtocol.LoanOffer memory acceptedOffer = lendingProtocol.getLoanOffer(offerId);
        assertFalse(acceptedOffer.isActive, "Accepted offer should be inactive");
    }

    // --- AcceptLoanOffer Failure Tests ---

    function test_Fail_AcceptLoanOffer_OfferExpired() public {
        // 1. Lender makes an offer with short expiration (e.g., 1 second)
        ILendingProtocol.OfferParams memory offerParams = _makeStandardOfferParams(
            address(mockNft),
            BORROWER_NFT_ID,
            address(weth),
            1 // Expires in 1 second
        );
        offerId = _makeAndGetStandardOfferId(lender, offerParams);

        // 2. Advance time past expiration
        vm.warp(block.timestamp + 2 seconds);

        // 3. Borrower attempts to accept the offer
        vm.startPrank(borrower);
        vm.expectRevert(bytes("Offer expired"));
        lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();
    }

    function test_Fail_AcceptLoanOffer_OfferInactive() public {
        // 1. Lender makes an offer
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);

        // 2. Lender cancels the offer
        vm.startPrank(lender);
        lendingProtocol.cancelLoanOffer(offerId);
        vm.stopPrank();

        // 3. Borrower attempts to accept the now inactive offer
        vm.startPrank(borrower);
        vm.expectRevert(bytes("Offer not active"));
        lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();
    }

    function test_Fail_AcceptLoanOffer_NotNftOwner() public {
        // 1. Lender makes an offer for an NFT the borrower doesn't own
        ILendingProtocol.OfferParams memory offerParams = _makeStandardOfferParams(
            address(mockNft),
            BORROWER_NFT_ID,
            address(weth),
            1 days // BORROWER_NFT_ID is owned by `borrower`
        );
        offerId = _makeAndGetStandardOfferId(lender, offerParams);

        // 2. `otherUser` (who doesn't own BORROWER_NFT_ID) attempts to accept
        vm.startPrank(otherUser);
        // Note: The exact revert message depends on whether it's a vault or direct NFT.
        // For direct NFT, it's "Not NFT owner" from LoanManager.
        // If it were a vault, it would be "Not vault owner".
        // Base setup uses direct NFT.
        vm.expectRevert(bytes("Not NFT owner"));
        lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // Also test scenario where NFT is owned by someone else (not the borrower)
        uint256 otherNftId = 99;
        mockNft.mint(otherUser, otherNftId); // otherUser owns otherNftId

        ILendingProtocol.OfferParams memory offerParamsForOtherNft =
            _makeStandardOfferParams(address(mockNft), otherNftId, address(weth), 1 days);
        bytes32 offerIdForOtherNft = _makeAndGetStandardOfferId(lender, offerParamsForOtherNft);

        vm.startPrank(borrower); // Borrower tries to accept offer for NFT they don't own
        vm.expectRevert(bytes("Not NFT owner"));
        lendingProtocol.acceptLoanOffer(offerIdForOtherNft, address(mockNft), otherNftId);
        vm.stopPrank();
    }

    // --- RepayLoan Tests ---

    function test_RepayLoan_Success() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Calculate interest and total repayment
        ILendingProtocol.Loan memory loanBeforeRepayment = lendingProtocol.getLoan(loanId);
        // Simulate some time passing for interest to accrue, but less than duration
        vm.warp(block.timestamp + (DEFAULT_DURATION_SECONDS / 2));
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loanBeforeRepayment.principalAmount + interest;

        // 3. Borrower approves WETH and repays
        vm.startPrank(borrower);
        weth.mint(borrower, totalRepayment); // Ensure borrower has enough WETH
        weth.approve(address(lendingProtocol), totalRepayment);

        uint256 borrowerWethBalanceBeforeRepay = weth.balanceOf(borrower);
        uint256 lenderWethBalanceBeforeRepay = weth.balanceOf(lender);
        address initialNFTOwner = mockNft.ownerOf(BORROWER_NFT_ID); // Should be lending protocol

        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        // 4. Verify states
        ILendingProtocol.Loan memory loanAfterRepayment = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loanAfterRepayment.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(loanAfterRepayment.accruedInterest, interest, "Accrued interest incorrect");

        // Verify WETH transfers
        assertEq(
            weth.balanceOf(borrower),
            borrowerWethBalanceBeforeRepay - totalRepayment,
            "Borrower WETH balance incorrect after repay"
        );
        assertEq(
            weth.balanceOf(lender),
            lenderWethBalanceBeforeRepay + totalRepayment,
            "Lender WETH balance incorrect after repay"
        );

        // Verify NFT return
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT not returned to borrower");
        assertNotEq(initialNFTOwner, borrower, "NFT was already with borrower which is wrong for test logic");
    }

    function test_Fail_RepayLoan_NotBorrower() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. `otherUser` (not borrower) attempts to repay
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;

        vm.startPrank(otherUser);
        weth.mint(otherUser, totalRepayment); // Give otherUser funds
        weth.approve(address(lendingProtocol), totalRepayment);

        vm.expectRevert(bytes("Not borrower"));
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_Fail_RepayLoan_InsufficientFunds() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Borrower attempts to repay with insufficient WETH
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;

        // Ensure borrower has less than totalRepayment (e.g. 1 wei less or 0)
        // Borrower already received principal - fee. Let's ensure their balance is less than totalRepayment.
        uint256 currentBorrowerBalance = weth.balanceOf(borrower);
        if (currentBorrowerBalance >= totalRepayment) {
            // Burn some tokens to make sure they don't have enough
            vm.prank(borrower);
            weth.burn(currentBorrowerBalance - (totalRepayment / 2)); // Leave them with half of what's needed
        }

        vm.startPrank(borrower);
        // Approve whatever they have
        weth.approve(address(lendingProtocol), weth.balanceOf(borrower));

        // Expect revert from SafeERC20: ERC20: transfer amount exceeds balance
        // The exact revert string can vary. Checking for a generic ERC20 failure.
        // Using `expectRevert()` without specific error if it's too variable or comes from OpenZeppelin's SafeERC20.
        // Using OpenZeppelin's modern error for insufficient balance.
        // Need to import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; as ERC20Contract for the error.
        // However, SafeERC20 uses `require(success && data.length == 0, "SafeERC20: ERC20 operation did not succeed");`
        // for `transferFrom` if the token returns false or data.
        // If the borrower's balance is less than totalRepayment, and they approve their exact balance,
        // the transferFrom will fail due to insufficient allowance for the totalRepayment amount.
        uint256 currentBorrowerWethHolding = weth.balanceOf(borrower); // This is the actual allowance provided
        // Manually specify the selector for ERC20InsufficientAllowance(address,uint256,uint256)
        bytes4 errorSelector = bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)"));
        vm.expectRevert(
            abi.encodeWithSelector(
                errorSelector,
                address(lendingProtocol), // spender
                currentBorrowerWethHolding, // allowance
                totalRepayment // needed
            )
        );
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    // --- ClaimCollateral Tests ---

    function test_ClaimCollateral_Success() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Advance time past loan due time to put it in default
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 seconds); // 1 second after due time

        // 3. Lender claims collateral
        vm.startPrank(lender);
        address initialNFTOwnerInLP = mockNft.ownerOf(BORROWER_NFT_ID); // Should be lending protocol
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        // 4. Verify states
        ILendingProtocol.Loan memory loanAfterClaim = lendingProtocol.getLoan(loanId);
        assertEq(
            uint8(loanAfterClaim.status), uint8(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status not DEFAULTED"
        );

        // Verify NFT transfer to lender
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), lender, "NFT not transferred to lender");
        assertEq(initialNFTOwnerInLP, address(lendingProtocol), "NFT was not held by LP before claim");
    }

    function test_Fail_ClaimCollateral_NotLender() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Advance time past loan due time
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 seconds);

        // 3. `otherUser` (not lender) attempts to claim
        vm.startPrank(otherUser);
        vm.expectRevert(bytes("Not lender"));
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }

    function test_Fail_ClaimCollateral_LoanNotDefaulted() public {
        // 1. Create an active loan
        ILendingProtocol.OfferParams memory offerParams =
            _makeStandardOfferParams(address(mockNft), BORROWER_NFT_ID, address(weth), 1 days);
        offerId = _makeAndGetStandardOfferId(lender, offerParams);
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Do NOT advance time past loan due time. Loan is active but not defaulted.
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertTrue(block.timestamp <= loan.dueTime, "Loan is past due, test invalid");

        // 3. Lender attempts to claim collateral prematurely
        vm.startPrank(lender);
        vm.expectRevert(bytes("Loan not defaulted"));
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }
}
