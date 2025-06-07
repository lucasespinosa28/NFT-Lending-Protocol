// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IRoyaltyManager
 * @notice Interface for managing and claiming royalties for IP assets.
 */
interface IRoyaltyManager {
    /**
     * @notice Emitted when royalties are claimed for an IP asset.
     * @param ipId The address of the IP asset.
     * @param amount The amount of royalty claimed.
     */
    event RoyaltyClaimed(address indexed ipId, uint256 amount);

    /**
     * @notice Claims royalty for a given IP asset and currency.
     * @param ipId The address of the IP asset.
     * @param currencyToken The address of the currency token.
     */
    function claimRoyalty(address ipId, address currencyToken) external;

    /**
     * @notice Gets the royalty balance for a given IP asset and currency.
     * @param ipId The address of the IP asset.
     * @param currencyToken The address of the currency token.
     * @return The royalty balance.
     */
    function getRoyaltyBalance(address ipId, address currencyToken) external view returns (uint256);

    /**
     * @notice Withdraws royalty for a given IP asset and currency to a recipient.
     * @param ipId The address of the IP asset.
     * @param currencyToken The address of the currency token.
     * @param recipient The address to receive the withdrawn royalty.
     * @param amount The amount to withdraw.
     */
    function withdrawRoyalty(address ipId, address currencyToken, address recipient, uint256 amount) external;
}
