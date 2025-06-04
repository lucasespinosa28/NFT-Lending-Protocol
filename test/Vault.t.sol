// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProtocolSetup} from "./Setup.t.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol"; // For NFTItem struct

contract VaultTest is ProtocolSetup {

    function test_VaultCollateral_MakeOffer_Accept_Repay() public {
        uint256 vaultNftId = 10; // The NFT ID Bob will put in the vault (minted to Bob in ProtocolSetup)

        // Bob Creates a Vault
        vm.startPrank(bob);
        nftCollection.approve(address(vaultsFactory), vaultNftId);

        VaultsFactory.NFTItem[] memory items = new VaultsFactory.NFTItem[](1);
        items[0] = VaultsFactory.NFTItem({
            contractAddress: address(nftCollection),
            tokenId: vaultNftId,
            amount: 1,
            isERC1155: false
        });

        uint256 expectedVaultId = vaultsFactory.totalSupply() + 1;

        vm.expectEmit(true, true, true, true);
        emit VaultsFactory.VaultCreated(expectedVaultId, bob, items);
        uint256 vaultId1 = vaultsFactory.mintVault(bob, items);
        assertEq(vaultId1, expectedVaultId, "Vault ID mismatch");

        assertEq(vaultsFactory.ownerOf(vaultId1), bob, "Bob should own the new vault");
        assertEq(nftCollection.ownerOf(vaultNftId), address(vaultsFactory), "NFT should be held by VaultsFactory");
        vm.stopPrank();

        // Alice (Lender) Makes an Offer for Bob's Vault
        uint256 loanPrincipalForVault = 1 ether;
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), loanPrincipalForVault);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(vaultsFactory),
            nftTokenId: vaultId1,
            currency: address(weth),
            principalAmount: loanPrincipalForVault,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 days),
            originationFeeRate: 0, totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
        });

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferMade(0, alice, offerParams.offerType, offerParams.nftContract, offerParams.nftTokenId, offerParams.currency, offerParams.principalAmount, offerParams.interestRateAPR, offerParams.durationSeconds, offerParams.expirationTimestamp, offerParams.originationFeeRate,0,0,0);
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        assertTrue(offerId != 0, "Offer ID for vault loan is zero");
        vm.stopPrank();

        // Bob (Borrower) Accepts Offer with Vault
        vm.startPrank(bob);
        vaultsFactory.approve(address(lendingProtocol), vaultId1);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.OfferAccepted(offerId, 0, bob, alice, address(vaultsFactory), vaultId1, address(weth), loanPrincipalForVault, block.timestamp, 30 days, 500, 0);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(vaultsFactory), vaultId1);
        assertTrue(loanId != 0, "Loan ID for vault collateral is zero");

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertTrue(loan.isVault, "Loan.isVault should be true");
        assertEq(loan.nftContract, address(vaultsFactory), "Loan.nftContract should be VaultsFactory address");
        assertEq(loan.nftTokenId, vaultId1, "Loan.nftTokenId should be vaultId1");
        assertEq(vaultsFactory.ownerOf(vaultId1), address(lendingProtocol), "Vault should be escrowed by LendingProtocol");
        vm.stopPrank();

        // Bob Repays the Loan
        vm.startPrank(bob);
        vm.warp(block.timestamp + 15 days);
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;
        weth.approve(address(lendingProtocol), totalRepayment);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanRepaid(loanId, bob, alice, totalRepayment, interest);
        lendingProtocol.repayLoan(loanId);

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status not REPAID");
        assertEq(vaultsFactory.ownerOf(vaultId1), bob, "Vault should be returned to Bob");
        vm.stopPrank();
    }
}
