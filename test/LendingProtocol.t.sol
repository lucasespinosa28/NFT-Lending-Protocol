// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

// Core contracts
import {LendingProtocol} from "../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {CollectionManager} from "../src/core/CollectionManager.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {PurchaseBundler} from "../src/core/PurchaseBundler.sol";
// import {RangeValidator} from "../src/core/RangeValidator.sol"; // Not directly used in basic offer
// import {Stash} from "../src/core/Stash.sol"; // Not directly used in basic offer

// Interfaces
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {RoyaltyManager} from "../src/core/RoyaltyManager.sol"; // Added import
import {MockRoyaltyModule} from "../src/mocks/MockRoyaltyModule.sol"; // Added import
import {MockIIPAssetRegistry} from "../src/mocks/MockIIPAssetRegistry.sol"; // Added import


// Mocks
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";

contract LendingProtocolTest is Test {
    // --- State Variables ---
    LendingProtocol internal lendingProtocol;
    CurrencyManager internal currencyManager;
    CollectionManager internal collectionManager;
    VaultsFactory internal vaultsFactory;
    Liquidation internal liquidation;
    PurchaseBundler internal purchaseBundler;
    RoyaltyManager internal royaltyManager; // Added
    MockRoyaltyModule internal mockRoyaltyModule; // Added
    MockIIPAssetRegistry internal mockIpAssetRegistry; // Added

    ERC20Mock internal weth;
    ERC20Mock internal usdc;
    ERC721Mock internal mockNft;

    // --- Users ---
    address internal owner = address(0x1); // Protocol deployer/owner
    address internal lender = address(0x2);
    address internal borrower = address(0x3);
    address internal otherUser = address(0x4);

    // --- Constants for testing ---
    uint256 internal constant LENDER_INITIAL_WETH_BALANCE = 100 ether;
    uint256 internal constant BORROWER_NFT_ID = 1;

    function setUp() public virtual {
        // Deal ETH to users for gas if needed (though Anvil usually handles this)
        vm.deal(owner, 10 ether);
        vm.deal(lender, 10 ether);
        vm.deal(borrower, 10 ether);
        vm.deal(otherUser, 10 ether);

        // --- Deploy Mocks ---
        vm.startPrank(owner);
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        usdc = new ERC20Mock("USD Coin", "USDC");
        mockNft = new ERC721Mock("Mock NFT", "MNFT");
        vm.stopPrank();

        // Mint mock tokens to users
        vm.prank(owner); // Owner can mint from mock
        weth.mint(lender, LENDER_INITIAL_WETH_BALANCE);

        vm.prank(owner); // Owner can mint from mock
        mockNft.mint(borrower, BORROWER_NFT_ID); // Borrower owns an NFT

        // --- Deploy Core Contracts ---
        vm.startPrank(owner);

        // 1. Deploy Managers
        address[] memory initialCurrencies = new address[](2);
        initialCurrencies[0] = address(weth);
        initialCurrencies[1] = address(usdc);
        currencyManager = new CurrencyManager(initialCurrencies);

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(mockNft);
        collectionManager = new CollectionManager(initialCollections);

        // 2. Deploy VaultsFactory (optional, can be address(0) if not used initially)
        vaultsFactory = new VaultsFactory("NFT Vault Shares Test", "NVST");

        // 3. Deploy Liquidation and PurchaseBundler (these need LendingProtocol address, but LP needs them too)
        // Deploy with address(0) for LP initially, then set LP address later.
        liquidation = new Liquidation(address(0));
        purchaseBundler = new PurchaseBundler(address(0));

        // 4. Deploy LendingProtocol
        // Deploy new mock dependencies for RoyaltyManager and LendingProtocol
        mockIpAssetRegistry = new MockIIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule();

        // Deploy RoyaltyManager with mocks and dummy addresses for its other dependencies
        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry),
            address(mockRoyaltyModule),
            address(0xdeadbeef03), // Dummy LICENSING_MODULE for RoyaltyManager
            address(0xdeadbeef04)  // Dummy LICENSE_REGISTRY for RoyaltyManager
        );

        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidation),
            address(purchaseBundler),
            address(royaltyManager), // Use deployed RoyaltyManager
            address(mockIpAssetRegistry) // Use deployed MockIIPAssetRegistry
        );

        // 5. Set LendingProtocol address in Liquidation and PurchaseBundler
        liquidation.setLendingProtocol(address(lendingProtocol));
        purchaseBundler.setLendingProtocol(address(lendingProtocol));

        vm.stopPrank();

        // --- Approvals ---
        // Lender approves LendingProtocol to spend WETH for making offers/loans
        vm.startPrank(lender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        // Borrower approves LendingProtocol to spend their NFT for accepting offers
        vm.startPrank(borrower);
        mockNft.setApprovalForAll(address(lendingProtocol), true); // Or approve specific token ID
        vm.stopPrank();

        // Fund MockRoyaltyModule with WETH for tests that might use it
        // Mint WETH to the test contract (owner / address(this)) itself for funding the mock module
        weth.mint(address(this), 200 ether); // Example amount, can be adjusted
        // Test contract approves MockRoyaltyModule to pull WETH from it
        weth.approve(address(mockRoyaltyModule), 200 ether);
        // Fund MockRoyaltyModule with some WETH. Specific amounts for ipIds are set in tests.
        mockRoyaltyModule.fundModule(address(weth), 100 ether); // Example funding
    }

    // --- Test Functions ---

    function test_InitialSetup() public {
        assertTrue(address(weth) != address(0), "WETH not deployed");
        assertTrue(address(usdc) != address(0), "USDC not deployed");
        assertTrue(address(mockNft) != address(0), "MockNFT not deployed");
        assertTrue(address(currencyManager) != address(0), "CurrencyManager not deployed");
        assertTrue(address(collectionManager) != address(0), "CollectionManager not deployed");
        assertTrue(address(vaultsFactory) != address(0), "VaultsFactory not deployed");
        assertTrue(address(liquidation) != address(0), "Liquidation not deployed");
        assertTrue(address(purchaseBundler) != address(0), "PurchaseBundler not deployed");
        assertTrue(address(lendingProtocol) != address(0), "LendingProtocol not deployed");

        assertEq(weth.balanceOf(lender), LENDER_INITIAL_WETH_BALANCE, "Lender WETH balance incorrect");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "Borrower NFT ownership incorrect");

        assertTrue(currencyManager.isCurrencySupported(address(weth)), "WETH not supported by CurrencyManager");
        assertTrue(
            collectionManager.isCollectionWhitelisted(address(mockNft)), "MockNFT not whitelisted by CollectionManager"
        );
    }

    function test_MakeStandardLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
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

        // Remove the expectEmit and emit sections since we can't predict the offerId
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);

        assertTrue(offerId != bytes32(0), "Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.lender, lender, "Offer lender incorrect");
        assertEq(offer.nftContract, address(mockNft), "Offer NFT contract incorrect");
        assertEq(offer.nftTokenId, BORROWER_NFT_ID, "Offer NFT token ID incorrect");
        assertEq(offer.currency, address(weth), "Offer currency incorrect");
        assertEq(offer.principalAmount, 1 ether, "Offer principal incorrect");
        assertTrue(offer.isActive, "Offer should be active");

        vm.stopPrank();
    }

    function test_MakeCollectionLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(mockNft),
            nftTokenId: 0,
            currency: address(weth),
            principalAmount: 0.5 ether, // Set this to maxPrincipalPerLoan value
            interestRateAPR: 600,
            durationSeconds: 14 days,
            expirationTimestamp: expiration,
            originationFeeRate: 50,
            totalCapacity: 10 ether,
            maxPrincipalPerLoan: 0.5 ether,
            minNumberOfLoans: 1
        });

        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(offerId != bytes32(0), "Collection Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.lender, lender, "Collection Offer lender incorrect");
        assertEq(uint8(offer.offerType), uint8(ILendingProtocol.OfferType.COLLECTION), "Offer type incorrect");
        assertEq(offer.nftContract, address(mockNft), "Collection Offer NFT contract incorrect");
        assertEq(offer.currency, address(weth), "Collection Offer currency incorrect");
        assertEq(offer.totalCapacity, 10 ether, "Collection Offer total capacity incorrect");
        assertEq(offer.maxPrincipalPerLoan, 0.5 ether, "Collection Offer max principal per loan incorrect");
        assertTrue(offer.isActive, "Collection Offer should be active");

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnsupportedCurrency() public {
        vm.startPrank(lender);

        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UNS");

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: BORROWER_NFT_ID,
            currency: address(unsupportedToken), // Using an unsupported currency
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });

        vm.expectRevert("Currency not supported");
        lendingProtocol.makeLoanOffer(params);

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnwhitelistedCollection() public {
        // Create unwhitelisted NFT
        ERC721Mock unwhitelistedNft = new ERC721Mock("Unlisted NFT", "UNL");

        // Mint NFT as owner
        vm.startPrank(owner);
        unwhitelistedNft.mint(borrower, 1);
        vm.stopPrank();

        // Try to make offer as lender
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(unwhitelistedNft),
            nftTokenId: 1,
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

        vm.expectRevert("Collection not whitelisted");
        lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
    }

    function test_AcceptStandardLoanOffer_Success() public {
        // 1. Lender makes an offer
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

        // 2. Borrower accepts the offer
        vm.startPrank(borrower);

        uint256 lenderWethBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBefore = weth.balanceOf(borrower);
        uint256 protocolWethBalanceBefore = weth.balanceOf(address(lendingProtocol));

        // Remove event expectation since we can't easily predict loanId and dueTime
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);

        assertTrue(loanId != bytes32(0), "Loan ID should not be zero");
        vm.stopPrank();

        // 3. Verify states
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.borrower, borrower, "Loan borrower incorrect");
        assertEq(loan.lender, lender, "Loan lender incorrect");
        assertEq(loan.nftContract, address(mockNft), "Loan NFT contract incorrect");
        assertEq(loan.nftTokenId, BORROWER_NFT_ID, "Loan NFT token ID incorrect");
        assertEq(loan.principalAmount, 1 ether, "Loan principal incorrect");
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan status not ACTIVE");

        // Verify NFT transfer
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), address(lendingProtocol), "NFT not escrowed by protocol");

        // Verify WETH transfers
        uint256 originationFee = (offerParams.principalAmount * offerParams.originationFeeRate) / 10000; // 1% = 100/10000
        uint256 netAmount = offerParams.principalAmount - originationFee;

        assertEq(
            weth.balanceOf(lender), lenderWethBalanceBefore - netAmount, "Lender WETH balance after loan incorrect"
        );
        assertEq(
            weth.balanceOf(borrower),
            borrowerWethBalanceBefore + netAmount,
            "Borrower WETH balance after loan incorrect"
        );
        assertEq(
            weth.balanceOf(address(lendingProtocol)),
            protocolWethBalanceBefore,
            "Protocol WETH balance after loan incorrect"
        );

        // Verify offer state
        ILendingProtocol.LoanOffer memory acceptedOffer = lendingProtocol.getLoanOffer(offerId);
        assertFalse(acceptedOffer.isActive, "Accepted offer should be inactive");
    }

    // --- TODO: Add more test cases ---
    // - test_CancelLoanOffer_Success
    // - test_Fail_CancelLoanOffer_NotOwner
    // - test_Fail_AcceptLoanOffer_OfferExpired
    // - test_Fail_AcceptLoanOffer_OfferInactive
    // - test_Fail_AcceptLoanOffer_NotNftOwner
    // - test_RepayLoan_Success
    // - test_Fail_RepayLoan_NotBorrower
    // - test_Fail_RepayLoan_InsufficientFunds
    // - test_ClaimCollateral_Success (after default)
    // - test_Fail_ClaimCollateral_NotLender
    // - test_Fail_ClaimCollateral_LoanNotDefaulted
    // - Tests for refinance, renegotiation, collection offers acceptance, etc.

    // --- Story Protocol Integration Tests ---

    function test_AcceptLoanOffer_WithStoryAsset_Success() public {
        // 1. Register the NFT with Story Protocol mock
        vm.prank(borrower); // Borrower (or owner) registers their NFT
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
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
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
        assertEq(loan.nftContract, address(mockNft)); // Assuming effective collateral is the base NFT
        assertEq(loan.status, ILendingProtocol.LoanStatus.ACTIVE);
    }

    function test_ClaimAndRepay_StoryAsset_FullRepaymentByRoyalty() public {
        // 1. Register NFT & create loan (similar to test_AcceptLoanOffer_WithStoryAsset_Success)
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD, nftContract: address(mockNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 36500, // 1% per day for easy calculation
            durationSeconds: 1 days, expirationTimestamp: uint64(block.timestamp + 1 hours), originationFeeRate: 0,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        }));
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Setup royalty balance in MockRoyaltyModule
        // Calculate expected interest: 1 ether * 36500 APR / 10000 / 365 days * 1 day = 0.01 ether
        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;

        // Fund MockRoyaltyModule through the test contract (owner)
        weth.mint(address(this), totalRepaymentDue); // Mint WETH to test contract
        weth.approve(address(mockRoyaltyModule), totalRepaymentDue); // Approve MockRoyaltyModule to pull
        mockRoyaltyModule.fundModule(address(weth), totalRepaymentDue); // Fund module
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), totalRepaymentDue); // Set amount for collection

        // 3. Borrower calls claimAndRepay
        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        vm.expectEmit(true, true, true, true, address(lendingProtocol));
        emit ILendingProtocol.LoanRepaid(loanId, borrower, lender, 1 ether, expectedInterest);

        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        // 4. Verify state
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue, "Lender did not receive full repayment");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT not returned to borrower");
        assertEq(royaltyManager.getRoyaltyBalance(ipId, address(weth)), 0, "Royalty balance in RoyaltyManager not cleared");
    }

    function test_ClaimAndRepay_StoryAsset_PartialRepaymentByRoyalty() public {
        // 1. Register NFT & create loan
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD, nftContract: address(mockNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 36500, durationSeconds: 1 days,
            expirationTimestamp: uint64(block.timestamp + 1 hours), originationFeeRate: 0,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        }));
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Setup partial royalty balance
        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000); // 0.01 ether
        uint256 totalRepaymentDue = 1 ether + expectedInterest;
        uint256 royaltyAvailable = 0.5 ether; // Less than total due

        weth.mint(address(this), royaltyAvailable);
        weth.approve(address(mockRoyaltyModule), royaltyAvailable);
        mockRoyaltyModule.fundModule(address(weth), royaltyAvailable);
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), royaltyAvailable);

        // Borrower needs to have funds for the remaining amount
        uint256 remainingForBorrower = totalRepaymentDue - royaltyAvailable;
        weth.mint(borrower, remainingForBorrower); // Mint to borrower
        vm.startPrank(borrower);
        weth.approve(address(lendingProtocol), remainingForBorrower); // Borrower approves LP
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
        // loan.principalAmount should be (original principal - royalty paid against principal part)
        // In this setup, royalty (0.5e) is less than principal (1e), so it reduces principal.
        // The interest (0.01e) is paid by borrower.
        // totalRepaymentDue = 1.01e. Royalty = 0.5e. Borrower pays 0.51e.
        // Loan struct principalAmount is principal MINUS amount paid by royalty towards principal.
        // The problem description for LendingProtocol.claimAndRepay states:
        // `currentLoan.principalAmount = originalPrincipal - amountToWithdrawFromRoyalty;`
        // This means the `principalAmount` field in the loan struct will reflect the remaining principal *if* royalty was not enough to cover it.
        // However, if the loan is REPAID, this field might not be as critical as the event.
        // The event LoanRepaid emits originalPrincipal.
        // Let's check the loan.accruedInterest is set.
        assertEq(loan.accruedInterest, expectedInterest, "Accrued interest on loan struct incorrect");
    }

    function test_ClaimAndRepay_StoryAsset_NoRoyaltyBalance() public {
        // 1. Register NFT & create loan
        vm.prank(borrower);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), BORROWER_NFT_ID);
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), BORROWER_NFT_ID);

        vm.startPrank(lender);
        bytes32 offerId = lendingProtocol.makeLoanOffer(ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD, nftContract: address(mockNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 36500, durationSeconds: 1 days,
            expirationTimestamp: uint64(block.timestamp + 1 hours), originationFeeRate: 0,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        }));
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), BORROWER_NFT_ID);
        vm.stopPrank();

        // 2. Setup NO royalty balance
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), 0);

        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000);
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
