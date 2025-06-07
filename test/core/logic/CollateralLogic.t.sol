// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";

// Protocol Core Contracts
import {LendingProtocol} from "../../../src/core/LendingProtocol.sol";
import {LoanOfferLogic} from "../../../src/core/logic/LoanOfferLogic.sol";
import {LoanManagementLogic} from "../../../src/core/logic/LoanManagementLogic.sol";
import {CollateralLogic} from "../../../src/core/logic/CollateralLogic.sol";
import {StoryIntegrationLogic} from "../../../src/core/logic/StoryIntegrationLogic.sol";

// Manager Contracts & Actual Implementations
import {CurrencyManager} from "../../../src/core/CurrencyManager.sol";
import {CollectionManager} from "../../../src/core/CollectionManager.sol";
import {VaultsFactory} from "../../../src/core/VaultsFactory.sol";
import {Liquidation} from "../../../src/core/Liquidation.sol";
import {PurchaseBundler} from "../../../src/core/PurchaseBundler.sol";
import {RoyaltyManager} from "../../../src/core/RoyaltyManager.sol";

// Interfaces
import "../../../src/interfaces/ILendingProtocol.sol"; // General import for structs/enums
import {IPurchaseBundler} from "../../../src/interfaces/IPurchaseBundler.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";


// Mocks
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol";
import {MockRoyaltyModule} from "../../../src/mocks/MockRoyaltyModule.sol";
import {MockIPAssetRegistry} from "../../../src/mocks/MockIPAssetRegistry.sol";
// MockPurchaseBundler might be needed if we want to control its behavior directly.
// For now, using the actual PurchaseBundler as deployed by LendingProtocol's setup.

contract CollateralLogicTest is Test {
    // --- Constants ---
    uint256 internal constant DEFAULT_PRINCIPAL = 1 ether;
    uint256 internal constant DEFAULT_INTEREST_RATE_APR = 1000; // 10%
    uint256 internal constant DEFAULT_DURATION_SECONDS = 30 days;
    uint64 internal constant DEFAULT_EXPIRATION_TIMESTAMP_OFFSET = 7 days;
    uint256 internal constant DEFAULT_ORIGINATION_FEE_RATE = 100; // 1%
    uint256 internal constant BORROWER_NFT_ID = 1;
    uint256 internal constant LENDER_INITIAL_WETH_BALANCE = 100 ether;
    uint256 internal constant BUYER_INITIAL_WETH_BALANCE = 200 ether;


    // --- Users ---
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal admin = makeAddr("admin");
    address internal buyer = makeAddr("buyer");
    address internal otherUser = makeAddr("otherUser");

    // --- Contracts ---
    LendingProtocol internal lendingProtocol;
    LoanOfferLogic internal loanOfferLogic;
    LoanManagementLogic internal loanManagementLogic;
    CollateralLogic internal collateralLogic;
    StoryIntegrationLogic internal storyIntegrationLogic;

    CurrencyManager internal currencyManager;
    CollectionManager internal collectionManager;
    VaultsFactory internal vaultsFactory;
    Liquidation internal liquidationContract;
    PurchaseBundler internal purchaseBundler; // Actual PurchaseBundler instance
    RoyaltyManager internal royaltyManager;
    MockIPAssetRegistry internal ipAssetRegistry;
    MockRoyaltyModule internal mockRoyaltyModule;

    // --- Mocks ---
    ERC20Mock internal weth;
    ERC721Mock internal testNft;

    function setUp() public virtual {
        vm.startPrank(admin);

        weth = new ERC20Mock("Wrapped Ether", "WETH");
        testNft = new ERC721Mock("Test NFT", "TNFT");

        ipAssetRegistry = new MockIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule();

        address[] memory initialCurrencies = new address[](1);
        initialCurrencies[0] = address(weth);
        currencyManager = new CurrencyManager(initialCurrencies);

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(testNft);
        collectionManager = new CollectionManager(admin, initialCollections);

        vaultsFactory = new VaultsFactory("TestVault", "TV");
        liquidationContract = new Liquidation(address(0));
        purchaseBundler = new PurchaseBundler(address(0)); // Deploy actual PurchaseBundler
        royaltyManager = new RoyaltyManager(
            address(ipAssetRegistry),
            address(mockRoyaltyModule),
            makeAddr("licensingModule"),
            makeAddr("licenseRegistry")
        );

        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidationContract),
            address(purchaseBundler), // Pass actual PurchaseBundler
            address(royaltyManager),
            address(ipAssetRegistry)
        );

        liquidationContract.setLendingProtocol(address(lendingProtocol));
        purchaseBundler.setLendingProtocol(address(lendingProtocol)); // Set LP address in actual PB

        vm.stopPrank();

        // Get deployed logic contract instances
        loanOfferLogic = lendingProtocol.loanOfferLogic();
        loanManagementLogic = lendingProtocol.loanManagementLogic();
        storyIntegrationLogic = lendingProtocol.storyIntegrationLogic();
        collateralLogic = lendingProtocol.collateralLogic();


        // Fund users
        weth.mint(lender, LENDER_INITIAL_WETH_BALANCE);
        weth.mint(borrower, DEFAULT_PRINCIPAL * 3); // For loan repayment, etc.
        weth.mint(buyer, BUYER_INITIAL_WETH_BALANCE); // For buyCollateralAndRepay tests
        testNft.mint(borrower, BORROWER_NFT_ID);

        // Approvals
        vm.startPrank(lender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower);
        testNft.setApprovalForAll(address(lendingProtocol), true);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(buyer);
        weth.approve(address(lendingProtocol), type(uint256).max); // Buyer approves LP for funds
        vm.stopPrank();
    }

    // Helper function to make a standard loan offer
    function _makeOffer(address _lender, uint256 _principal, uint256 _nftTokenId) internal returns (bytes32 offerId) {
        vm.startPrank(_lender);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(testNft),
            nftTokenId: _nftTokenId,
            currency: address(weth),
            principalAmount: _principal,
            interestRateAPR: DEFAULT_INTEREST_RATE_APR,
            durationSeconds: DEFAULT_DURATION_SECONDS,
            expirationTimestamp: uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET),
            originationFeeRate: DEFAULT_ORIGINATION_FEE_RATE,
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        offerId = lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
    }

    // Helper function to create an active loan
    function _createActiveLoan() internal returns (bytes32 loanId, bytes32 offerId) {
        offerId = _makeOffer(lender, DEFAULT_PRINCIPAL, BORROWER_NFT_ID);
        vm.startPrank(borrower);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();
    }

    // Test functions will be added here
    // For now, focusing on setup and structure.
    // If LendingProtocol.t.sol has specific tests for these collateral functions, they will be moved.
    // Otherwise, new tests will need to be written later.

    function test_PlaceholderForCollateralLogic() public {
        assertTrue(true, "Placeholder test for CollateralLogic.t.sol");
    }
}
