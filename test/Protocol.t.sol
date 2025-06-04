// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ILendingProtocol might still be needed directly in tests for params, events etc.
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
// Import the base setup contract (which includes Test, Vm, core contracts, mocks)
import {ProtocolSetup, ReentrantBorrowerRepay} from "./Setup.t.sol"; // ReentrantBorrowerRepay also imported for relevant tests
// Specific imports for types used in `new` expressions within tests, if not covered by ProtocolSetup's exports
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";


contract ProtocolTest is ProtocolSetup {
    // State variables, addresses, constants, and setUp() are inherited from ProtocolSetup.

    // A new test to confirm setup from base is working as expected.
    function test_BaseSetupConfirmation() public {
        assertTrue(currencyManager.isCurrencySupported(address(weth)));
        assertTrue(currencyManager.isCurrencySupported(address(usdc)));
        assertTrue(collectionManager.isCollectionWhitelisted(address(nftCollection)));
        assertEq(nftCollection.ownerOf(1), bob);
        assertEq(nftCollection.ownerOf(3), charlie);
        assertEq(weth.balanceOf(charlie), WETH_STARTING_BALANCE); // WETH_STARTING_BALANCE is internal in ProtocolSetup
        assertEq(usdc.balanceOf(charlie), USDC_STARTING_BALANCE); // USDC_STARTING_BALANCE is internal in ProtocolSetup
        assertEq(nftCollection.ownerOf(10), bob);
    }

    function test_InitialSetup() public {
        assertTrue(currencyManager.isCurrencySupported(address(weth)));
        assertTrue(currencyManager.isCurrencySupported(address(usdc)));
        assertTrue(collectionManager.isCollectionWhitelisted(address(nftCollection)));
        assertEq(nftCollection.ownerOf(1), bob);
        assertEq(nftCollection.ownerOf(3), charlie); // Charlie owns NFT ID 3
        assertEq(weth.balanceOf(charlie), WETH_STARTING_BALANCE); // Charlie has WETH
        assertEq(usdc.balanceOf(charlie), USDC_STARTING_BALANCE); // Charlie has USDC
        assertEq(nftCollection.ownerOf(10), bob); // Bob owns NFT ID 10 for vault
    }

    // Standard Loan tests moved to test/StandardLoan.t.sol:
    // - test_LenderMakesOffer_BorrowerAccepts_RepaysLoan
    // - test_Fail_AcceptExpiredOffer
    // - test_AccessControl_CancelLoanOffer_Revert_NotOfferOwner (related to standard offers)
    // - test_MakeLoanOffer_Revert_UnsupportedCurrency (general but affects standard offers)
    // - test_MakeLoanOffer_Revert_CollectionNotWhitelisted_StandardOffer (specific to standard offers)

    // Add more tests:
    // - Collection offers MOVED to test/CollectionLoan.t.sol
    // - Refinancing
    // - Renegotiation
    // - Liquidation (claim collateral, auction)
    // - Sell & Repay
    // - Vaults
    // - Edge cases, security checks (reentrancy, access control)

    // test_CollectionOffer_LenderMakes_BorrowersAccept MOVED
    // test_CollectionOffer_Revert_LenderInsufficientBalanceForNextLoan MOVED
    // test_CollectionOffer_OfferCreation_PrincipalCanBeGreaterThanMaxPrincipalPerLoan MOVED

    // Refinance tests moved to test/Refinance.t.sol
    // - _createInitialLoanForRefinance
    // - test_Refinance_Successful
    // - test_Refinance_Revert_PrincipalReduction
    // - test_Refinance_Revert_OriginalLoanNotActive
    // - test_Refinance_Successful_NewPrincipalSameAsOld

    // Renegotiation tests moved to test/Renegotiation.t.sol
    // - _createInitialLoanForRenegotiation (alias and its original logic now in RenegotiationTest)
    // - test_Renegotiation_Successful_LenderProposes_BorrowerAccepts_IncreasedPrincipal
    // - test_Renegotiation_Successful_LenderProposes_BorrowerAccepts_DecreasedPrincipal
    // - test_Renegotiation_Revert_NotLenderProposes
    // - test_Renegotiation_Revert_NotBorrowerAccepts
    // - test_Renegotiation_Revert_ProposalNotFound
    // - test_Renegotiation_Revert_LoanNotActiveForPropose
    // - test_Renegotiation_Revert_LoanNotActiveForAccept
    // - test_Renegotiation_Revert_ProposalAlreadyActioned

    // --- Claim Collateral Tests MOVED to test/Collateral.t.sol ---
    // - test_ClaimCollateral_Successful
    // - test_ClaimCollateral_Revert_NotLender
    // - test_ClaimCollateral_Revert_LoanNotDefaulted
    // - test_ClaimCollateral_Revert_LoanAlreadyClaimed
    // - test_VaultCollateral_Default_Claim (also moved, was part of this section before)

    // --- Vault Collateral Tests MOVED to test/Vault.t.sol ---
    // - test_VaultCollateral_MakeOffer_Accept_Repay

    // test_VaultCollateral_Default_Claim MOVED to test/Collateral.t.sol

    // --- Edge Case and Security Tests ---
    // MOVED to test/Security.t.sol:
    // - test_Reentrancy_RepayLoan
    // - test_AccessControl_SetCurrencyManager_Revert_NotOwner

    // test_AccessControl_CancelLoanOffer_Revert_NotOfferOwner MOVED to StandardLoan.t.sol
    // test_MakeLoanOffer_Revert_UnsupportedCurrency MOVED to StandardLoan.t.sol
    // test_MakeLoanOffer_Revert_CollectionNotWhitelisted_StandardOffer MOVED to StandardLoan.t.sol
    // test_MakeLoanOffer_Revert_CollectionNotWhitelisted_CollectionOffer MOVED to CollectionLoan.t.sol

    // Timestamp Manipulation Tests MOVED to test/EdgeCases.t.sol
    // - test_RepayLoan_AtExactDueTime
    // - test_RepayLoan_OneSecondPastDueTime_Revert_Defaulted
    // - test_ClaimCollateral_AtExactDueTime_Revert_NotDefaultedYet
    // - test_CalculateInterest_TimeTravel
}

// IERC721Receiver and ReentrantBorrowerRepay are now in Setup.t.sol
// They are removed from this file.
