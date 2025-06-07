// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRoyaltyModule} from "@storyprotocol/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRoyaltyModule is IRoyaltyModule {
    // Mapping to simulate royalty amounts available for collection
    // ipId => currencyToken => amount
    mapping(address => mapping(address => uint256)) public royaltyAmountsToCollect;
    mapping(address => address) public ipRoyaltyVaults; // Not strictly used by collectRoyaltyTokens but part of interface

    address public lastCollector;
    address public lastIpIdCollected;
    address public lastCurrencyTokenCollected;

    // Function to allow test setup to load funds into this mock module
    function setRoyaltyAmount(address ipId, address currencyToken, uint256 amount) external {
        royaltyAmountsToCollect[ipId][currencyToken] = amount;
    }

    // Function to allow test setup to fund this contract with mock ERC20 tokens
    // This mock module needs to hold tokens to be able to transfer them to RoyaltyManager
    function fundModule(address currencyToken, uint256 amount) external {
        IERC20(currencyToken).transferFrom(msg.sender, address(this), amount);
    }

    function collectRoyaltyTokens(address ipId, address token) external override returns (uint256 collectedAmount) {
        lastCollector = msg.sender; // Should be RoyaltyManager
        lastIpIdCollected = ipId;
        lastCurrencyTokenCollected = token;

        collectedAmount = royaltyAmountsToCollect[ipId][token];
        if (collectedAmount > 0) {
            // Simulate transferring these tokens to the collector (RoyaltyManager)
            require(IERC20(token).balanceOf(address(this)) >= collectedAmount, "MockRoyaltyModule: Insufficient funds to send.");
            IERC20(token).transfer(msg.sender, collectedAmount);
            royaltyAmountsToCollect[ipId][token] = 0; // Clear after collection
        }
        return collectedAmount;
    }

    // --- Other IRoyaltyModule functions (minimal or no-op implementation) ---
    function getRoyaltyPolicy(address) external view override returns (address royaltyPolicy, address snapshotId) {
        return (address(0), address(0));
    }
    function setRoyaltyPolicy(address, address, address) external override {}
    function setRoyaltyPolicyBatch(address[] calldata, address[] calldata, address[] calldata) external override {}
    function onRoyaltyPaid(address, address, uint256) external override {}
    function payRoyaltyOnBehalf(address, address, address, address, uint256) external override {}
    function setIpRoyaltyVault(address, address) external override {}
    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IRoyaltyModule).interfaceId || super.supportsInterface(interfaceId);
    }
}
