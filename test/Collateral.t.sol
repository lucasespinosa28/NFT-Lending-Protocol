// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol"; // For NFTItem struct

contract CollateralTest is ProtocolSetup {

    // Helper to create a standard loan for default testing
    function _createInitialLoanForDefaultTest() internal returns (bytes32 loanId) {
        // Alice (lender) makes an offer for NFT ID 1 (owned by Bob)
        uint256 principal = 1 ether;
        uint256 apr = 500; // 5%
        uint256 duration = 10 days; // Shorter duration for faster default
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 originationFee = 100; // 1%

        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), principal + (principal * originationFee / 10000));

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 1, // Bob's NFT
            currency: address(weth),
            principalAmount: principal,
            interestRateAPR: apr,
            durationSeconds: duration,
            expirationTimestamp: expiration,
            originationFeeRate: originationFee,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // Bob (borrower) accepts the offer
        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();
        return loanId;
    }

    // Helper to create a vault loan for default testing
    function _createVaultLoanForDefaultTest() internal returns (bytes32 loanId, uint256 vaultId) {
        uint256 vaultNftIdToUse = 10; // NFT ID 10 is minted to Bob in ProtocolSetup

        // Bob Creates a Vault
        vm.startPrank(bob);
        nftCollection.approve(address(vaultsFactory), vaultNftIdToUse);
        VaultsFactory.NFTItem[] memory items = new VaultsFactory.NFTItem[](1);
        items[0] = VaultsFactory.NFTItem({
            contractAddress: address(nftCollection),
            tokenId: vaultNftIdToUse,
            amount: 1,
            isERC1155: false
        });
        vaultId = vaultsFactory.mintVault(bob, items);
        vm.stopPrank();

        // Alice Makes an Offer for Bob's Vault
        uint256 loanPrincipalForVault = 0.5 ether;
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), loanPrincipalForVault);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(vaultsFactory),
            nftTokenId: vaultId,
            currency: address(weth),
            principalAmount: loanPrincipalForVault,
            interestRateAPR: 600,
            durationSeconds: 10 days, // Shorter duration
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        // Bob Accepts Offer with Vault
        vm.startPrank(bob);
        vaultsFactory.approve(address(lendingProtocol), vaultId);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(vaultsFactory), vaultId);
        vm.stopPrank();
        return (loanId, vaultId);
    }

    function test_ClaimCollateral_Successful() public {
        bytes32 loanId = _createInitialLoanForDefaultTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        vm.warp(loan.dueTime + 1 days);

        vm.startPrank(alice);
        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT owner should be protocol before claim");

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.CollateralClaimed(loanId, alice, loan.nftContract, loan.nftTokenId);

        lendingProtocol.claimCollateral(loanId);

        ILendingProtocol.Loan memory defaultedLoan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(defaultedLoan.status), uint256(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status should be DEFAULTED");
        assertEq(nftCollection.ownerOf(loan.nftTokenId), alice, "NFT owner should be Alice after claim");
        vm.stopPrank();
    }

    function test_ClaimCollateral_Revert_NotLender() public {
        bytes32 loanId = _createInitialLoanForDefaultTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        vm.warp(loan.dueTime + 1 days);

        vm.startPrank(charlie); // Charlie is not the lender
        vm.expectRevert("Not lender");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT should still be owned by protocol");
    }

    function test_ClaimCollateral_Revert_LoanNotDefaulted() public {
        bytes32 loanId = _createInitialLoanForDefaultTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        assertTrue(block.timestamp <= loan.dueTime, "Timestamp should be before or at due time for this test");

        vm.startPrank(alice);
        vm.expectRevert("Loan not yet defaulted");
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        assertEq(nftCollection.ownerOf(loan.nftTokenId), address(lendingProtocol), "NFT should still be owned by protocol");
        ILendingProtocol.Loan memory currentLoan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(currentLoan.status), uint256(ILendingProtocol.LoanStatus.ACTIVE), "Loan status should still be ACTIVE");
    }

    function test_ClaimCollateral_Revert_LoanAlreadyClaimed() public {
        bytes32 loanId = _createInitialLoanForDefaultTest();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        vm.warp(loan.dueTime + 1 days);

        vm.startPrank(alice);
        lendingProtocol.claimCollateral(loanId);
        assertEq(nftCollection.ownerOf(loan.nftTokenId), alice, "NFT should be owned by Alice after first claim");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(bytes("ERC721: transfer from incorrect owner"));
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();
    }

    function test_VaultCollateral_Default_Claim() public {
        (bytes32 loanId, uint256 vaultId) = _createVaultLoanForDefaultTest();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueTime + 1 days);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.CollateralClaimed(loanId, alice, address(vaultsFactory), vaultId);
        lendingProtocol.claimCollateral(loanId);

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status not DEFAULTED after claim");
        assertEq(vaultsFactory.ownerOf(vaultId), alice, "Vault should be transferred to Alice after claim");
        vm.stopPrank();
    }
}
