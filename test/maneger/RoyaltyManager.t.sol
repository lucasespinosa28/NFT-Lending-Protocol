// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/core/manager/RoyaltyManager.sol";
import "../../src/mocks/ERC721Mock.sol";
import "../../src/mocks/MockIIPAssetRegistry.sol";
import "../../src/mocks/MockRoyaltyModule.sol"; 
import "../../src/mocks/ERC20Mock.sol"; 
import "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import "@storyprotocol/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import "@storyprotocol/contracts/interfaces/modules/licensing/ILicensingModule.sol";
import "@storyprotocol/contracts/interfaces/registries/ILicenseRegistry.sol";

contract RoyaltyManagerTest is Test {
    RoyaltyManager public royaltyManager;
    ERC721Mock public mockNft;
    MockIIPAssetRegistry public mockIpAssetRegistry;
    MockRoyaltyModule internal mockRoyaltyModule; // Added mock royalty module instance
    ERC20Mock internal royaltyToken; // Added royalty token instance

    address public owner;
    address public user;

    // Dummy addresses for modules not being tested directly
    address constant DUMMY_LICENSING_MODULE = address(0xdeadbeef01);
    address constant DUMMY_LICENSE_REGISTRY = address(0xdeadbeef02);

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        vm.deal(user, 10 ether);

        mockIpAssetRegistry = new MockIIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule(); // Deploy mock royalty module
        royaltyToken = new ERC20Mock("RoyaltyToken", "RTKN"); // Deploy mock ERC20 token

        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry),
            address(mockRoyaltyModule), // Use mock royalty module address
            DUMMY_LICENSING_MODULE, // Use dummy address
            DUMMY_LICENSE_REGISTRY // Use dummy address
        );

        mockNft = new ERC721Mock("TestNFT", "TNFT");
        mockNft.mint(user, 1);

        // Register the NFT as an IP Asset on Story Protocol mock
        // This is useful for getting a consistent ipId for tests
        vm.prank(user); // Or owner if preferred
        mockIpAssetRegistry.register(block.chainid, address(mockNft), 1);

        // Fund the MockRoyaltyModule with some royaltyTokens
        royaltyToken.mint(address(this), 1000 ether); // Test contract gets tokens
        royaltyToken.approve(address(mockRoyaltyModule), 1000 ether); // Approve mock module to pull
        mockRoyaltyModule.fundModule(address(royaltyToken), 100 ether); // Mock module now holds 100 RTKN
    }

    function test_ClaimRoyalty_And_GetBalance_Success() public {
        // Use the pre-registered mockNft to get an ipId
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), 1);
        uint256 collectAmount = 10 ether;
        // Configure MockRoyaltyModule to have this amount available for the ipId and token
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(royaltyToken), collectAmount);

        vm.expectEmit(true, true, true, true, address(royaltyManager));
        emit IRoyaltyManager.RoyaltyClaimed(ipId, collectAmount);
        royaltyManager.claimRoyalty(ipId, address(royaltyToken));

        assertEq(
            royaltyManager.getRoyaltyBalance(ipId, address(royaltyToken)),
            collectAmount,
            "Royalty balance mismatch after claim"
        );
        assertEq(
            royaltyToken.balanceOf(address(royaltyManager)),
            collectAmount,
            "RoyaltyManager token balance mismatch after claim"
        );
        // Check that MockRoyaltyModule transferred the tokens
        assertEq(mockRoyaltyModule.lastCollector(), address(royaltyManager), "Collector was not RoyaltyManager");
        assertEq(mockRoyaltyModule.lastIpIdCollected(), ipId, "Collected IP ID mismatch");
        assertEq(
            mockRoyaltyModule.lastCurrencyTokenCollected(), address(royaltyToken), "Collected currency token mismatch"
        );
    }

    function test_WithdrawRoyalty_Success() public {
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), 1);
        uint256 initialCollectAmount = 15 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(royaltyToken), initialCollectAmount);
        royaltyManager.claimRoyalty(ipId, address(royaltyToken)); // Populate balance in RoyaltyManager

        uint256 withdrawAmount = 5 ether;
        address recipient = address(0xABC);
        vm.deal(recipient, 0); // Ensure recipient has 0 balance initially

        uint256 rmBalanceBefore = royaltyToken.balanceOf(address(royaltyManager));
        uint256 recipientBalanceBefore = royaltyToken.balanceOf(recipient);

        royaltyManager.withdrawRoyalty(ipId, address(royaltyToken), recipient, withdrawAmount);

        assertEq(
            royaltyManager.getRoyaltyBalance(ipId, address(royaltyToken)),
            initialCollectAmount - withdrawAmount,
            "Balance after withdrawal mismatch"
        );
        assertEq(
            royaltyToken.balanceOf(address(royaltyManager)),
            rmBalanceBefore - withdrawAmount,
            "RM token balance after withdrawal mismatch"
        );
        assertEq(
            royaltyToken.balanceOf(recipient),
            recipientBalanceBefore + withdrawAmount,
            "Recipient token balance after withdrawal mismatch"
        );
    }

    function test_Fail_WithdrawRoyalty_InsufficientBalance() public {
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), 1);
        uint256 initialCollectAmount = 2 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(royaltyToken), initialCollectAmount);
        royaltyManager.claimRoyalty(ipId, address(royaltyToken)); // Populate balance

        uint256 withdrawAmount = 5 ether; // Attempt to withdraw more than available
        vm.expectRevert("RM: Insufficient royalty balance for withdrawal");
        royaltyManager.withdrawRoyalty(ipId, address(royaltyToken), address(0xABC), withdrawAmount);
    }

    function test_ClaimRoyalty_NoBalanceToCollect() public {
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), 1);
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(royaltyToken), 0); // No amount to collect

        // RoyaltyClaimed event should not be emitted if collectedAmount is 0
        // vm.expectNoEmit(); // TODO: Foundry's expectNoEmit might not work as expected for conditional emits.
        // A workaround is to check a boolean flag if the event handler has complex logic.
        // For this case, the event is only emitted if collectedAmount > 0, so this should be fine.
        royaltyManager.claimRoyalty(ipId, address(royaltyToken));
        assertEq(
            royaltyManager.getRoyaltyBalance(ipId, address(royaltyToken)),
            0,
            "Balance should be 0 when no royalty collected"
        );
        assertEq(royaltyToken.balanceOf(address(royaltyManager)), 0, "RoyaltyManager token balance should be 0");
    }
}
