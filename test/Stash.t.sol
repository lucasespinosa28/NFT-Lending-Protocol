// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Stash} from "../src/core/Stash.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";
import {MockIIPAssetRegistry} from "../src/mocks/MockIIPAssetRegistry.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract StashTest is Test {
    Stash internal stash;
    ERC721Mock internal mockNft;
    MockIIPAssetRegistry internal mockIpAssetRegistry;

    address internal owner = address(0x1);
    address internal stashingUser = address(0x2);
    uint256 internal constant USER_NFT_ID = 1;

    function setUp() public {
        vm.deal(owner, 1 ether);
        vm.deal(stashingUser, 1 ether);

        vm.startPrank(owner);
        mockNft = new ERC721Mock("Original NFT", "ONFT");
        mockIpAssetRegistry = new MockIIPAssetRegistry();
        // Deploy Stash with the mock IP registry
        stash = new Stash("Stashed ONFT", "sONFT", address(0), address(mockIpAssetRegistry));
        vm.stopPrank();

        // Mint NFT to user and approve stash contract
        vm.prank(owner);
        mockNft.mint(stashingUser, USER_NFT_ID);
        vm.startPrank(stashingUser);
        mockNft.setApprovalForAll(address(stash), true);
        vm.stopPrank();
    }

    function test_Stash_NonStoryAsset_Success() public {
        vm.startPrank(stashingUser);
        uint256 stashTokenId = stash.stash(address(mockNft), USER_NFT_ID);
        vm.stopPrank();

        assertTrue(stashTokenId > 0, "Stash token ID should be greater than zero");
        assertEq(stash.ownerOf(stashTokenId), stashingUser, "Stash token not owned by stasher");
        assertEq(mockNft.ownerOf(USER_NFT_ID), address(stash), "Original NFT not held by Stash contract");
    }

    function test_Stash_StoryRegisteredAsset_Fails() public {
        // Register the NFT with Story Protocol mock
        // Assuming stashingUser (owner of NFT) or general owner can register.
        // For this mock, anyone can call register.
        mockIpAssetRegistry.register(block.chainid, address(mockNft), USER_NFT_ID);

        // Attempt to stash
        vm.startPrank(stashingUser);
        vm.expectRevert("Stash: Token is already registered with Story Protocol");
        stash.stash(address(mockNft), USER_NFT_ID);
        vm.stopPrank();
    }
}
