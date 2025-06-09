// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol"; // Import Vm to access Vm.Log
// import {StdCheats} from "forge-std/StdCheats.sol"; // Not needed when Test is inherited
import {LendingProtocolBaseTest} from "../LendingProtocolBase.t.sol"; // Or your base test setup
import {ILendingProtocol} from "../../../src/interfaces/ILendingProtocol.sol";
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol"; // Assuming you have this
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol"; // Assuming you have this

contract RequestTests is
    LendingProtocolBaseTest // Inherit from base
{
    // address borrower = makeAddr("borrower"); // Inherited from LendingProtocolBaseTest
    // address lender = makeAddr("lender");     // Inherited from LendingProtocolBaseTest
    ERC721Mock testNft;
    ERC20Mock testCurrency;
    uint256 nftTokenId = 1;

    bytes32 lastRequestId; // To store requestId for subsequent tests
    bytes32 lastLoanId; // To store loanId for subsequent tests

    event LoanRequestMade(
        bytes32 indexed requestId,
        address indexed borrower,
        address indexed nftContract,
        uint256 nftTokenId,
        address currency,
        uint256 principalAmount,
        uint256 interestRateAPR,
        uint256 durationSeconds,
        uint64 expirationTimestamp
    );

    event LoanRequestCancelled(bytes32 indexed requestId, address indexed borrower);

    event LoanRequestAccepted(
        bytes32 indexed requestId,
        bytes32 indexed loanId,
        address indexed lender,
        address borrower,
        address nftContract,
        uint256 nftTokenId,
        address currency,
        uint256 principalAmount,
        uint64 dueTime
    );

    // Event from LoanManager, but emitted by LendingProtocol
    // This will be the requestId
    // Max 3 indexed, removing from lender
    // No longer indexed
    event OfferAccepted( // Re-used for loan acceptance via request
        bytes32 indexed loanId,
        bytes32 indexed offerId,
        address indexed borrower,
        address lender,
        address nftContractAddress,
        uint256 nftId,
        address currency,
        uint256 principal,
        uint64 dueDate
    );

    function setUp() public virtual override {
        super.setUp(); // Call base setup

        testNft = new ERC721Mock("TestNFT", "TNFT");
        testCurrency = new ERC20Mock("TestCurrency", "TCUR"); // Removed decimals

        // Mint NFT to borrower
        testNft.mint(borrower, nftTokenId);

        // Mint currency to lender and borrower (for approvals etc.)
        testCurrency.mint(lender, 1_000_000 * 10 ** 18); // Lender has plenty of funds
        testCurrency.mint(borrower, 100 * 10 ** 18); // Borrower for any potential fees or approvals

        // Whitelist collection and currency in LendingProtocol
        vm.prank(owner);
        // Directly use the 'collectionManager' instance from BaseTest for admin functions
        collectionManager.addWhitelistedCollection(address(testNft)); // Corrected function name and params
        vm.prank(owner);
        // Directly use the 'currencyManager' instance from BaseTest for admin functions
        currencyManager.addSupportedCurrency(address(testCurrency)); // Corrected function name and params
    }

    // --- Test makeLoanRequest ---

    function test_Req_makeLoanRequest_Success() public {
        vm.startPrank(borrower);
        ILendingProtocol.LoanRequestParams memory params = ILendingProtocol.LoanRequestParams({
            nftContract: address(testNft),
            nftTokenId: nftTokenId,
            currency: address(testCurrency),
            principalAmount: 100 * 10 ** 18, // 100 TC tokens
            interestRateAPR: 1000, // 10%
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 7 days)
        });

        // Removed vm.expectEmit from this helper function.
        // Event checking will be done in specific tests that need it.
        bytes32 requestId = lendingProtocol.makeLoanRequest(params);
        lastRequestId = requestId; // Save for other tests
        vm.stopPrank();

        ILendingProtocol.LoanRequest memory request = lendingProtocol.getLoanRequest(requestId);
        assertEq(request.borrower, borrower);
        assertTrue(request.isActive);
        assertEq(request.principalAmount, params.principalAmount);
    }

    function test_Req_makeLoanRequest_Fail_NotNFTOwner() public {
        vm.startPrank(lender); // Try to make request with NFT owned by borrower
        ILendingProtocol.LoanRequestParams memory params = ILendingProtocol.LoanRequestParams({
            nftContract: address(testNft),
            nftTokenId: nftTokenId, // This NFT is owned by borrower
            currency: address(testCurrency),
            principalAmount: 100 * 10 ** 18,
            interestRateAPR: 1000,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 7 days)
        });

        vm.expectRevert("RM: Not NFT owner");
        lendingProtocol.makeLoanRequest(params); // Changed protocol to lendingProtocol
        vm.stopPrank();
    }

    // Add more failure cases for makeLoanRequest:
    // - test_Req_makeLoanRequest_Fail_CurrencyNotSupported
    // - test_Req_makeLoanRequest_Fail_CollectionNotWhitelisted
    // - test_Req_makeLoanRequest_Fail_ZeroPrincipal
    // - test_Req_makeLoanRequest_Fail_ZeroDuration
    // - test_Req_makeLoanRequest_Fail_ExpirationInPast

    // --- Test cancelLoanRequest ---
    function test_Req_cancelLoanRequest_Success() public {
        // First, make a request
        test_Req_makeLoanRequest_Success(); // This sets lastRequestId

        vm.startPrank(borrower);
        vm.expectEmit(true, true, false, true, address(lendingProtocol)); // Changed protocol to lendingProtocol
        emit LoanRequestCancelled(lastRequestId, borrower);
        lendingProtocol.cancelLoanRequest(lastRequestId); // Changed protocol to lendingProtocol
        vm.stopPrank();

        ILendingProtocol.LoanRequest memory request = lendingProtocol.getLoanRequest(lastRequestId); // Changed protocol to lendingProtocol
        assertFalse(request.isActive);
    }

    function test_Req_cancelLoanRequest_Fail_NotOwner() public {
        test_Req_makeLoanRequest_Success();

        vm.startPrank(lender); // Try to cancel borrower's request
        vm.expectRevert("RM: Not request owner");
        lendingProtocol.cancelLoanRequest(lastRequestId); // Changed protocol to lendingProtocol
        vm.stopPrank();
    }

    // Add more failure cases for cancelLoanRequest:
    // - test_Req_cancelLoanRequest_Fail_AlreadyInactive / NotExists

    // --- Test acceptLoanRequest ---
    function test_Req_acceptLoanRequest_Success() public {
        test_Req_makeLoanRequest_Success(); // Borrower makes request, sets lastRequestId

        // Borrower approves protocol to take NFT
        vm.prank(borrower);
        testNft.approve(address(lendingProtocol), nftTokenId); // Changed protocol to lendingProtocol

        // Lender approves protocol to spend currency
        vm.prank(lender);
        testCurrency.approve(address(lendingProtocol), 100 * 10 ** 18); // Changed protocol to lendingProtocol

        vm.startPrank(lender);
        // Event checking removed from this test, will be covered by test_Req_acceptLoanRequest_Events_Precise

        bytes32 loanId = lendingProtocol.acceptLoanRequest(lastRequestId);
        lastLoanId = loanId; // Save for other tests
        vm.stopPrank();

        // Verify NFT transfer
        assertEq(testNft.ownerOf(nftTokenId), address(lendingProtocol)); // Changed protocol to lendingProtocol
        // Verify currency transfer
        assertEq(testCurrency.balanceOf(borrower), (100 + 100) * 10 ** 18); // Initial + loan principal
        assertEq(testCurrency.balanceOf(lender), (1_000_000 - 100) * 10 ** 18); // Initial - loan principal

        // Verify request inactive
        ILendingProtocol.LoanRequest memory req = lendingProtocol.getLoanRequest(lastRequestId); // Changed protocol to lendingProtocol
        assertFalse(req.isActive);

        // Verify loan details
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Changed protocol to lendingProtocol
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
        assertEq(loan.principalAmount, 100 * 10 ** 18);
        assertTrue(loan.status == ILendingProtocol.LoanStatus.ACTIVE);
    }

    // Helper to get event fields when IDs are dynamic
    function captureLoanRequestAccepted(bytes32 _requestId) internal returns (bytes32 loanId, uint64 dueTime) {
        vm.recordLogs();
        lendingProtocol.acceptLoanRequest(_requestId); // Changed protocol to lendingProtocol
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Changed Log[] to Vm.Log[]
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == LoanRequestAccepted.selector) {
                (bytes32 reqId, bytes32 lId, address eventLender, address eventBorrower, uint64 dTime) = // Unused variables
                 abi.decode(entries[i].data, (bytes32, bytes32, address, address, uint64));
                // Further decoding of topics for indexed fields if necessary
                return (lId, dTime); // reqId, eventLender, eventBorrower are unused, which is fine for a helper like this.
            }
        }
        revert("LoanRequestAccepted event not found");
    }

    function test_Req_acceptLoanRequest_Events_Precise() public {
        test_Req_makeLoanRequest_Success();

        vm.prank(borrower);
        testNft.approve(address(lendingProtocol), nftTokenId); // Changed protocol to lendingProtocol
        vm.prank(lender);
        testCurrency.approve(address(lendingProtocol), 100 * 10 ** 18); // Changed protocol to lendingProtocol

        ILendingProtocol.LoanRequest memory request = lendingProtocol.getLoanRequest(lastRequestId); // Changed protocol to lendingProtocol

        vm.startPrank(lender);
        // Expect LoanRequestAccepted from LendingProtocol
        // We can't know loanId beforehand for the emit check.
        // We can check other fields if we know them.
        // Or capture event and assert.

        // Expect OfferAccepted from LoanManager (via LendingProtocol)
        // Same issue with loanId.

        // For precise event checking, you might need to:
        // 1. Predict the loanId (if possible, based on current counter and inputs)
        // 2. Capture all emitted events and decode them manually to check.

        // Example of capturing (simplified):
        vm.recordLogs();
        bytes32 loanId = lendingProtocol.acceptLoanRequest(lastRequestId); // Changed protocol to lendingProtocol
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Changed Log[] to Vm.Log[]

        bool foundLoanRequestAccepted = false;
        bool foundOfferAccepted = false;
        uint64 expectedDueTime = uint64(block.timestamp + request.durationSeconds);

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == LoanRequestAccepted.selector) {
                // bytes32 rId; bytes32 lId; address l; address b; address nC; uint256 nT; address cur; uint256 pA; uint64 dT;
                // (rId, lId, l, b, nC, nT, cur, pA, dT) = abi.decode(entries[i].data, (bytes32, bytes32, address, address, address, uint256, address, uint256, uint64));
                // For indexed: entries[i].topics[1] is requestId, topics[2] is loanId, topics[3] is lender
                // Non-indexed are in data
                (
                    address decodedBorrower,
                    address decodedNftContract,
                    uint256 decodedNftTokenId,
                    address decodedCurrency,
                    uint256 decodedPrincipal,
                    uint64 decodedDueTime
                ) = abi.decode(entries[i].data, (address, address, uint256, address, uint256, uint64));

                assertEq(bytes32(entries[i].topics[1]), lastRequestId);
                assertEq(bytes32(entries[i].topics[2]), loanId);
                assertEq(address(uint160(uint256(entries[i].topics[3]))), lender); // Lender is indexed
                assertEq(decodedBorrower, borrower); // Borrower is not indexed in this event
                assertEq(decodedPrincipal, request.principalAmount);
                // Timestamps can be tricky due to block progression if not careful
                assertTrue(
                    decodedDueTime >= expectedDueTime && decodedDueTime <= expectedDueTime + 1, "Due time mismatch"
                );
                foundLoanRequestAccepted = true;
            }
            if (entries[i].topics[0] == OfferAccepted.selector) {
                // (bytes32 lId, bytes32 oId, address b, address l, address ncAdd, uint256 nId, address curr, uint256 princ, uint64 dDate) =
                //    abi.decode(entries[i].data, (bytes32,bytes32,address,address,address,uint256,address,uint256,uint64));
                assertEq(bytes32(entries[i].topics[1]), loanId); // loanId is indexed
                assertEq(bytes32(entries[i].topics[2]), lastRequestId); // offerId (requestId) is indexed
                assertEq(address(uint160(uint256(entries[i].topics[3]))), borrower); // borrower is indexed
                foundOfferAccepted = true;
            }
        }
        assertTrue(foundLoanRequestAccepted, "LoanRequestAccepted event not emitted or not found");
        assertTrue(foundOfferAccepted, "OfferAccepted event not emitted or not found");

        vm.stopPrank();
    }

    // Add more failure cases for acceptLoanRequest:
    // - test_Req_acceptLoanRequest_Fail_RequestInactive
    // - test_Req_acceptLoanRequest_Fail_RequestExpired
    // - test_Req_acceptLoanRequest_Fail_LenderIsBorrower
    // - test_Req_acceptLoanRequest_Fail_ProtocolNotApprovedNFT

    // --- Test Post-Acceptance (Basic) ---
    function test_Req_loanRepayment_Success() public {
        test_Req_acceptLoanRequest_Success(); // Creates a loan via request, sets lastLoanId

        require(lastLoanId != bytes32(0), "Loan ID not set from acceptLoanRequest");
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(lastLoanId);

        // Fast forward time to near due date but not past it
        vm.warp(loan.dueTime - 1 days); // Corrected to use dueTime

        uint256 interest = lendingProtocol.calculateInterest(lastLoanId); // Changed protocol to lendingProtocol
        uint256 totalRepayment = loan.principalAmount + interest;

        // Borrower approves currency for repayment
        vm.prank(borrower);
        testCurrency.approve(address(lendingProtocol), totalRepayment); // Changed protocol to lendingProtocol

        vm.startPrank(borrower);
        lendingProtocol.repayLoan(lastLoanId); // Changed protocol to lendingProtocol
        vm.stopPrank();

        ILendingProtocol.Loan memory repaidLoan = lendingProtocol.getLoan(lastLoanId); // Changed protocol to lendingProtocol
        assertTrue(repaidLoan.status == ILendingProtocol.LoanStatus.REPAID);
        assertEq(testNft.ownerOf(nftTokenId), borrower); // NFT returned to borrower
    }

    // Add test_Req_claimCollateral_Success if loan defaults
}
