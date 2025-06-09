// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CurrencyManager} from "../../src/core/manager/CurrencyManager.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For Ownable errors

contract CurrencyManagerTest is Test {
    CurrencyManager internal currencyManager;
    ERC20Mock internal mockCurrency;
    address internal admin = address(this);
    address internal user = address(0x1001);

    function setUp() public {
        // Constructor: CurrencyManager(address[] memory initialCurrencies)
        // Owner is msg.sender (admin)
        currencyManager = new CurrencyManager(new address[](0));
        mockCurrency = new ERC20Mock("MockCurrency", "MCK");
    }

    function test_InitialState() public view {
        assertEq(currencyManager.owner(), admin, "Owner not set to deployer");
        assertEq(currencyManager.getSupportedCurrencies().length, 0, "Initially no currencies should be supported");
    }

    function test_AddAndCheckSupportedCurrency() public {
        // Admin (this contract) calls addSupportedCurrency
        currencyManager.addSupportedCurrency(address(mockCurrency));

        assertTrue(
            currencyManager.isCurrencySupported(address(mockCurrency)), "Mock currency should be supported after adding"
        );

        // Verify it's in the list of supported currencies
        address[] memory supportedCurrencies = currencyManager.getSupportedCurrencies();
        bool found = false;
        for (uint256 i = 0; i < supportedCurrencies.length; i++) {
            if (supportedCurrencies[i] == address(mockCurrency)) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Mock currency not found in supported currencies list");
    }

    function test_AddCurrency_WhenNotAdmin_ShouldFail() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        currencyManager.addSupportedCurrency(address(mockCurrency));
        vm.stopPrank();
    }

    function test_RemoveSupportedCurrency() public {
        // Add currency first (by admin - this contract)
        currencyManager.addSupportedCurrency(address(mockCurrency));
        assertTrue(
            currencyManager.isCurrencySupported(address(mockCurrency)), "Currency should be supported before removal"
        );

        // Admin (this contract) removes currency
        currencyManager.removeSupportedCurrency(address(mockCurrency));
        assertFalse(
            currencyManager.isCurrencySupported(address(mockCurrency)), "Currency should not be supported after removal"
        );
    }

    function test_RemoveCurrency_WhenNotAdmin_ShouldFail() public {
        // Add currency first by admin (this contract)
        currencyManager.addSupportedCurrency(address(mockCurrency));

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        currencyManager.removeSupportedCurrency(address(mockCurrency));
        vm.stopPrank();
    }
}
