// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/Liquidation.sol";
import "../src/interfaces/ILendingProtocol.sol";
import "../src/mocks/MockLendingProtocol.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For Ownable errors

contract LiquidationTest is Test {
    Liquidation internal liquidation;
    MockLendingProtocol internal mockLendingProtocol;
    // address internal treasury = address(0xDEAD); // Liquidation does not have a treasury field
    address internal admin = address(this);
    address internal user = address(0x1001);


    function setUp() public {
        mockLendingProtocol = new MockLendingProtocol();
        // Constructor: Liquidation(address _lendingProtocolAddress)
        liquidation = new Liquidation(address(mockLendingProtocol));
    }

    function test_InitialState() public {
        assertEq(liquidation.owner(), admin, "Owner not set");
        assertEq(address(liquidation.lendingProtocol()), address(mockLendingProtocol), "LendingProtocol address incorrect");
        // No treasuryAddress function to test
    }

    function test_SetLendingProtocolAddress_WhenAdmin() public {
        MockLendingProtocol newMockLP = new MockLendingProtocol();
        liquidation.setLendingProtocol(address(newMockLP)); // Called by admin (this)
        assertEq(address(liquidation.lendingProtocol()), address(newMockLP), "New LP address not set");
    }

    function test_SetLendingProtocolAddress_WhenNotAdmin_ShouldFail() public {
        MockLendingProtocol newMockLP = new MockLendingProtocol();
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        liquidation.setLendingProtocol(address(newMockLP));
        vm.stopPrank();
    }

    // No treasury tests as Liquidation.sol does not manage a treasury address directly via constructor/setters.

    // Tests for startAuction, bid, claimCollateralFromAuction etc. will be added.
}
