// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ICurrencyManager
 * @author Lucas Espinosa
 * @notice Interface for managing supported ERC20 currencies for loans.
 * @dev Provides functions to add, remove, and query supported currencies.
 */
interface ICurrencyManager {
    // --- Events ---
    /**
     * @notice Emitted when a new ERC20 token is added as a supported currency.
     * @param tokenAddress The address of the ERC20 token added.
     */
    event CurrencyAdded(address indexed tokenAddress);

    /**
     * @notice Emitted when an ERC20 token is removed from supported currencies.
     * @param tokenAddress The address of the ERC20 token removed.
     */
    event CurrencyRemoved(address indexed tokenAddress);

    // --- Functions ---

    /**
     * @notice Checks if a given ERC20 token is supported for loans.
     * @param tokenAddress The address of the ERC20 token.
     * @return True if the currency is supported, false otherwise.
     */
    function isCurrencySupported(address tokenAddress) external view returns (bool);

    /**
     * @notice Adds a new ERC20 token to the list of supported currencies.
     * @dev Should be restricted (e.g., Ownable, Governance). Emits CurrencyAdded.
     * @param tokenAddress The address of the ERC20 token to add.
     */
    function addSupportedCurrency(address tokenAddress) external;

    /**
     * @notice Removes an ERC20 token from the list of supported currencies.
     * @dev Should be restricted. Emits CurrencyRemoved.
     * @param tokenAddress The address of the ERC20 token to remove.
     */
    function removeSupportedCurrency(address tokenAddress) external;

    /**
     * @notice Gets a list of all supported currency addresses.
     * @return An array of supported currency addresses.
     */
    function getSupportedCurrencies() external view returns (address[] memory);
}
