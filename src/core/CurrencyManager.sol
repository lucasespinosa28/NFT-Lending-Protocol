// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICurrencyManager} from "../interfaces/ICurrencyManager.sol";

/**
 * @title CurrencyManager
 * @author Lucas Espinosa
 * @notice Manages supported ERC20 currencies for loans.
 * @dev Implements ICurrencyManager. This is a placeholder implementation.
 */
// aderyn-ignore-next-line(centralization-risk)
contract CurrencyManager is ICurrencyManager, Ownable {
    mapping(address => bool) private supportedCurrencies;
    address[] private currencyList;

    /**
     * @notice Constructor to initialize the contract with an initial set of supported currencies.
     * @param initialCurrencies Array of ERC20 token addresses to support at deployment.
     */
    constructor(address[] memory initialCurrencies) Ownable(msg.sender) {
        for (uint256 i = 0; i < initialCurrencies.length; i++) {
            _addSupportedCurrency(initialCurrencies[i]);
        }
    }

    /**
     * @inheritdoc ICurrencyManager
     */
    function isCurrencySupported(address tokenAddress) external view override returns (bool) {
        return supportedCurrencies[tokenAddress];
    }

    /**
     * @inheritdoc ICurrencyManager
     */
    // aderyn-ignore-next-line(centralization-risk)
    function addSupportedCurrency(address tokenAddress) external override onlyOwner {
        _addSupportedCurrency(tokenAddress);
    }

    /**
     * @notice Internal function to add a currency to the supported list.
     * @dev Checks for zero address, contract code, and duplicate entries.
     * @param tokenAddress The address of the ERC20 token to add.
     */
    function _addSupportedCurrency(address tokenAddress) private {
        require(tokenAddress != address(0), "Zero address");
        require(!supportedCurrencies[tokenAddress], "Currency already supported");
        // Basic check if it's a contract (doesn't guarantee ERC20)
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(tokenAddress)
        }
        require(codeSize > 0, "Not a contract address");

        // Optional: Try to call a view function like decimals() to verify ERC20, but can be gas intensive
        // try IERC20(tokenAddress).decimals() returns (uint8) {
        //     // It's likely an ERC20
        // } catch {
        //     revert("Not a valid ERC20 token");
        // }

        supportedCurrencies[tokenAddress] = true;
        currencyList.push(tokenAddress);
        emit CurrencyAdded(tokenAddress);
    }

    /**
     * @inheritdoc ICurrencyManager
     */
    // aderyn-ignore-next-line(centralization-risk)
  function removeSupportedCurrency(address tokenAddress) external override onlyOwner {
    require(tokenAddress != address(0), "Zero address");
    require(supportedCurrencies[tokenAddress], "Currency not supported");

    supportedCurrencies[tokenAddress] = false;

    uint256 len = currencyList.length; // Cache length to avoid repeated SLOAD
    uint256 indexToRemove = len; // Set to len as a sentinel value
    for (uint256 i = 0; i < len; i++) {
        if (currencyList[i] == tokenAddress) {
            indexToRemove = i;
            break;
        }
    }
    if (indexToRemove < len) {
        address lastToken = currencyList[len - 1];
        currencyList[indexToRemove] = lastToken;
        currencyList.pop();
    }
    emit CurrencyRemoved(tokenAddress);
}

    /**
     * @inheritdoc ICurrencyManager
     */
    function getSupportedCurrencies() external view override returns (address[] memory) {
        return currencyList;
    }
}
