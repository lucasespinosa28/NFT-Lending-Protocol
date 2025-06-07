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
        collectionManager = new CollectionManager(owner,initialCollections);

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
            address(0xdeadbeef04) // Dummy LICENSE_REGISTRY for RoyaltyManager
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

    // Loan Offer related tests moved to test/core/logic/LoanOfferLogic.t.sol
    // - test_MakeStandardLoanOffer_Success
    // - test_MakeCollectionLoanOffer_Success
    // - test_Fail_MakeStandardLoanOffer_UnsupportedCurrency
    // - test_Fail_MakeStandardLoanOffer_UnwhitelistedCollection

    // test_AcceptStandardLoanOffer_Success moved to LoanManagementLogic.t.sol
    // test_AcceptLoanOffer_WithStoryAsset_Success moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_FullRepaymentByRoyalty moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_PartialRepaymentByRoyalty moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_NoRoyaltyBalance moved to LoanManagementLogic.t.sol

    // --- TODO: Add more test cases ---
    // - test_CancelLoanOffer_Success // Moved to LoanOfferLogic.t.sol
    // - test_Fail_CancelLoanOffer_NotOwner // Moved to LoanOfferLogic.t.sol
    // - test_Fail_AcceptLoanOffer_OfferExpired // Stays in LendingProtocol.t.sol (tests interaction)
    // - test_Fail_AcceptLoanOffer_OfferInactive // Stays in LendingProtocol.t.sol (tests interaction)
    // - test_Fail_AcceptLoanOffer_NotNftOwner // Stays in LendingProtocol.t.sol (tests interaction)
    // - test_RepayLoan_Success // In LoanManagementLogic.t.sol
    // - test_Fail_RepayLoan_NotBorrower // In LoanManagementLogic.t.sol
    // - test_Fail_RepayLoan_InsufficientFunds // In LoanManagementLogic.t.sol
    // - test_ClaimCollateral_Success (after default) // LML part in LML.t.sol, CollateralLogic part in CollateralLogic.t.sol
    // - test_Fail_ClaimCollateral_NotLender // LML/CollateralLogic tests
    // - test_Fail_ClaimCollateral_LoanNotDefaulted // LML/CollateralLogic tests
    // - Tests for refinance, renegotiation // In LoanManagementLogic.t.sol
    // - Tests for collateral sale functions (list, cancel, buy) // In CollateralLogic.t.sol

    // --- Story Protocol Integration Tests ---
    // test_AcceptLoanOffer_WithStoryAsset_Success moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_FullRepaymentByRoyalty moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_PartialRepaymentByRoyalty moved to LoanManagementLogic.t.sol
    // test_ClaimAndRepay_StoryAsset_NoRoyaltyBalance moved to LoanManagementLogic.t.sol
}
