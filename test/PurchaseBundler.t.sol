// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/PurchaseBundler.sol";
import "../src/interfaces/ILendingProtocol.sol";
import "../src/mocks/ERC721Mock.sol";
import "../src/mocks/ERC20Mock.sol";
import "../src/mocks/MockLendingProtocol.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For Ownable errors

contract PurchaseBundlerTest is Test {
    PurchaseBundler internal purchaseBundler;
    MockLendingProtocol internal mockLendingProtocol; // Use the mock
    ERC721Mock internal mockNft;
    ERC20Mock internal mockCurrency;
    address internal admin = address(this);
    // address internal treasury = address(0xDEAD); // PurchaseBundler does not have a treasury field
    address internal user = address(0x1001);
    address internal seller = address(0x1002); // Example seller (borrower) - distinct from user
    address internal buyer = address(0x1003);  // Example buyer
    uint256 internal constant NFT_ID = 1;

    function setUp() public {
        mockLendingProtocol = new MockLendingProtocol();
        // Constructor: PurchaseBundler(address _lendingProtocolAddress)
        purchaseBundler = new PurchaseBundler(address(mockLendingProtocol));

        mockNft = new ERC721Mock("MockNFT", "MNFT");
        mockCurrency = new ERC20Mock("MockCurrency", "MCK");
        mockNft.mint(seller, NFT_ID);
    }

    function test_InitialState() public {
        assertEq(purchaseBundler.owner(), admin, "Owner not set");
        assertEq(address(purchaseBundler.lendingProtocol()), address(mockLendingProtocol), "LendingProtocol address incorrect");
        // No treasury function to test
    }

    function test_SetLendingProtocolAddress_WhenAdmin() public {
        MockLendingProtocol newMockLP = new MockLendingProtocol();
        purchaseBundler.setLendingProtocol(address(newMockLP)); // Called by admin
        assertEq(address(purchaseBundler.lendingProtocol()), address(newMockLP), "New LP address not set");
    }

    function test_SetLendingProtocolAddress_WhenNotAdmin_ShouldFail() public {
        MockLendingProtocol newMockLP = new MockLendingProtocol();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        purchaseBundler.setLendingProtocol(address(newMockLP));
        vm.stopPrank();
    }

    // No treasury tests as PurchaseBundler.sol does not manage a treasury address directly via constructor/setters.

    // Tests for listCollateralForSale, buyListedCollateral etc. will be added.
}
