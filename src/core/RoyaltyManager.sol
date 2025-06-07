// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IRoyaltyModule} from "@storyprotocol/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import {ILicensingModule} from "@storyprotocol/contracts/interfaces/modules/licensing/ILicensingModule.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";
import {ILicenseRegistry} from "@storyprotocol/contracts/interfaces/registries/ILicenseRegistry.sol";
import {ILicenseTemplate} from "@storyprotocol/contracts/interfaces/modules/licensing/ILicenseTemplate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRoyaltyManager} from "../interfaces/IRoyaltyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RoyaltyManager is IRoyaltyManager, Ownable {
    IIPAssetRegistry public immutable IP_ASSET_REGISTRY;
    IRoyaltyModule public immutable ROYALTY_MODULE;
    ILicensingModule public immutable LICENSING_MODULE;
    ILicenseRegistry public immutable LICENSE_REGISTRY;

    mapping(address => mapping(address => uint256)) public ipaRoyaltyClaims; // ipId => currencyToken => balanceHeldByRoyaltyManager

    constructor(address ipAssetRegistry, address royaltyModule, address licensingModule, address licenseRegistry)
        Ownable(msg.sender)
    {
        IP_ASSET_REGISTRY = IIPAssetRegistry(ipAssetRegistry);
        ROYALTY_MODULE = IRoyaltyModule(royaltyModule);
        LICENSING_MODULE = ILicensingModule(licensingModule);
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
    }

    function claimRoyalty(address ipId, address currencyToken) external override {
        require(ipId != address(0), "RM: IP ID cannot be zero address");
        require(currencyToken != address(0), "RM: Currency token cannot be zero address");

        // Call Story Protocol's RoyaltyModule to collect tokens.
        // This function transfers the tokens to this contract (RoyaltyManager) and returns the amount.
        uint256 collectedAmount = ROYALTY_MODULE.collectRoyaltyTokens(ipId, currencyToken);

        if (collectedAmount > 0) {
            ipaRoyaltyClaims[ipId][currencyToken] += collectedAmount;
            emit RoyaltyClaimed(ipId, collectedAmount); // Existing event
        }
    }

    function getRoyaltyBalance(address ipId, address currencyToken) external view override returns (uint256) {
        require(ipId != address(0), "RM: IP ID cannot be zero address");
        require(currencyToken != address(0), "RM: Currency token cannot be zero address");
        return ipaRoyaltyClaims[ipId][currencyToken];
    }

    function withdrawRoyalty(address ipId, address currencyToken, address recipient, uint256 amount) external override {
        require(ipId != address(0), "RM: IP ID cannot be zero address");
        require(currencyToken != address(0), "RM: Currency token cannot be zero address");
        require(recipient != address(0), "RM: Recipient cannot be zero address");
        require(amount > 0, "RM: Amount must be greater than zero");

        uint256 currentBalance = ipaRoyaltyClaims[ipId][currencyToken];
        require(currentBalance >= amount, "RM: Insufficient royalty balance for withdrawal");

        ipaRoyaltyClaims[ipId][currencyToken] = currentBalance - amount;

        // Transfer the ERC20 tokens to the recipient
        IERC20(currencyToken).transfer(recipient, amount);

        // Consider adding a new event RoyaltyWithdrawn if detailed logging is needed.
    }
}
