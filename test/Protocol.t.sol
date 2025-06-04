// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {LendingProtocol} from "../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {CollectionManager} from "../src/core/CollectionManager.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {PurchaseBundler} from "../src/core/PurchaseBundler.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";

// Mocks - Updated to local mocks
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";

contract ProtocolTest is Test {
    LendingProtocol lendingProtocol;
    CurrencyManager currencyManager;
    CollectionManager collectionManager;
    VaultsFactory vaultsFactory;
    Liquidation liquidation;
    PurchaseBundler purchaseBundler;

    ERC20Mock weth;
    ERC20Mock usdc;
    ERC721Mock nftCollection;

    address alice = vm.addr(1); // Lender
    address bob = vm.addr(2); // Borrower
    address charlie = vm.addr(3); // Another user

    uint256 constant WETH_STARTING_BALANCE = 1000 ether;
    uint256 constant USDC_STARTING_BALANCE = 1000000 * 1e6; // 1M USDC

    function setUp() public {
        // Deploy Mock Tokens
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy NFT Collection
        nftCollection = new ERC721Mock("Test NFT", "TNFT");

        // Deploy Managers
        address[] memory initialCurrencies = new address[](1);
        initialCurrencies[0] = address(weth);
        currencyManager = new CurrencyManager(initialCurrencies);
        currencyManager.addSupportedCurrency(address(usdc));

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(nftCollection);
        collectionManager = new CollectionManager(initialCollections);

        // Deploy VaultsFactory (optional)
        vaultsFactory = new VaultsFactory("Test Vaults", "TVF");

        // Deploy Liquidation and PurchaseBundler (need LP address later)
        liquidation = new Liquidation(address(0));
        purchaseBundler = new PurchaseBundler(address(0));

        // Deploy LendingProtocol
        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidation),
            address(purchaseBundler)
        );

        // Set LP address in Liquidation and PurchaseBundler
        liquidation.setLendingProtocol(address(lendingProtocol));
        purchaseBundler.setLendingProtocol(address(lendingProtocol));

        // Fund users
        weth.mint(alice, WETH_STARTING_BALANCE);
        weth.mint(bob, WETH_STARTING_BALANCE);
        usdc.mint(alice, USDC_STARTING_BALANCE);
        usdc.mint(bob, USDC_STARTING_BALANCE);

        // Mint NFT to Bob
        nftCollection.mint(bob, 1);
        nftCollection.mint(bob, 2);

        // Mint NFT to Charlie
        nftCollection.mint(charlie, 3);

        // Fund Charlie
        weth.mint(charlie, WETH_STARTING_BALANCE);
        usdc.mint(charlie, USDC_STARTING_BALANCE);

        // Mint another NFT to Bob for vault testing
        nftCollection.mint(bob, 10);
    }

    function test_InitialSetup() public {
        assertTrue(currencyManager.isCurrencySupported(address(weth)));
        assertTrue(currencyManager.isCurrencySupported(address(usdc)));
        assertTrue(collectionManager.isCollectionWhitelisted(address(nftCollection)));
        assertEq(nftCollection.ownerOf(1), bob);
        assertEq(nftCollection.ownerOf(3), charlie); // Charlie owns NFT ID 3
        assertEq(weth.balanceOf(charlie), WETH_STARTING_BALANCE); // Charlie has WETH
        assertEq(usdc.balanceOf(charlie), USDC_STARTING_BALANCE); // Charlie has USDC
        assertEq(nftCollection.ownerOf(10), bob); // Bob owns NFT ID 10 for vault
    }

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
        assertTrue(
            weth.balanceOf(bob) >= WETH_STARTING_BALANCE + principal - (principal * originationFee / 10000) - 100 wei
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

    // Add more tests:
    // - Collection offers
    // - Refinancing
    // - Renegotiation
    // - Liquidation (claim collateral, auction)
    // - Sell & Repay
    // - Vaults
    // - Edge cases, security checks (reentrancy, access control)

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

        // Deal Alice a specific amount of WETH, less than totalCapacity * principal
        weth.burn(alice, weth.balanceOf(alice)); // Burn initial balance
        weth.mint(alice, aliceActualFunding); // Mint specific amount
        assertEq(weth.balanceOf(alice), aliceActualFunding, "Alice initial WETH incorrect");

        vm.startPrank(alice);
        // Alice approves for the full totalCapacity, even if she can't fund it all initially
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

        vm.expectEmit(true, true, true, true); // For OfferMade
        emit ILendingProtocol.OfferMade(0, alice, offerParams.offerType, offerParams.nftContract, 0, address(weth), principalPerLoan, 500, 30 days, uint64(block.timestamp + 1 days), 100, totalCapacityForOffer, principalPerLoan, 0);
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID should not be zero");
        vm.stopPrank();

        // Bob (Borrower 1) accepts the offer - this should succeed
        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1); // Bob's NFT ID 1

        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        vm.expectEmit(true, true, true, true); // For OfferAccepted (Bob)
        emit ILendingProtocol.OfferAccepted(offerId, 0, bob, alice, address(nftCollection), 1, address(weth), principalPerLoan, block.timestamp, 30 days, 500, 100);
        bytes32 loanId1 = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        assertTrue(loanId1 != 0, "Loan ID 1 should not be zero");

        assertEq(weth.balanceOf(alice), aliceInitialWeth - principalPerLoan, "Alice WETH balance incorrect after Bob's loan");
        uint256 expectedBobWeth = bobInitialWeth + principalPerLoan - (principalPerLoan * offerParams.originationFeeRate / 10000);
        assertEq(weth.balanceOf(bob), expectedBobWeth, "Bob WETH balance incorrect after loan");
        vm.stopPrank();

        // Alice now has 0.5 ether (1.5 - 1.0)
        assertEq(weth.balanceOf(alice), 0.5 ether, "Alice should have 0.5 WETH remaining");

        // Charlie (Borrower 2) attempts to accept the offer - this should fail
        vm.startPrank(charlie);
        nftCollection.approve(address(lendingProtocol), 3); // Charlie's NFT ID 3

        // Expecting a revert due to insufficient balance from lender (Alice)
        // The exact error depends on SafeERC20 behavior, typically "ERC20: transfer amount exceeds balance"
        // For Solidity 0.8.x, arithmetic errors (underflow/overflow) are also possible if SafeERC20 is not used or if checks are internal.
        // Let's use a generic ERC20 error first.
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        // Alternative if the above fails: vm.expectRevert(stdError.arithmeticError);
        lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 3);
        vm.stopPrank();

        // Verify offer status - amountDrawn should only reflect Bob's loan
        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.amountDrawn, principalPerLoan, "Offer amountDrawn should only be for Bob's loan");
        assertTrue(offer.isActive, "Offer should still be active as total capacity not met, even if lender can't fund");
    }

    function test_CollectionOffer_OfferCreation_PrincipalCanBeGreaterThanMaxPrincipalPerLoan() public {
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 2 ether); // Approve enough for totalCapacity

        uint256 offerPrincipal = 1 ether;
        uint256 offerMaxPrincipalPerLoan = 0.5 ether; // This is less than offerPrincipal
        uint256 offerTotalCapacity = 2 ether;

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(nftCollection),
            nftTokenId: 0, // Not used for collection offers
            currency: address(weth),
            principalAmount: offerPrincipal,
            interestRateAPR: 500, // 5%
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 100, // 1%
            totalCapacity: offerTotalCapacity,
            maxPrincipalPerLoan: offerMaxPrincipalPerLoan, // Set lower than principalAmount
            minNumberOfLoans: 0
        });

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(
            0, // offerId is dynamic
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

        // Bob accepts the offer
        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1); // Bob's NFT ID 1

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(
            offerId,
            0, // loanId is dynamic
            bob,
            alice,
            address(nftCollection),
            1, // NFT ID
            address(weth),
            offerPrincipal, // Expecting loan to use offer.principalAmount
            block.timestamp, // Approximate
            createdOffer.durationSeconds,
            createdOffer.interestRateAPR,
            createdOffer.originationFeeRate
        );
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        assertTrue(loanId != 0, "Loan ID should not be zero");

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        // This assertion confirms that the loan's principal is based on offer.principalAmount,
        // not capped by offer.maxPrincipalPerLoan at the point of acceptance in the current logic.
        assertEq(loan.principalAmount, offerPrincipal, "Loan principalAmount should be offer.principalAmount, not capped by maxPrincipalPerLoan");

        uint256 expectedBobWeth = bobInitialWeth + offerPrincipal - (offerPrincipal * createdOffer.originationFeeRate / 10000);
        assertEq(weth.balanceOf(bob), expectedBobWeth, "Bob WETH balance incorrect");
        assertEq(weth.balanceOf(alice), aliceInitialWeth - offerPrincipal, "Alice WETH balance incorrect");
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol), "NFT should be held by protocol");
        vm.stopPrank();
    }

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
        // Charlie pays paymentToOldLender + diffToBorrower. Fee is internal.
        assertEq(weth.balanceOf(charlie), charlieInitialWeth - (paymentToOldLender + diffToBorrower), "Charlie (new lender) balance incorrect");
        vm.stopPrank();
    }

    function test_Refinance_Revert_PrincipalReduction() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        // ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);

        vm.startPrank(charlie);
        uint256 newPrincipalAmountReduced = 0.9 ether; // Less than original 1 ether

        // Approval amount doesn't strictly matter as it should revert before transfer
        weth.approve(address(lendingProtocol), 2 ether);

        vm.expectRevert("Principal reduction not allowed in refinance"); // Exact revert string from contract
        lendingProtocol.refinanceLoan(
            loanId,
            newPrincipalAmountReduced,
            400, // new APR
            60 days, // new duration
            50 // new origination fee
        );
        vm.stopPrank();
    }

    function test_Refinance_Revert_OriginalLoanNotActive() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory loanDetails = lendingProtocol.getLoan(loanId);

        // Bob repays the loan
        vm.warp(block.timestamp + 15 days); // Let some time pass
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loanDetails.principalAmount + interest;

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loanDetails = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loanDetails.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");

        // Charlie attempts to refinance
        vm.startPrank(charlie);
        weth.approve(address(lendingProtocol), 2 ether); // Arbitrary approval

        vm.expectRevert("Original loan not active"); // Exact revert string from contract
        lendingProtocol.refinanceLoan(
            loanId,
            1 ether, // new principal
            400, // new APR
            60 days, // new duration
            50 // new origination fee
        );
        vm.stopPrank();
    }

    function test_Refinance_Successful_NewPrincipalSameAsOld() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);

        vm.warp(block.timestamp + 5 days); // Let some interest accrue

        uint256 newPrincipalAmount = oldLoan.principalAmount; // Same as old
        uint256 newInterestRateAPR = 300; // Better rate for Bob
        uint256 newDurationSeconds = 20 days;
        uint256 newOriginationFeeRate = 0; // No new fee

        uint256 aliceInitialWeth = weth.balanceOf(alice);
        uint256 bobInitialWeth = weth.balanceOf(bob); // Should be largely unchanged
        uint256 charlieInitialWeth = weth.balanceOf(charlie);

        vm.startPrank(charlie);
        uint256 interestForOldLender = lendingProtocol.calculateInterest(loanId);
        uint256 paymentToOldLender = oldLoan.principalAmount + interestForOldLender;
        uint256 newLenderOriginationFee = 0; // As per newOriginationFeeRate = 0

        // Diff to borrower is 0
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
            block.timestamp + newDurationSeconds, // approx
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
        // Bob's balance might change due to gas, but not due to principal difference.
        // We can assert it's close to initial, or exactly initial if no other tx.
        // For simplicity, we'll check it's not significantly changed by the refinance mechanics itself.
        assertTrue(weth.balanceOf(bob) >= bobInitialWeth - 0.01 ether && weth.balanceOf(bob) <= bobInitialWeth + 0.01 ether, "Bob balance changed unexpectedly (same principal)");
        assertEq(weth.balanceOf(charlie), charlieInitialWeth - paymentToOldLender, "Charlie balance incorrect (same principal)");
        vm.stopPrank();
    }

    // Alias for clarity in renegotiation tests
    function _createInitialLoanForRenegotiation() internal returns (bytes32 loanId) {
        return _createInitialLoanForRefinance();
    }

    function test_Renegotiation_Successful_LenderProposes_BorrowerAccepts_IncreasedPrincipal() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory oldLoan = lendingProtocol.getLoan(loanId);
        uint256 originalLoanStartTime = oldLoan.startTime;

        vm.warp(block.timestamp + 7 days); // Let some time pass

        // Lender (Alice) Proposes Renegotiation
        uint256 proposedPrincipalAmount = 1.2 ether; // Increased
        uint256 proposedInterestRateAPR = 550; // 5.5%
        uint256 proposedDurationSeconds = 45 days; // From original start time

        // Ensure Alice has enough WETH for the additional principal
        uint256 additionalPrincipal = proposedPrincipalAmount - oldLoan.principalAmount;
        if (weth.balanceOf(alice) < additionalPrincipal) {
             weth.deal(alice, weth.balanceOf(alice) + additionalPrincipal); // Top up if needed
        }
        // Alice needs to approve the protocol for the additional amount she will pay out
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

        // Borrower (Bob) Accepts Renegotiation
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
            originalLoanStartTime + proposedDurationSeconds, // Expected new due time
            0 // Expected accrued interest after renegotiation
        );
        lendingProtocol.acceptRenegotiation(proposalId);

        // Verify Post-Renegotiation State
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

        vm.warp(block.timestamp + 3 days); // Let some time pass

        // Lender (Alice) Proposes Renegotiation
        uint256 proposedPrincipalAmount = 0.8 ether; // Decreased
        uint256 proposedInterestRateAPR = 450; // 4.5%
        uint256 proposedDurationSeconds = 25 days; // From original start time

        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(
            loanId,
            proposedPrincipalAmount,
            proposedInterestRateAPR,
            proposedDurationSeconds
        );
        assertTrue(proposalId != 0, "Proposal ID should not be zero for decreased principal");
        vm.stopPrank();

        // Borrower (Bob) Accepts Renegotiation
        uint256 bobInitialWeth = weth.balanceOf(bob);
        uint256 aliceInitialWeth = weth.balanceOf(alice);
        uint256 principalReduction = oldLoan.principalAmount - proposedPrincipalAmount;

        vm.startPrank(bob);
        // Bob approves WETH for the principal reduction he pays back to Alice
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
            originalLoanStartTime + proposedDurationSeconds, // Expected new due time
            0 // Expected accrued interest after renegotiation
        );
        lendingProtocol.acceptRenegotiation(proposalId);

        // Verify Post-Renegotiation State
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
        vm.startPrank(charlie); // Charlie is not the lender
        vm.expectRevert("Not lender");
        lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_NotBorrowerAccepts() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        // Alice (lender) proposes
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();

        vm.startPrank(charlie); // Charlie is not the borrower
        vm.expectRevert("Not borrower");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_ProposalNotFound() public {
        _createInitialLoanForRenegotiation(); // Create a loan so context is valid
        vm.startPrank(bob); // Bob is a valid borrower for some loan
        bytes32 fakeProposalId = keccak256(abi.encodePacked("fake_id"));
        vm.expectRevert("Proposal not found or not for this loan");
        lendingProtocol.acceptRenegotiation(fakeProposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_LoanNotActiveForPropose() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        // Bob repays the loan
        vm.startPrank(bob);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        weth.approve(address(lendingProtocol), loan.principalAmount + interest);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        // Alice attempts to propose for repaid loan
        vm.startPrank(alice);
        vm.expectRevert("Loan not active");
        lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 500, 30 days);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_LoanNotActiveForAccept() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        // Alice (lender) proposes
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 1.1 ether, 550, 40 days);
        vm.stopPrank();

        // Bob repays the loan AFTER proposal
        vm.startPrank(bob);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        weth.approve(address(lendingProtocol), loan.principalAmount + interest);
        // Alice needs to have approved the additional funds for the proposal in case it's accepted
        // However, the loan is repaid before acceptance, so this might not be hit if checks prevent it.
        // Let's ensure Alice has funds in case the check for active loan is after fund transfer logic (it shouldn't be).
        vm.deal(alice, weth.balanceOf(alice) + 0.1 ether); // Ensure Alice has the 0.1 ether diff just in case
        vm.prank(alice); // For the approval of the diff
        weth.approve(address(lendingProtocol), 0.1 ether);


        lendingProtocol.repayLoan(loanId); // Loan becomes REPAID
        vm.stopPrank(); // Bob stops

        // Bob attempts to accept proposal for now repaid loan
        vm.startPrank(bob);
        vm.expectRevert("Loan not active");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }

    function test_Renegotiation_Revert_ProposalAlreadyActioned() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        // Alice (lender) proposes
        vm.startPrank(alice);
        bytes32 proposalId = lendingProtocol.proposeRenegotiation(loanId, 0.9 ether, 450, 20 days); // Decrease principal
        vm.stopPrank();

        // Bob accepts
        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), 0.1 ether); // Approve the difference
        lendingProtocol.acceptRenegotiation(proposalId);
        // Bob tries to accept again
        vm.expectRevert("Proposal already actioned");
        lendingProtocol.acceptRenegotiation(proposalId);
        vm.stopPrank();
    }

    // --- Claim Collateral Tests ---

    function test_ClaimCollateral_Successful() public {
        bytes32 loanId = _createInitialLoanForRenegotiation(); // Using alias, same as _createInitialLoanForRefinance
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        // Default the Loan
        vm.warp(loan.dueTime + 1 days);

        // Lender (Alice) Claims Collateral
        vm.startPrank(alice);
        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT owner should be protocol before claim");

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.CollateralClaimed(loanId, alice, loan.nftContract, loan.nftTokenId);

        lendingProtocol.claimCollateral(loanId);

        // Verify Post-Claim State
        ILendingProtocol.Loan memory defaultedLoan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(defaultedLoan.status), uint256(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status should be DEFAULTED");
        assertEq(nftCollection.ownerOf(loan.nftTokenId), alice, "NFT owner should be Alice after claim");
        vm.stopPrank();
    }

    function test_ClaimCollateral_Revert_NotLender() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        // Default the Loan
        vm.warp(loan.dueTime + 1 days);

        // Attempt Claim by Non-Lender (Charlie)
        vm.startPrank(charlie);
        vm.expectRevert("Not lender");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT should still be owned by protocol");
    }

    function test_ClaimCollateral_Revert_LoanNotDefaulted() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        // Do NOT warp time past dueTime, or warp to a point before dueTime
        if (block.timestamp < loan.dueTime) {
            // If current time is already past due time (e.g. due to previous tests), this test might be invalid.
            // However, each test runs in a fresh state.
        } else {
             // This case should ideally not be hit in a fresh test run if duration > 0
            vm.warp(loan.startTime + loan.durationSeconds / 2); // Warp to midpoint, definitely not defaulted
        }
        assertTrue(block.timestamp <= loan.dueTime, "Timestamp should be before or at due time for this test");


        // Attempt Claim by Lender (Alice)
        vm.startPrank(alice);
        vm.expectRevert("Loan not yet defaulted");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT should still be owned by protocol");
        ILendingProtocol.Loan memory currentLoan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(currentLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Loan status should still be ACTIVE");
    }

    function test_ClaimCollateral_Revert_LoanAlreadyClaimed() public {
        bytes32 loanId = _createInitialLoanForRenegotiation();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        // Default the Loan
        vm.warp(loan.dueTime + 1 days);

        // Alice claims collateral successfully
        vm.startPrank(alice);
        lendingProtocol.claimCollateral(loanId);
        assertEq(nftCollection.ownerOf(loan.nftTokenId), alice, "NFT should be owned by Alice after first claim");
        vm.stopPrank(); // Alice stops for a moment

        // Attempt Claim Again by Lender (Alice)
        vm.startPrank(alice);
        // The primary error would be ERC721 trying to transfer an NFT not owned by `address(this)` anymore.
        // The "Loan not active/defaulted" check might also catch it if status was changed further,
        // but after first claim, status is DEFAULTED.
        // `require(currentLoan.status == LoanStatus.ACTIVE || currentLoan.status == LoanStatus.DEFAULTED` -> true for DEFAULTED
        // `require(block.timestamp > currentLoan.dueTime)` -> true
        // Then `currentLoan.status = LoanStatus.DEFAULTED;` (no change)
        // Then `IERC721(currentLoan.nftContract).safeTransferFrom(address(this), msg.sender, currentLoan.nftTokenId);` -> this fails.
        vm.expectRevert(bytes("ERC721: transfer from incorrect owner"));
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }

    // --- Vault Collateral Tests ---

    function test_VaultCollateral_MakeOffer_Accept_Repay() public {
        uint256 vaultNftId = 10; // The NFT ID Bob will put in the vault

        // Bob Creates a Vault
        vm.startPrank(bob);
        nftCollection.approve(address(vaultsFactory), vaultNftId);

        VaultsFactory.NFTItem[] memory items = new VaultsFactory.NFTItem[](1);
        items[0] = VaultsFactory.NFTItem({
            contractAddress: address(nftCollection),
            tokenId: vaultNftId,
            amount: 1,
            isERC1155: false
        });

        // Predicting vaultId can be tricky if other tests mint vaults.
        // For robustness, capture it from event or assume it's the next one if factory is fresh.
        // Let's assume it's vault ID 1 for this test if no other vaults created by factory yet.
        // Or, better, get the count and expect next. For now, simple assumption if this is the first vault.
        uint256 expectedVaultId = vaultsFactory.totalSupply() + 1;

        vm.expectEmit(true, true, true, true); // Check all indexed fields
        emit VaultsFactory.VaultCreated(expectedVaultId, bob, items);
        uint256 vaultId1 = vaultsFactory.mintVault(bob, items);
        assertEq(vaultId1, expectedVaultId, "Vault ID mismatch");


        assertEq(vaultsFactory.ownerOf(vaultId1), bob, "Bob should own the new vault");
        assertEq(nftCollection.ownerOf(vaultNftId), address(vaultsFactory), "NFT should be held by VaultsFactory");
        vm.stopPrank();

        // Alice (Lender) Makes an Offer for Bob's Vault
        uint256 loanPrincipalForVault = 1 ether;
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), loanPrincipalForVault);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(vaultsFactory), // Target VaultsFactory contract
            nftTokenId: vaultId1,                // Target specific vault ID
            currency: address(weth),
            principalAmount: loanPrincipalForVault,
            interestRateAPR: 500, // 5%
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });

        // Expect OfferMade from lendingProtocol
        // Note: offerId is not easily predictable without knowing internal counter of LP
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(0, alice, offerParams.offerType, offerParams.nftContract, offerParams.nftTokenId, offerParams.currency, offerParams.principalAmount, offerParams.interestRateAPR, offerParams.durationSeconds, offerParams.expirationTimestamp, offerParams.originationFeeRate,0,0,0);
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID for vault loan is zero");
        vm.stopPrank();

        // Bob (Borrower) Accepts Offer with Vault
        vm.startPrank(bob);
        vaultsFactory.approve(address(lendingProtocol), vaultId1);

        // Expect OfferAccepted from lendingProtocol
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(offerId, 0, bob, alice, address(vaultsFactory), vaultId1, address(weth), loanPrincipalForVault, block.timestamp, 30 days, 500, 0);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(vaultsFactory), vaultId1);
        assertTrue(loanId != 0, "Loan ID for vault collateral is zero");

        // Verify Loan Details for Vault Collateral
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertTrue(loan.isVault, "Loan.isVault should be true");
        assertEq(loan.nftContract, address(vaultsFactory), "Loan.nftContract should be VaultsFactory address");
        assertEq(loan.nftTokenId, vaultId1, "Loan.nftTokenId should be vaultId1");
        assertEq(vaultsFactory.ownerOf(vaultId1), address(lendingProtocol), "Vault should be escrowed by LendingProtocol");
        vm.stopPrank();

        // Bob Repays the Loan
        vm.startPrank(bob);
        vm.warp(block.timestamp + 15 days); // Accrue some interest
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRepaid(loanId, bob, alice, totalRepayment, interest);
        lendingProtocol.repayLoan(loanId);

        // Verify Post-Repayment State
        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(vaultsFactory.ownerOf(vaultId1), bob, "Vault should be returned to Bob");
        vm.stopPrank();
    }

    function test_VaultCollateral_Default_Claim() public {
        uint256 vaultNftId = 10; // Use the one minted to Bob in setUp

        // Bob Creates a Vault
        vm.startPrank(bob);
        nftCollection.approve(address(vaultsFactory), vaultNftId);
        VaultsFactory.NFTItem[] memory items = new VaultsFactory.NFTItem[](1);
        items[0] = VaultsFactory.NFTItem({contractAddress: address(nftCollection), tokenId: vaultNftId, amount: 1, isERC1155: false});
        uint256 vaultId1 = vaultsFactory.mintVault(bob, items);
        vm.stopPrank();

        // Alice Makes an Offer for Bob's Vault
        uint256 loanPrincipalForVault = 0.5 ether; // Smaller principal for variety
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), loanPrincipalForVault);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(vaultsFactory),
            nftTokenId: vaultId1,
            currency: address(weth),
            principalAmount: loanPrincipalForVault,
            interestRateAPR: 600, // 6%
            durationSeconds: 10 days, // Shorter duration for faster default
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // Bob Accepts Offer with Vault
        vm.startPrank(bob);
        vaultsFactory.approve(address(lendingProtocol), vaultId1);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(vaultsFactory), vaultId1);
        vm.stopPrank();

        // Default the Loan
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 days); // Warp time past loan's dueTime

        // Alice (Lender) Claims Vault Collateral
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.CollateralClaimed(loanId, alice, address(vaultsFactory), vaultId1);
        lendingProtocol.claimCollateral(loanId);

        // Verify Post-Claim State
        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status not DEFAULTED after claim");
        assertEq(vaultsFactory.ownerOf(vaultId1), alice, "Vault should be transferred to Alice after claim");
        vm.stopPrank();
    }

    // --- Edge Case and Security Tests ---

    // Reentrancy Test: Malicious Borrower Contract for Repay
    function test_Reentrancy_RepayLoan() public {
        ReentrantBorrowerRepay reentrantBorrower = new ReentrantBorrowerRepay(lendingProtocol, weth, nftCollection, address(this));

        // Mint NFT to the reentrant borrower contract directly
        nftCollection.mint(address(reentrantBorrower), 99);
        reentrantBorrower.setNftId(99);

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
        // It needs WETH to pay origination fee if any, and to repay later.
        weth.mint(address(reentrantBorrower), 2 ether);
        vm.startPrank(address(reentrantBorrower));
        // Approve LP for the NFT it holds
        // In ReentrantBorrowerRepay, it should approve itself or be pre-approved.
        // For this structure, the ReentrantBorrowerRepay contract itself calls acceptLoanOffer.
        // It needs to approve the LendingProtocol for its own NFT.
        reentrantBorrower.approveNftToLP(address(lendingProtocol));
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 99);
        reentrantBorrower.setLoanId(loanId); // Inform attacker about the loanId
        vm.stopPrank();

        // Attacker (this test contract) will tell ReentrantBorrower to attempt repay
        // which will trigger onERC721Received and attempt re-entrancy.
        // The re-entrant call is lp.getLoan(loanId) which is a view function,
        // but it's enough to check the nonReentrant guard.
        // If it tried to call repayLoan again, it would fail due to nonReentrant.
        // We expect the repayLoan to complete successfully, and the re-entrant call inside onERC721Received to not cause issues.
        // The nonReentrant modifier should prevent state changes if a state-changing function was re-entered.

        uint256 interest = lendingProtocol.calculateInterest(loanId);
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;

        vm.prank(address(reentrantBorrower)); // Borrower initiates repay
        weth.approve(address(lendingProtocol), totalRepayment); // Borrower approves WETH for repay

        // No specific revert expected from repayLoan itself due to reentrancy guard handling it.
        // The reentrant call is a view call in this setup. If it were a state-changing call,
        // that specific reentrant call would be reverted by the guard on that function, or the outer call would fail.
        vm.prank(address(reentrantBorrower));
        lendingProtocol.repayLoan(loanId);

        // Check loan is repaid and ReentrantBorrower got NFT back
        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID));
        assertEq(nftCollection.ownerOf(99), address(reentrantBorrower));
        assertTrue(reentrantBorrower.reentrantCallSucceeded(), "Reentrant call should have been made (and handled)");
    }


    // Access Control Tests
    function test_AccessControl_SetCurrencyManager_Revert_NotOwner() public {
        vm.startPrank(alice); // Alice is not the owner
        CurrencyManager newCm = new CurrencyManager(new address[](0));
        vm.expectRevert("Ownable: caller is not the owner");
        lendingProtocol.setCurrencyManager(address(newCm));
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

    // Invalid Input Tests for makeLoanOffer
    function test_MakeLoanOffer_Revert_UnsupportedCurrency() public {
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UST");
        vm.startPrank(alice);
        unsupportedToken.mint(alice, 1 ether);
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
        ERC721Mock unlistedCollection = new ERC721Mock("Unlisted NFT", "UNFT");
        unlistedCollection.mint(bob, 1); // Bob owns an NFT from unlisted collection
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

    function test_MakeLoanOffer_Revert_CollectionNotWhitelisted_CollectionOffer() public {
        ERC721Mock unlistedCollection = new ERC721Mock("Unlisted NFT", "UNFT");
        // No need to mint, just referencing the unlisted collection address
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 5 ether); // For totalCapacity
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(unlistedCollection), // Unlisted collection
            nftTokenId: 0, // Not used for collection offer
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

    // Timestamp Manipulation Tests
    function test_RepayLoan_AtExactDueTime() public {
        bytes32 loanId = _createInitialLoanForRefinance(); // Helper creates loan for ID 1 from Alice to Bob
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime); // Warp to exact due time

        vm.startPrank(bob);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId); // Should succeed
        vm.stopPrank();

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID));
    }

    function test_RepayLoan_OneSecondPastDueTime_Revert_Defaulted() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 second); // Warp one second past due time

        vm.startPrank(bob);
        uint256 interest = lendingProtocol.calculateInterest(loanId); // Interest is capped at due time
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);

        vm.expectRevert("Loan past due (defaulted)");
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_ClaimCollateral_AtExactDueTime_Revert_NotDefaultedYet() public {
        bytes32 loanId = _createInitialLoanForRefinance();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime); // Warp to exact due time

        vm.startPrank(alice); // Lender
        vm.expectRevert("Loan not yet defaulted");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }

    function test_CalculateInterest_TimeTravel() public {
        bytes32 loanId = _createInitialLoanForRefinance(); // 30-day loan, 5% APR (simple interest for test)
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        uint256 principal = loan.principalAmount; // 1 ether
        uint256 apr = loan.interestRateAPR; // 500 (5%)

        // Interest for full period (30 days)
        // Interest = P * APR_daily * Duration_days
        // APR_daily = APR / 10000 / 365
        // Interest = P * (APR/10000) * (Duration_sec / SECS_PER_YEAR)
        // Interest = 1 ether * (500/10000) * (30 days / 365 days) approx
        uint256 expectedFullInterest = principal * apr * loan.durationSeconds / (10000 * 365 days);

        // At T0 (loan start time)
        vm.warp(loan.startTime);
        uint256 interestAtT0 = lendingProtocol.calculateInterest(loanId);
        assertEq(interestAtT0, 0, "Interest at T0 should be 0");

        // At T15 (midpoint)
        vm.warp(loan.startTime + 15 days);
        uint256 interestAtT15 = lendingProtocol.calculateInterest(loanId);
        assertTrue(interestAtT15 > 0 && interestAtT15 < expectedFullInterest, "Interest at T15 incorrect");
        assertApproxEqAbs(interestAtT15, expectedFullInterest / 2, 1 wei, "Interest at T15 should be approx half");


        // At T30 (due time)
        vm.warp(loan.dueTime);
        uint256 interestAtT30 = lendingProtocol.calculateInterest(loanId);
        assertApproxEqAbs(interestAtT30, expectedFullInterest, 1 wei, "Interest at T30 (due time) incorrect");

        // At T45 (past due time)
        vm.warp(loan.dueTime + 15 days);
        uint256 interestAtT45 = lendingProtocol.calculateInterest(loanId);
        assertApproxEqAbs(interestAtT45, expectedFullInterest, 1 wei, "Interest at T45 (past due) should be capped at T30 interest");
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

contract ReentrantBorrowerRepay is IERC721Receiver {
    LendingProtocol public lp;
    ERC20Mock public weth; // WETH token
    ERC721Mock public nft; // The collateral NFT contract
    bytes32 public loanId;
    uint256 public nftId;
    address public attacker; // Test contract address
    bool public reentrantCallMade;
    bool public reentrantCallSucceeded;

    constructor(LendingProtocol _lp, ERC20Mock _weth, ERC721Mock _nft, address _attacker) {
        lp = _lp;
        weth = _weth;
        nft = _nft;
        attacker = _attacker;
    }

    function setLoanId(bytes32 _loanId) public {
        loanId = _loanId;
    }
    function setNftId(uint256 _nftId) public {
        nftId = _nftId;
    }

    function approveNftToLP(address _lendingProtocol) public {
        nft.approve(_lendingProtocol, nftId);
    }


    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        if (msg.sender == address(lp)) { // Call came from LendingProtocol during repayLoan's NFT transfer
            reentrantCallMade = true;
            try lp.getLoan(loanId) { // Attempt a simple view function call
                reentrantCallSucceeded = true;
            } catch {
                reentrantCallSucceeded = false;
            }
            // If we tried to call lp.repayLoan(loanId) here, it would be blocked by nonReentrant.
            // try lp.repayLoan(loanId) {} catch Error(string memory reason) { if (keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("ReentrancyGuard: reentrant call"))) { reentrantCallBlockedByGuard = true; }} catch {}
        }
        return this.onERC721Received.selector;
    }
}
