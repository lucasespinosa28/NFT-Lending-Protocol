// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRoyaltyModule} from "@storyprotocol/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import {IModule} from "@storyprotocol/contracts/interfaces/modules/base/IModule.sol"; // Added import
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRoyaltyModule is IRoyaltyModule {
    // Mapping to simulate royalty amounts available for collection
    // ipId => currencyToken => amount
    mapping(address => mapping(address => uint256)) public royaltyAmountsToCollect;
    mapping(address => address) private _ipRoyaltyVaults_mock_state; // Renamed and made private

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

    function collectRoyaltyTokens(address ipId, address token) external returns (uint256 collectedAmount) {
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
    function getRoyaltyPolicy(address) external view returns (address royaltyPolicy, address snapshotId) { // Removed override
        return (address(0), address(0));
    }
    function setRoyaltyPolicy(address, address, address) external {} // Removed override, not in IRoyaltyModule
    function setRoyaltyPolicyBatch(address[] calldata, address[] calldata, address[] calldata) external {} // Removed override, not in IRoyaltyModule
    function onRoyaltyPaid(address, address, uint256) external {} // Removed override, not in IRoyaltyModule
    // Matches IRoyaltyModule: payRoyaltyOnBehalf(address receiverIpId, address payerIpId, address token, uint256 amount)
    function payRoyaltyOnBehalf(address receiverIpId, address payerIpId, address token, uint256 amount) external override {}
    function setIpRoyaltyVault(address, address) external {} // Removed override, not in IRoyaltyModule
    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        // Assuming IModule provides a base supportsInterface or this mock is intended to be basic
        return interfaceId == type(IRoyaltyModule).interfaceId || interfaceId == type(IModule).interfaceId;
    }

    // --- BEGIN Stubs for IRoyaltyModule ---
    function accumulatedRoyaltyPolicies(address) external view override returns (address[] memory) {
        return new address[](0);
    }
    function globalRoyaltyStack(address) external view override returns (uint32) {
        return 0;
    }
    function hasAncestorIp(address, address) external override returns (bool) { // Removed view as it's not in interface spec
        return false;
    }
    function isIpRoyaltyVault(address) external view override returns (bool) {
        return false;
    }
    function isRegisteredExternalRoyaltyPolicy(address) external view override returns (bool) {
        return false;
    }
    function isWhitelistedRoyaltyPolicy(address) external view override returns (bool) {
        return false;
    }
    function isWhitelistedRoyaltyToken(address) external view override returns (bool) {
        return false;
    }
    function maxAccumulatedRoyaltyPolicies() external view override returns (uint256) {
        return 0;
    }
    function maxAncestors() external view override returns (uint256) {
        return 0;
    }
    function maxParents() external view override returns (uint256) {
        return 0;
    }
    function maxPercent() external pure override returns (uint32) {
        return 10000; // e.g., 100% with 2 decimal places
    }
    function name() external override returns (string memory) { // Removed view, IModule.name() is not view
        return "MockRoyaltyModule";
    }
    function onLicenseMinting(address, address, uint32, bytes calldata) external override {}
    function onLinkToParents(address, address[] calldata, address[] calldata, uint32[] calldata, bytes calldata, uint32) external override {}
    function payLicenseMintingFee(address, address, address, uint256) external override {}
    function registerExternalRoyaltyPolicy(address) external override {}
    function royaltyFeePercent() external view override returns (uint32) {
        return 0;
    }
    function setRoyaltyFeePercent(uint32) external override {}
    function setRoyaltyLimits(uint256) external override {}
    function setTreasury(address) external override {}
    function totalRevenueTokensAccounted(address, address, address) external view override returns (uint256) {
        return 0;
    }
    function totalRevenueTokensReceived(address, address) external view override returns (uint256) {
        return 0;
    }
    function treasury() external view override returns (address) {
        return address(0);
    }
    function whitelistRoyaltyPolicy(address, bool) external override {}
    function whitelistRoyaltyToken(address, bool) external override {}

    // Added from interface, was missing in error list but present in IRoyaltyModule.sol
    function ipRoyaltyVaults(address) external view override returns (address) {
        return address(0);
    }
    // --- END Stubs for IRoyaltyModule ---
}
