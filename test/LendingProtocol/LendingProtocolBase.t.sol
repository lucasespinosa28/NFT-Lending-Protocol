// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

// Core contracts
import {LendingProtocol} from "../../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../../src/core/CurrencyManager.sol";
import {CollectionManager} from "../../src/core/CollectionManager.sol";
import {VaultsFactory} from "../../src/core/VaultsFactory.sol";
import {Liquidation} from "../../src/core/Liquidation.sol";
import {PurchaseBundler} from "../../src/core/PurchaseBundler.sol";
import {RoyaltyManager} from "../../src/core/RoyaltyManager.sol";
import {MockRoyaltyModule} from "../../src/mocks/MockRoyaltyModule.sol";
import {MockIIPAssetRegistry} from "../../src/mocks/MockIIPAssetRegistry.sol";

// Interfaces
import {ILendingProtocol} from "../../src/interfaces/ILendingProtocol.sol";

// Mocks
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../../src/mocks/ERC721Mock.sol";

contract LendingProtocolBaseTest is Test {
    // --- State Variables ---
    LendingProtocol internal lendingProtocol;
    CurrencyManager internal currencyManager;
    CollectionManager internal collectionManager;
    VaultsFactory internal vaultsFactory;
    Liquidation internal liquidation;
    PurchaseBundler internal purchaseBundler;
    RoyaltyManager internal royaltyManager;
    MockRoyaltyModule internal mockRoyaltyModule;
    MockIIPAssetRegistry internal mockIpAssetRegistry;

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
}
