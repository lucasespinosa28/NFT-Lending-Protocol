// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LendingProtocolBaseTest} from "./LendingProtocolBase.t.sol";
// No specific ILendingProtocol structs needed for this test usually

contract InitialSetupTests is LendingProtocolBaseTest {
    function test_InitialSetup() public {
        assertTrue(address(weth) != address(0), "WETH not deployed");
        assertTrue(address(usdc) != address(0), "USDC not deployed");
        assertTrue(address(mockNft) != address(0), "MockNFT not deployed");
        assertTrue(address(currencyManager) != address(0), "CurrencyManager not deployed");
        assertTrue(address(collectionManager) != address(0), "CollectionManager not deployed");
        assertTrue(address(vaultsFactory) != address(0), "VaultsFactory not deployed");
        assertTrue(address(liquidation) != address(0), "Liquidation not deployed");
        assertTrue(address(purchaseBundler) != address(0), "PurchaseBundler not deployed");
        assertTrue(address(royaltyManager) != address(0), "RoyaltyManager not deployed");
        assertTrue(address(mockIpAssetRegistry) != address(0), "MockIpAssetRegistry not deployed");
        assertTrue(address(mockRoyaltyModule) != address(0), "MockRoyaltyModule not deployed");
        assertTrue(address(lendingProtocol) != address(0), "LendingProtocol not deployed");

        assertEq(weth.balanceOf(lender), LENDER_INITIAL_WETH_BALANCE, "Lender WETH balance incorrect");
        assertEq(mockNft.ownerOf(BORROWER_NFT_ID), borrower, "Borrower NFT ownership incorrect");

        assertTrue(currencyManager.isCurrencySupported(address(weth)), "WETH not supported by CurrencyManager");
        assertTrue(
            collectionManager.isCollectionWhitelisted(address(mockNft)), "MockNFT not whitelisted by CollectionManager"
        );
    }
}
