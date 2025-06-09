// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/RangeValidator.sol";
import "../src/interfaces/IRangeValidator.sol";
import "../src/mocks/ERC721Mock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol"; // For Ownable errors

contract RangeValidatorTest is Test {
    RangeValidator internal rangeValidator;
    address internal admin = address(this);
    address internal user = address(0x1001);
    ERC721Mock internal mockNft;

    function setUp() public {
        // Constructor: RangeValidator() Ownable(msg.sender)
        rangeValidator = new RangeValidator();
        mockNft = new ERC721Mock("MockNFT_For_RangeValidator", "MNFT_RV");
    }

    function test_InitialState() public view {
        assertEq(rangeValidator.owner(), admin, "Owner not set");
    }

    function test_SetAndCheckTokenIdRangeRule() public {
        // Note: This test will still fail the assertTrue assertions if isTokenIdValidForCollectionOffer is not implemented
        uint256 minTokenId = 10;
        uint256 maxTokenId = 20;

        vm.startPrank(admin);
        // Set rule: Allow token IDs 10-20 for mockNft
        rangeValidator.setTokenIdRangeRule(address(mockNft), minTokenId, maxTokenId, true);
        vm.stopPrank();

        // Assertions will currently fail because isTokenIdValidForCollectionOffer always returns false.
        // These assertions represent the desired behavior once the contract logic is implemented.
        assertTrue(rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft), 15), "Token ID 15 should be valid");
        assertTrue(
            rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft), minTokenId),
            "Min Token ID 10 should be valid"
        );
        assertTrue(
            rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft), maxTokenId),
            "Max Token ID 20 should be valid"
        );

        assertFalse(
            rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft), 5),
            "Token ID 5 should be invalid (below range)"
        );
        assertFalse(
            rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft), 25),
            "Token ID 25 should be invalid (above range)"
        );

        // Test for a collection with no rules set (or if default is false)
        ERC721Mock mockNft2 = new ERC721Mock("MockNFT2_For_RangeValidator", "MNFT_RV2");
        assertFalse(
            rangeValidator.isTokenIdValidForCollectionOffer(address(mockNft2), 15),
            "Token ID for unconfigured collection should be invalid"
        );
    }

    function test_SetTokenIdRangeRule_WhenNotAdmin_ShouldFail() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rangeValidator.setTokenIdRangeRule(address(mockNft), 10, 20, true);
        vm.stopPrank();
    }

    // Further tests for multiple rules, overlapping rules, specific validators etc. can be added.
}
