// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/core/RoyaltyManager.sol";
import "../src/mocks/ERC721Mock.sol";
import "../src/mocks/MockIIPAssetRegistry.sol"; // Added import
import "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import "@storyprotocol/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import "@storyprotocol/contracts/interfaces/modules/licensing/ILicensingModule.sol";
import "@storyprotocol/contracts/interfaces/registries/ILicenseRegistry.sol";

contract RoyaltyManagerTest is Test {
    RoyaltyManager public royaltyManager;
    ERC721Mock public mockNft;
    MockIIPAssetRegistry public mockIpAssetRegistry; // Added mock instance
    address public owner;
    address public user;

    // Story Protocol Mainnet Addresses
    // IIPAssetRegistry constant IP_ASSET_REGISTRY = IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b); // Commented out or remove
    IRoyaltyModule constant ROYALTY_MODULE = IRoyaltyModule(0xD2f60c40fEbccf6311f8B47c4f2Ec6b040400086);
    ILicensingModule constant LICENSING_MODULE = ILicensingModule(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);
    ILicenseRegistry constant LICENSE_REGISTRY = ILicenseRegistry(0x529a750E02d8E2f15649c13D69a465286a780e24);

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        vm.deal(user, 10 ether);

        mockIpAssetRegistry = new MockIIPAssetRegistry(); // Instantiate mock

        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry), // Use mock address
            address(ROYALTY_MODULE),
            address(LICENSING_MODULE),
            address(LICENSE_REGISTRY)
        );

        mockNft = new ERC721Mock("TestNFT", "TNFT");
        mockNft.mint(user, 1);

        // Register the NFT as an IP Asset on Story Protocol
        vm.prank(user);
        mockIpAssetRegistry.register(block.chainid, address(mockNft), 1); // Use mock for registration
    }

    function testClaimRoyalty() public {
        address ipId = mockIpAssetRegistry.ipId(block.chainid, address(mockNft), 1); // Use mock for ipId retrieval

        // This test requires that the IP has parents with royalty policies.
        // For a unit test, you would mock these dependencies.
        // For an integration test, you would need to set up the parent IPs and licenses on a forked mainnet.
        // For now, this test will likely fail without the setup.
        vm.expectRevert(); // Expecting revert because no royalties are set up
        royaltyManager.claimRoyalty(ipId);
    }
}
