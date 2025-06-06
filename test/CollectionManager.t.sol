// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/core/CollectionManager.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

contract CollectionManagerTest is Test {
    CollectionManager public manager;
    MockERC721 public mockNFT1;
    MockERC721 public mockNFT2;
    address public owner;

    function setUp() public {
        owner = address(this);
        address[] memory initialCollections = new address[](0);
        manager = new CollectionManager(initialCollections);

        // Deploy mock NFTs
        mockNFT1 = new MockERC721("Mock1", "MK1");
        mockNFT2 = new MockERC721("Mock2", "MK2");
    }

    function testAddWhitelistedCollection() public {
        manager.addWhitelistedCollection(address(mockNFT1));
        assertTrue(manager.isCollectionWhitelisted(address(mockNFT1)));
    }

    function testRemoveWhitelistedCollection() public {
        manager.addWhitelistedCollection(address(mockNFT1));
        manager.removeWhitelistedCollection(address(mockNFT1));
        assertFalse(manager.isCollectionWhitelisted(address(mockNFT1)));
    }

    function testGetWhitelistedCollections() public {
        manager.addWhitelistedCollection(address(mockNFT1));
        manager.addWhitelistedCollection(address(mockNFT2));

        address[] memory collections = manager.getWhitelistedCollections();
        assertEq(collections.length, 2);
        assertTrue(collections[0] == address(mockNFT1) || collections[1] == address(mockNFT1));
        assertTrue(collections[0] == address(mockNFT2) || collections[1] == address(mockNFT2));
    }

    function testCannotAddZeroAddress() public {
        vm.expectRevert("Zero address");
        manager.addWhitelistedCollection(address(0));
    }

    function testCannotAddNonContract() public {
        vm.expectRevert("Not a contract address");
        manager.addWhitelistedCollection(address(1));
    }

    function testCannotAddDuplicateCollection() public {
        manager.addWhitelistedCollection(address(mockNFT1));
        vm.expectRevert("Collection already whitelisted");
        manager.addWhitelistedCollection(address(mockNFT1));
    }

    function testOnlyOwnerCanAdd() public {
        address nonOwner = address(0x123);
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        manager.addWhitelistedCollection(address(mockNFT1));
    }
}
