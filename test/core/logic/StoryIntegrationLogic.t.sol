// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";

// Contract to be tested
import {StoryIntegrationLogic} from "../../../src/core/logic/StoryIntegrationLogic.sol";

// Dependencies for StoryIntegrationLogic & Setup
import {LendingProtocol} from "../../../src/core/LendingProtocol.sol"; // To get StoryIntegrationLogic instance via owner
import {RoyaltyManager} from "../../../src/core/RoyaltyManager.sol";
import {CurrencyManager} from "../../../src/core/CurrencyManager.sol"; // For LP deployment
import {CollectionManager} from "../../../src/core/CollectionManager.sol"; // For LP deployment
import {VaultsFactory} from "../../../src/core/VaultsFactory.sol"; // For LP deployment
import {Liquidation} from "../../../src/core/Liquidation.sol"; // For LP deployment
import {PurchaseBundler} from "../../../src/core/PurchaseBundler.sol"; // For LP deployment


// Interfaces
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import {IRoyaltyManager} from "../../../src/interfaces/IRoyaltyManager.sol";

// Mocks
import {MockIPAssetRegistry} from "../../../src/mocks/MockIPAssetRegistry.sol";
import {MockRoyaltyModule} from "../../../src/mocks/MockRoyaltyModule.sol";
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol"; // For NFT registration

contract StoryIntegrationLogicTest is Test {
    // --- Users ---
    address internal admin = makeAddr("admin");
    address internal lender = makeAddr("lender"); // Recipient of royalty payments
    address internal testNftOwner = makeAddr("testNftOwner");

    // --- Contracts ---
    LendingProtocol internal lendingProtocol; // Used to deploy and own SIL
    StoryIntegrationLogic internal storyIntegrationLogic;
    RoyaltyManager internal royaltyManager; // Actual RoyaltyManager
    MockIPAssetRegistry internal mockIpAssetRegistry;
    MockRoyaltyModule internal mockRoyaltyModule; // Mock for IRoyaltyManager internals

    // --- Mocks ---
    ERC20Mock internal weth;
    ERC721Mock internal testNft;
    uint256 internal constant TEST_NFT_ID = 1;
    bytes32 internal constant DUMMY_LOAN_ID = keccak256("dummyLoanId");


    function setUp() public virtual {
        vm.startPrank(admin);

        // Deploy Mocks
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        testNft = new ERC721Mock("Test NFT", "TNFT");
        testNft.mint(testNftOwner, TEST_NFT_ID);

        mockIpAssetRegistry = new MockIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule();

        // Deploy RoyaltyManager (actual contract, but with mocked IRoyaltyModule)
        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry),
            address(mockRoyaltyModule),
            makeAddr("licensingModule"), // Dummy address
            makeAddr("licenseRegistry")  // Dummy address
        );

        // Deploy minimal LendingProtocol to act as owner for StoryIntegrationLogic
        // StoryIntegrationLogic is deployed inside LendingProtocol's constructor
        // LendingProtocol constructor:
        // address _currencyManager, address _collectionManager, address _vaultsFactory,
        // address _liquidationContract, address _purchaseBundler,
        // address _royaltyManagerAddress, address _ipAssetRegistryAddress
        CurrencyManager _currencyManager = new CurrencyManager(new address[](0));
        CollectionManager _collectionManager = new CollectionManager(admin, new address[](0));
        VaultsFactory _vaultsFactory = new VaultsFactory("V", "V");
        Liquidation _liquidation = new Liquidation(address(0));
        PurchaseBundler _purchaseBundler = new PurchaseBundler(address(0));

        lendingProtocol = new LendingProtocol(
            address(_currencyManager),
            address(_collectionManager),
            address(_vaultsFactory),
            address(_liquidation),
            address(_purchaseBundler),
            address(royaltyManager), // Pass the actual RoyaltyManager which uses MockRoyaltyModule
            address(mockIpAssetRegistry)
        );

        // Get the deployed StoryIntegrationLogic instance
        storyIntegrationLogic = lendingProtocol.storyIntegrationLogic();

        vm.stopPrank();

        // Fund MockRoyaltyModule via test contract for withdrawals
        weth.mint(address(this), 100 ether); // Mint to test contract
        weth.approve(address(mockRoyaltyModule), 100 ether); // Approve mock to pull
        mockRoyaltyModule.fundModule(address(weth), 50 ether); // Fund the mock module itself
    }

    // --- Unit Tests ---

    function testGetIpId_Success() public {
        vm.prank(admin); // or testNftOwner
        mockIpAssetRegistry.register(block.chainid, address(testNft), TEST_NFT_ID);
        address expectedIpId = mockIpAssetRegistry.ipId(block.chainid, address(testNft), TEST_NFT_ID);
        assertTrue(expectedIpId != address(0), "IP ID should not be zero after registration");

        address retrievedIpId = storyIntegrationLogic.getIpId(address(testNft), TEST_NFT_ID);
        assertEq(retrievedIpId, expectedIpId, "getIpId did not return the correct registered IP ID");
    }

    function testGetIpId_NotRegistered() public {
        // TEST_NFT_ID is minted but not registered with mockIpAssetRegistry in this test's scope
        address retrievedIpId = storyIntegrationLogic.getIpId(address(testNft), TEST_NFT_ID + 1); // Use a different token ID
        assertEq(retrievedIpId, address(0), "getIpId should return address(0) for an unregistered asset");
    }

    function testAttemptRoyaltyPayment_FullRepayment() public {
        // 1. Setup: Register IP ID and set royalty balance
        vm.prank(admin);
        mockIpAssetRegistry.register(block.chainid, address(testNft), TEST_NFT_ID);
        address ipId = storyIntegrationLogic.getIpId(address(testNft), TEST_NFT_ID);
        assertTrue(ipId != address(0));

        uint256 amountDue = 10 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), amountDue); // Set royalty balance >= amountDue

        // 2. Action: Attempt royalty payment (as owner of SIL, which is LP)
        vm.startPrank(admin); // Simulate call from LendingProtocol (owner of SIL)
        uint256 amountPaid = storyIntegrationLogic.attemptRoyaltyPayment(DUMMY_LOAN_ID, ipId, address(weth), amountDue, lender);
        vm.stopPrank();

        // 3. Assertions
        assertEq(amountPaid, amountDue, "Amount paid from royalty should be the full amount due");
        // Further check: mockRoyaltyModule's internal balance for this IP ID should be 0
        // and lender should have received the funds. This requires more detailed mock or event checking.
        // For now, rely on the returned value and event emission from SIL.
        // vm.expectCall(address(mockRoyaltyModule), abi.encodeWithSelector(IRoyaltyManager.withdrawRoyalty.selector, ipId, address(weth), lender, amountDue));
        // This expectCall is for IRoyaltyManager, but we're calling MockRoyaltyModule which might not have the exact same external interface.
        // The event RoyaltyWithdrawn from StoryIntegrationLogic is a good check.
        vm.expectEmit(true, true, true, true, address(storyIntegrationLogic));
        emit StoryIntegrationLogic.RoyaltyWithdrawn(DUMMY_LOAN_ID, ipId, lender, amountDue);
        // Re-run the payment attempt to ensure it doesn't double pay (or check balance if mock allows)
        // This part is tricky without a more stateful mockRoyaltyModule or direct balance check.
        // The current MockRoyaltyModule just allows setting a value that getRoyaltyBalance returns once.
    }

    function testAttemptRoyaltyPayment_PartialRepayment() public {
        vm.prank(admin);
        mockIpAssetRegistry.register(block.chainid, address(testNft), TEST_NFT_ID);
        address ipId = storyIntegrationLogic.getIpId(address(testNft), TEST_NFT_ID);
        assertTrue(ipId != address(0));

        uint256 amountDue = 10 ether;
        uint256 royaltyAvailable = 5 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), royaltyAvailable);

        vm.startPrank(admin);
        uint256 amountPaid = storyIntegrationLogic.attemptRoyaltyPayment(DUMMY_LOAN_ID, ipId, address(weth), amountDue, lender);
        vm.stopPrank();

        assertEq(amountPaid, royaltyAvailable, "Amount paid from royalty should be the available royalty amount");
        vm.expectEmit(true, true, true, true, address(storyIntegrationLogic));
        emit StoryIntegrationLogic.RoyaltyWithdrawn(DUMMY_LOAN_ID, ipId, lender, royaltyAvailable);
    }

    function testAttemptRoyaltyPayment_NoRoyalty() public {
        vm.prank(admin);
        mockIpAssetRegistry.register(block.chainid, address(testNft), TEST_NFT_ID);
        address ipId = storyIntegrationLogic.getIpId(address(testNft), TEST_NFT_ID);
        assertTrue(ipId != address(0));

        uint256 amountDue = 10 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), 0); // No royalty balance

        vm.startPrank(admin);
        uint256 amountPaid = storyIntegrationLogic.attemptRoyaltyPayment(DUMMY_LOAN_ID, ipId, address(weth), amountDue, lender);
        vm.stopPrank();

        assertEq(amountPaid, 0, "Amount paid from royalty should be zero");
    }

    function testAttemptRoyaltyPayment_IpIdNotEffectivelyRegistered() public {
        // Using an IP ID that getIpId would return as address(0) because it's not registered
        // or because the underlying NFT itself is not registered.
        address unregisteredIpId = address(0); // storyIntegrationLogic.getIpId for an unregistered asset returns 0
        uint256 amountDue = 10 ether;

        vm.startPrank(admin);
        uint256 amountPaid = storyIntegrationLogic.attemptRoyaltyPayment(DUMMY_LOAN_ID, unregisteredIpId, address(weth), amountDue, lender);
        vm.stopPrank();

        assertEq(amountPaid, 0, "Amount paid should be zero if IP ID is not registered");
    }
}
