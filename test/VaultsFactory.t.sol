// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/VaultsFactory.sol";
import "../src/core/CollectionManager.sol"; // Needed for setCollectionManager
import "../src/core/CurrencyManager.sol"; // Needed for setCurrencyManager
import "../src/mocks/ERC721Mock.sol"; // Added import
import "../src/mocks/ERC20Mock.sol"; // Added import
// May need mock vault implementation if deploying vaults is tested deeply.

contract VaultsFactoryTest is Test {
    VaultsFactory internal vaultsFactory;
    address internal admin = address(this); // Deployer, becomes owner of VaultsFactory
    address internal user = address(0x1001); // Another user
    ERC721Mock internal mockNft1;
    ERC721Mock internal mockNft2;

    function setUp() public {
        // Deploy VaultsFactory with name and symbol
        vaultsFactory = new VaultsFactory("TestVaults", "TVF");

        // Prepare mock NFTs
        mockNft1 = new ERC721Mock("MockNFT1", "MN1");
        mockNft2 = new ERC721Mock("MockNFT2", "MN2");

        // Mint some NFTs to the 'user' who will create the vault
        mockNft1.mint(user, 1);
        mockNft1.mint(user, 2);
        mockNft2.mint(user, 101);
    }

    function test_InitialState() public {
        assertEq(vaultsFactory.owner(), admin, "Owner should be the deployer");
        assertEq(vaultsFactory.name(), "TestVaults", "Name mismatch");
        assertEq(vaultsFactory.symbol(), "TVF", "Symbol mismatch");
    }

    function test_MintVaultAndCheckContent() public {
        // User needs to approve VaultsFactory to take their NFTs
        vm.startPrank(user);
        mockNft1.setApprovalForAll(address(vaultsFactory), true);
        mockNft2.setApprovalForAll(address(vaultsFactory), true);

        IVaultsFactory.NFTItem[] memory items = new IVaultsFactory.NFTItem[](2);
        items[0] = IVaultsFactory.NFTItem({
            contractAddress: address(mockNft1),
            tokenId: 1,
            amount: 1, // For ERC721, amount is 1
            isERC1155: false
        });
        items[1] = IVaultsFactory.NFTItem({
            contractAddress: address(mockNft2),
            tokenId: 101,
            amount: 1, // For ERC721, amount is 1
            isERC1155: false
        });

        // Expect VaultCreated event
        // event VaultCreated(uint256 indexed vaultId, address indexed owner, address[] nftContracts, uint256[] tokenIds, uint256[] amounts);
        // It has 2 indexed topics (vaultId, owner). The arrays are not indexed.
        address[] memory expectedNftContracts = new address[](2);
        expectedNftContracts[0] = address(mockNft1);
        expectedNftContracts[1] = address(mockNft2);
        uint256[] memory expectedTokenIds = new uint256[](2);
        expectedTokenIds[0] = 1;
        expectedTokenIds[1] = 101;
        uint256[] memory expectedAmounts = new uint256[](2);
        expectedAmounts[0] = 1; // amount for ERC721 is 1
        expectedAmounts[1] = 1; // amount for ERC721 is 1

        // vaultId will be 1 as it's the first vault minted in this test sequence.
        uint256 expectedVaultId = 1;

        vm.expectEmit(true, true, false, false, address(vaultsFactory)); // Check vaultId (indexed), owner (indexed), and other non-indexed data
        emit IVaultsFactory.VaultCreated(expectedVaultId, user, expectedNftContracts, expectedTokenIds, expectedAmounts); // Qualified with interface

        uint256 vaultId = vaultsFactory.mintVault(user, items);
        vm.stopPrank();

        assertEq(vaultId, expectedVaultId, "Minted vault ID mismatch"); // Also assert the returned vaultId
        assertTrue(vaultId > 0, "Vault ID should be non-zero");
        assertEq(vaultsFactory.ownerOf(vaultId), user, "Vault owner mismatch");
        assertTrue(vaultsFactory.isVault(vaultId), "isVault should return true for minted vault");
        assertEq(vaultsFactory.ownerOfVault(vaultId), user, "ownerOfVault mismatch");

        // Check content
        IVaultsFactory.NFTItem[] memory content = vaultsFactory.getVaultContent(vaultId);
        assertEq(content.length, 2, "Vault content length mismatch");
        assertEq(content[0].contractAddress, address(mockNft1), "Item 0 contract address mismatch");
        assertEq(content[0].tokenId, 1, "Item 0 tokenId mismatch");
        assertFalse(content[0].isERC1155, "Item 0 should be ERC721");
        assertEq(content[1].contractAddress, address(mockNft2), "Item 1 contract address mismatch");
        assertEq(content[1].tokenId, 101, "Item 1 tokenId mismatch");
        assertFalse(content[1].isERC1155, "Item 1 should be ERC721");

        // Verify NFTs are now owned by VaultsFactory
        assertEq(mockNft1.ownerOf(1), address(vaultsFactory), "NFT1 item 1 not held by factory");
        assertEq(mockNft2.ownerOf(101), address(vaultsFactory), "NFT2 item 101 not held by factory");
    }

    function test_MintVault_EmptyItems_ShouldFail() public {
        vm.startPrank(user);
        IVaultsFactory.NFTItem[] memory emptyItems = new IVaultsFactory.NFTItem[](0);
        vm.expectRevert("Cannot create empty vault");
        vaultsFactory.mintVault(user, emptyItems);
        vm.stopPrank();
    }

    function test_MintVault_NotApproved_ShouldFail() public {
        // User does NOT approve VaultsFactory for mockNft1
        vm.startPrank(user);
        // mockNft1.setApprovalForAll(address(vaultsFactory), true); // Approval missing

        IVaultsFactory.NFTItem[] memory items = new IVaultsFactory.NFTItem[](1);
        items[0] = IVaultsFactory.NFTItem({contractAddress: address(mockNft1), tokenId: 1, amount: 1, isERC1155: false});

        // Expect revert from ERC721: transfer caller is not owner nor approved
        vm.expectRevert(); // This will catch the ERC721 transfer failure
        vaultsFactory.mintVault(user, items);
        vm.stopPrank();
    }
}
