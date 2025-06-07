// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

// Protocol Core Contracts
import {LendingProtocol} from "../../../src/core/LendingProtocol.sol";
import {LoanOfferLogic} from "../../../src/core/logic/LoanOfferLogic.sol";

// Manager Contracts are in src/core/ as per LendingProtocol.t.sol
import {CurrencyManager} from "../../../src/core/CurrencyManager.sol";
import {CollectionManager} from "../../../src/core/CollectionManager.sol";

// Interfaces
import "../../../src/interfaces/ILendingProtocol.sol"; // General import

// Mocks & Test Utilities
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol";
import {MockRoyaltyModule} from "../../../src/mocks/MockRoyaltyModule.sol";
import {MockIPAssetRegistry} from "../../../src/mocks/MockIPAssetRegistry.sol";
// Actual contracts will be used instead of these mocks, matching LendingProtocol.t.sol setup
// import {MockPurchaseBundler} from "../../../src/mocks/MockPurchaseBundler.sol";
// import {MockVaultsFactory} from "../../../src/mocks/MockVaultsFactory.sol";
// import {MockLiquidation} from "../../../src/mocks/MockLiquidation.sol";

// Actual contracts that were being mocked unnecessarily for this test setup
import {PurchaseBundler} from "../../../src/core/PurchaseBundler.sol";
import {VaultsFactory} from "../../../src/core/VaultsFactory.sol";
import {Liquidation} from "../../../src/core/Liquidation.sol";


contract LoanOfferLogicTest is Test { // Removed StdCheats as Test usually includes it
    // --- Constants ---
    uint256 internal constant DEFAULT_PRINCIPAL = 100 ether;
    uint256 internal constant DEFAULT_INTEREST_RATE_APR = 1000; // 10%
    uint256 internal constant DEFAULT_DURATION_SECONDS = 30 days;
    uint64 internal constant DEFAULT_EXPIRATION_TIMESTAMP_OFFSET = 7 days;
    uint256 internal constant DEFAULT_ORIGINATION_FEE_RATE = 100; // 1%
    uint256 internal constant BORROWER_NFT_ID = 1;


    // --- Users ---
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal admin = makeAddr("admin"); // Used as deployer of core infrastructure
    address internal otherUser = makeAddr("otherUser");

    // --- Contracts ---
    LendingProtocol internal lendingProtocol;
    LoanOfferLogic internal loanOfferLogic; // Instance obtained from lendingProtocol

    CurrencyManager internal currencyManager;
    CollectionManager internal collectionManager;
    MockIPAssetRegistry internal ipAssetRegistry;


    // --- Mocks ---
    ERC20Mock internal weth;
    ERC20Mock internal usdc;
    ERC721Mock internal testNft; // Standard NFT for specific offers
    ERC721Mock internal collectionNft; // For collection offers

    function setUp() public virtual {
        vm.startPrank(admin);
        // Deploy Mocks first
        weth = new ERC20Mock("Wrapped Ether", "WETH"); // Decimals default to 18 in OZ ERC20
        usdc = new ERC20Mock("USD Coin", "USDC");     // This will also default to 18, not 6. Test amounts may need adjustment.

        // Deploy CurrencyManager
        address[] memory initialCurrencies = new address[](2);
        initialCurrencies[0] = address(weth);
        initialCurrencies[1] = address(usdc);
        currencyManager = new CurrencyManager(initialCurrencies);
        // currencyManager.addCurrency calls removed as they are part of constructor and had wrong signature

        // Deploy CollectionManager
        // CollectionManager constructor: address _owner, address[] memory _initialCollections
        // The read file for LendingProtocol.t.sol shows: collectionManager = new CollectionManager(owner,initialCollections);
        // For LoanOfferLogic.t.sol, admin is the owner/deployer of managers.
        address[] memory initialCollections = new address[](2); // For testNft and collectionNft
        testNft = new ERC721Mock("Test NFT", "TNFT");
        collectionNft = new ERC721Mock("Collection NFT", "CNFT");
        initialCollections[0] = address(testNft);
        initialCollections[1] = address(collectionNft);
        collectionManager = new CollectionManager(admin, initialCollections); // admin is owner
        // collectionManager.addCollection calls removed as they are part of constructor logic or need onlyOwner if called post-construction.
        // For whitelisting, CollectionManager's constructor in this version adds them if _initialCollections is used.
        // If addCollection is used post-deployment, it's onlyOwner (admin).
        // The original LendingProtocol.t.sol used `new CollectionManager(owner,initialCollections);`
        // We need to ensure these collections are indeed whitelisted. The constructor does this.

        ipAssetRegistry = new MockIPAssetRegistry();

        // Deploy LendingProtocol (which deploys LoanOfferLogic)
        // For LoanOfferLogic tests, we might not need fully functional VaultsFactory, Liquidation, PurchaseBundler
        // if LOL doesn't directly interact with them. LP constructor needs them.
        // Let's deploy the actual ones as LendingProtocol.t.sol does.
        VaultsFactory _vaultsFactory = new VaultsFactory("TestVault", "TV"); // name, symbol
        Liquidation _liquidation = new Liquidation(address(0)); // Needs LP address later
        PurchaseBundler _purchaseBundler = new PurchaseBundler(address(0)); // Needs LP address later

        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(_vaultsFactory),
            address(_liquidation),
            address(_purchaseBundler),
            address(new MockRoyaltyModule()), // Still using mock for this as it's simpler
            address(ipAssetRegistry)
        );

        // Set LP address in contracts that need it (if setUp was for them)
        // _liquidation.setLendingProtocol(address(lendingProtocol));
        // _purchaseBundler.setLendingProtocol(address(lendingProtocol));

        vm.stopPrank();

        // Get the deployed LoanOfferLogic instance from LendingProtocol
        loanOfferLogic = lendingProtocol.loanOfferLogic();

        // Fund users
        weth.mint(lender, 1000 ether);
        usdc.mint(lender, 10000 * 10**6);

        // Approve LendingProtocol for lender's tokens
        vm.startPrank(lender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        usdc.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        // Mint NFTs
        testNft.mint(borrower, BORROWER_NFT_ID);
        collectionNft.mint(borrower, 1);
        collectionNft.mint(borrower, 2);
    }

    // --- Loan Offer Creation Tests ---

    function test_MakeStandardLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(testNft),
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

        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(offerId != bytes32(0), "Offer ID should not be zero");

        // Fetch offer directly from LoanOfferLogic to verify state
        ILendingProtocol.LoanOffer memory offer = loanOfferLogic.getLoanOffer(offerId); // Qualified name
        assertEq(offer.lender, lender, "Offer lender incorrect");
        assertEq(offer.nftContract, address(testNft), "Offer NFT contract incorrect");
        assertEq(offer.nftTokenId, BORROWER_NFT_ID, "Offer NFT token ID incorrect");
        assertEq(offer.currency, address(weth), "Offer currency incorrect");
        assertEq(offer.principalAmount, 1 ether, "Offer principal incorrect");
        assertTrue(offer.isActive, "Offer should be active");

        vm.stopPrank();
    }

    function test_MakeCollectionLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.COLLECTION, // Qualified name
            nftContract: address(collectionNft), // Target the collection
            nftTokenId: 0, // Not applicable for collection offers
            currency: address(weth),
            principalAmount: 0, // For collection offer, this is effectively maxPrincipalPerLoan if totalCapacity = maxPrincipalPerLoan
            interestRateAPR: 600,
            durationSeconds: 14 days,
            expirationTimestamp: expiration,
            originationFeeRate: 50,
            totalCapacity: 10 ether,
            maxPrincipalPerLoan: 1 ether, // Max principal for any single loan against this offer
            minNumberOfLoans: 1 // Optional: minimum number of loans to activate this (not strictly enforced here)
        });
        // In collection offers, principalAmount in OfferParams is often set to maxPrincipalPerLoan or 0 if totalCapacity is the main funding limit per loan.
        // Let's assume principalAmount in the LoanOffer struct gets populated by maxPrincipalPerLoan for clarity in getLoanOffer.
        // The actual principal for a loan taken against a collection offer is determined at acceptance time, up to maxPrincipalPerLoan.

        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(offerId != bytes32(0), "Collection Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = loanOfferLogic.getLoanOffer(offerId); // Qualified name
        assertEq(offer.lender, lender, "Collection Offer lender incorrect");
        assertEq(uint8(offer.offerType), uint8(ILendingProtocol.OfferType.COLLECTION), "Offer type incorrect"); // Qualified name
        assertEq(offer.nftContract, address(collectionNft), "Collection Offer NFT contract incorrect");
        assertEq(offer.currency, address(weth), "Collection Offer currency incorrect");
        assertEq(offer.totalCapacity, 10 ether, "Collection Offer total capacity incorrect");
        assertEq(offer.maxPrincipalPerLoan, 1 ether, "Collection Offer max principal per loan incorrect");
        // For collection offers, offer.principalAmount might represent the max per loan or be 0.
        // Based on current LoanOfferLogic.makeLoanOffer, it uses params.principalAmount.
        // If params.principalAmount was 0 for collection offer, then offer.principalAmount will be 0.
        assertEq(offer.principalAmount, 0, "Collection offer's base principalAmount should be 0 or reflect maxPerLoan based on convention");
        assertTrue(offer.isActive, "Collection Offer should be active");

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnsupportedCurrency() public {
        vm.startPrank(lender);
        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UNS"); // Corrected: removed decimals argument

        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(testNft),
            nftTokenId: BORROWER_NFT_ID,
            currency: address(unsupportedToken),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });

        vm.expectRevert("Currency not supported"); // This revert comes from LoanOfferLogic
        lendingProtocol.makeLoanOffer(params);

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnwhitelistedCollection() public {
        vm.startPrank(admin); // Admin deploys new unwhitelisted NFT
        ERC721Mock unwhitelistedNft = new ERC721Mock("Unlisted NFT", "UNL");
        unwhitelistedNft.mint(borrower, 1);
        vm.stopPrank();

        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(unwhitelistedNft),
            nftTokenId: 1,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });

        vm.expectRevert("Collection not whitelisted"); // This revert comes from LoanOfferLogic
        lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
    }

    // --- Loan Offer Cancellation Tests ---

    function test_CancelLoanOffer_Success() public {
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(testNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 500,
            durationSeconds: 7 days, expirationTimestamp: expiration, originationFeeRate: 100,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(loanOfferLogic.getLoanOffer(offerId).isActive, "Offer should be active initially");
        vm.stopPrank();

        vm.startPrank(lender); // Lender cancels their own offer
        lendingProtocol.cancelLoanOffer(offerId);
        vm.stopPrank();

        ILendingProtocol.LoanOffer memory offer = loanOfferLogic.getLoanOffer(offerId); // Qualified name
        assertFalse(offer.isActive, "Offer should be inactive after cancellation");
    }

    function test_Fail_CancelLoanOffer_NotOwner() public {
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(testNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 500,
            durationSeconds: 7 days, expirationTimestamp: expiration, originationFeeRate: 100,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();

        vm.startPrank(otherUser); // Different user tries to cancel
        vm.expectRevert("LP: Not offer owner"); // Revert expected from LendingProtocol before it calls LoanOfferLogic
        lendingProtocol.cancelLoanOffer(offerId);
        vm.stopPrank();

        assertTrue(loanOfferLogic.getLoanOffer(offerId).isActive, "Offer should still be active");
    }

     function test_Fail_CancelLoanOffer_AlreadyInactive() public {
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({ // Qualified name
            offerType: ILendingProtocol.OfferType.STANDARD, // Qualified name
            nftContract: address(testNft), nftTokenId: BORROWER_NFT_ID,
            currency: address(weth), principalAmount: 1 ether, interestRateAPR: 500,
            durationSeconds: 7 days, expirationTimestamp: expiration, originationFeeRate: 100,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        lendingProtocol.cancelLoanOffer(offerId); // First cancellation
        vm.stopPrank();

        vm.startPrank(lender);
        // LendingProtocol's cancelLoanOffer first checks if offer.lender == msg.sender via getLoanOffer.
        // Then it calls LoanOfferLogic.cancelLoanOffer(offerId, msg.sender).
        // LoanOfferLogic's cancelLoanOffer has `require(offer.isActive, "LOL: Offer not active");`
        vm.expectRevert("LOL: Offer not active");
        lendingProtocol.cancelLoanOffer(offerId); // Second cancellation
        vm.stopPrank();
    }


    // --- TODO: Add tests for other failure cases of makeLoanOffer ---
    // e.g., principal amount zero, duration zero, expiration in past
}


// Minimal mock for AddressProvider if needed by CurrencyManager's addCurrency
contract MockAddressProvider {
    address private _feed;
    constructor(address feed) { _feed = feed; }
    // Add other functions if CurrencyManager actually calls them. For now, assume it only needs an address.
}

// Minimal mock for RangeValidator if needed by CollectionManager
contract MockRangeValidator {
    address private _validator;
    constructor(address validator) { _validator = validator; }
}
