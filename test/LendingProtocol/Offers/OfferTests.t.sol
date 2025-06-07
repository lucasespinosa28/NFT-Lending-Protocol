// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LendingProtocolBaseTest} from "../LendingProtocolBase.t.sol";
import {ILendingProtocol} from "../../../src/interfaces/ILendingProtocol.sol";
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol"; // For unsupported currency test
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol"; // For unwhitelisted collection test

contract OfferTests is LendingProtocolBaseTest {
    function test_MakeStandardLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: BORROWER_NFT_ID,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });

        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(offerId != bytes32(0), "Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.lender, lender, "Offer lender incorrect");
        assertEq(offer.nftContract, address(mockNft), "Offer NFT contract incorrect");
        assertEq(offer.nftTokenId, BORROWER_NFT_ID, "Offer NFT token ID incorrect");
        assertEq(offer.currency, address(weth), "Offer currency incorrect");
        assertEq(offer.principalAmount, 1 ether, "Offer principal incorrect");
        assertTrue(offer.isActive, "Offer should be active");

        vm.stopPrank();
    }

    function test_MakeCollectionLoanOffer_Success() public {
        vm.startPrank(lender);

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.COLLECTION,
            nftContract: address(mockNft),
            nftTokenId: 0, // Not specific for collection offer type at creation
            currency: address(weth),
            principalAmount: 0.5 ether, // Should be <= maxPrincipalPerLoan
            interestRateAPR: 600,
            durationSeconds: 14 days,
            expirationTimestamp: expiration,
            originationFeeRate: 50,
            totalCapacity: 10 ether,
            maxPrincipalPerLoan: 0.5 ether, // principalAmount must be <= this
            minNumberOfLoans: 1
        });

        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        assertTrue(offerId != bytes32(0), "Collection Offer ID should not be zero");

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertEq(offer.lender, lender, "Collection Offer lender incorrect");
        assertEq(uint8(offer.offerType), uint8(ILendingProtocol.OfferType.COLLECTION), "Offer type incorrect");
        assertEq(offer.nftContract, address(mockNft), "Collection Offer NFT contract incorrect");
        assertEq(offer.currency, address(weth), "Collection Offer currency incorrect");
        assertEq(offer.totalCapacity, 10 ether, "Collection Offer total capacity incorrect");
        assertEq(offer.maxPrincipalPerLoan, 0.5 ether, "Collection Offer max principal per loan incorrect");
        assertTrue(offer.isActive, "Collection Offer should be active");

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnsupportedCurrency() public {
        vm.startPrank(lender);

        ERC20Mock unsupportedToken = new ERC20Mock("Unsupported", "UNS");

        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: BORROWER_NFT_ID,
            currency: address(unsupportedToken), // Using an unsupported currency
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });

        vm.expectRevert("Currency not supported");
        lendingProtocol.makeLoanOffer(params);

        vm.stopPrank();
    }

    function test_Fail_MakeStandardLoanOffer_UnwhitelistedCollection() public {
        // Create unwhitelisted NFT
        ERC721Mock unwhitelistedNft = new ERC721Mock("Unlisted NFT", "UNL");

        // Mint NFT as owner
        vm.startPrank(owner);
        unwhitelistedNft.mint(borrower, 1); // Mint to borrower so they own it
        vm.stopPrank();

        // Try to make offer as lender
        vm.startPrank(lender);
        uint64 expiration = uint64(block.timestamp + 1 days);
        ILendingProtocol.OfferParams memory params = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(unwhitelistedNft),
            nftTokenId: 1, // Token ID owned by borrower
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 7 days,
            expirationTimestamp: expiration,
            originationFeeRate: 100,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });

        vm.expectRevert("Collection not whitelisted");
        lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
    }

    // TODO: Add test_CancelLoanOffer_Success if applicable from original or new tests
    // function test_CancelLoanOffer_Success() public { ... }
    // function test_Fail_CancelLoanOffer_NotOwner() public { ... }
}
