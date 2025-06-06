// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICurrencyManager} from "../interfaces/ICurrencyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CurrencyManager
 * @author Your Name/Team
 * @notice Manages supported ERC20 currencies for loans.
 * @dev Implements ICurrencyManager. This is a placeholder implementation.
 */
contract CurrencyManager is ICurrencyManager, Ownable {
    mapping(address => bool) private supportedCurrencies;
    address[] private currencyList;

    constructor(address[] memory initialCurrencies) Ownable(msg.sender) {
        for (uint256 i = 0; i < initialCurrencies.length; i++) {
            _addSupportedCurrency(initialCurrencies[i]);
        }
    }

    function isCurrencySupported(address tokenAddress) external view override returns (bool) {
        return supportedCurrencies[tokenAddress];
    }

    function addSupportedCurrency(address tokenAddress) external override onlyOwner {
        _addSupportedCurrency(tokenAddress);
    }

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

    function removeSupportedCurrency(address tokenAddress) external override onlyOwner {
        require(tokenAddress != address(0), "Zero address");
        require(supportedCurrencies[tokenAddress], "Currency not supported");

        supportedCurrencies[tokenAddress] = false;

        // Remove from list (can be gas intensive for large lists)
        for (uint256 i = 0; i < currencyList.length; i++) {
            if (currencyList[i] == tokenAddress) {
                currencyList[i] = currencyList[currencyList.length - 1];
                currencyList.pop();
                break;
            }
        }
        emit CurrencyRemoved(tokenAddress);
    }

    function getSupportedCurrencies() external view override returns (address[] memory) {
        return currencyList;
    }
}
