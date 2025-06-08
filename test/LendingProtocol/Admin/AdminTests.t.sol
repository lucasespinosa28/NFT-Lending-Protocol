// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LendingProtocolBaseTest} from "../LendingProtocolBase.t.sol";
import {ICurrencyManager} from "../../../src/interfaces/ICurrencyManager.sol";
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol"; // For emergency withdraw tests
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol"; // For emergency withdraw tests
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract AdminTests is LendingProtocolBaseTest {
    // TODO: Add tests for administrative functions
    // - test_SetCurrencyManager_Success (example, if direct testing is desired)
    // - test_Fail_SetCurrencyManager_NotOwner
    // - test_EmergencyWithdrawERC20_Success
    // - test_Fail_EmergencyWithdrawERC20_NotOwner
    // - test_EmergencyWithdrawERC721_Success
    // - test_Fail_EmergencyWithdrawERC721_NotOwner
    // - test_EmergencyWithdrawNative_Success
    // - test_Fail_EmergencyWithdrawNative_NotOwner

    address internal newCurrencyManagerAddr;

    function setUp() public override {
        super.setUp();
        // Deploy a new dummy contract or use a fresh address for the new currency manager
        newCurrencyManagerAddr = address(new ERC20Mock("Dummy CM", "DCM")); // Using ERC20Mock as a stand-in for a generic contract address
    }

    function test_SetCurrencyManager_Success() public {
        vm.startPrank(owner);
        // No specific event is defined in AdminManager or LendingProtocol for this setter,
        // so we just check the state change.
        lendingProtocol.setCurrencyManager(newCurrencyManagerAddr);
        assertEq(address(lendingProtocol.currencyManager()), newCurrencyManagerAddr, "CurrencyManager should be updated");
        vm.stopPrank();
    }

    function test_Fail_SetCurrencyManager_NotOwner() public {
        vm.startPrank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        lendingProtocol.setCurrencyManager(newCurrencyManagerAddr);
        vm.stopPrank();
    }

    // --- Emergency Withdraw ERC20 ---
    function test_EmergencyWithdrawERC20_Success() public {
        // Mint some WETH to the LendingProtocol contract
        uint256 amountToWithdraw = 10 ether;
        weth.mint(address(lendingProtocol), amountToWithdraw);

        uint256 initialBalanceRecipient = weth.balanceOf(owner);
        uint256 initialBalanceLP = weth.balanceOf(address(lendingProtocol));

        vm.startPrank(owner);
        lendingProtocol.emergencyWithdrawERC20(address(weth), owner, amountToWithdraw);
        vm.stopPrank();

        assertEq(weth.balanceOf(owner), initialBalanceRecipient + amountToWithdraw, "Owner should receive withdrawn WETH");
        assertEq(weth.balanceOf(address(lendingProtocol)), initialBalanceLP - amountToWithdraw, "LP balance should decrease");
    }

    function test_Fail_EmergencyWithdrawERC20_NotOwner() public {
        uint256 amountToWithdraw = 1 ether;
        weth.mint(address(lendingProtocol), amountToWithdraw); // Ensure LP has funds

        vm.startPrank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        lendingProtocol.emergencyWithdrawERC20(address(weth), otherUser, amountToWithdraw);
        vm.stopPrank();
    }

    // --- Emergency Withdraw ERC721 ---
    function test_EmergencyWithdrawERC721_Success() public {
        // Mint an NFT to the LendingProtocol contract
        uint256 nftIdToWithdraw = 999;
        mockNft.mint(address(lendingProtocol), nftIdToWithdraw);

        assertEq(mockNft.ownerOf(nftIdToWithdraw), address(lendingProtocol), "LP should own the NFT before withdrawal");

        vm.startPrank(owner);
        lendingProtocol.emergencyWithdrawERC721(address(mockNft), owner, nftIdToWithdraw);
        vm.stopPrank();

        assertEq(mockNft.ownerOf(nftIdToWithdraw), owner, "Owner should receive withdrawn NFT");
    }

    function test_Fail_EmergencyWithdrawERC721_NotOwner() public {
        uint256 nftIdToWithdraw = 1000;
        mockNft.mint(address(lendingProtocol), nftIdToWithdraw); // Ensure LP owns an NFT

        vm.startPrank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        lendingProtocol.emergencyWithdrawERC721(address(mockNft), otherUser, nftIdToWithdraw);
        vm.stopPrank();
    }

    // --- Emergency Withdraw Native ---
    function test_EmergencyWithdrawNative_Success() public {
        uint256 amountToWithdraw = 1 ether;
        // Send some ETH to the LendingProtocol contract
        vm.deal(address(lendingProtocol), amountToWithdraw + 0.5 ether); // Give it a bit more than withdrawal amount

        uint256 initialBalanceRecipient = owner.balance;
        uint256 initialBalanceLP = address(lendingProtocol).balance;

        vm.startPrank(owner);
        lendingProtocol.emergencyWithdrawNative(payable(owner), amountToWithdraw);
        vm.stopPrank();

        // Recipient's balance should increase by amountToWithdraw. Gas costs make exact checks tricky for sender.
        assertEq(owner.balance, initialBalanceRecipient + amountToWithdraw, "Owner should receive withdrawn ETH");
        assertEq(address(lendingProtocol).balance, initialBalanceLP - amountToWithdraw, "LP ETH balance should decrease");
    }

    function test_Fail_EmergencyWithdrawNative_NotOwner() public {
        uint256 amountToWithdraw = 0.5 ether;
        vm.deal(address(lendingProtocol), amountToWithdraw); // Ensure LP has ETH

        vm.startPrank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        lendingProtocol.emergencyWithdrawNative(payable(otherUser), amountToWithdraw);
        vm.stopPrank();
    }
}
