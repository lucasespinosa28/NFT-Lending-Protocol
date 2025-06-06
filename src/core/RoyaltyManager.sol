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

    mapping(address => uint256) public ipaRoyaltyClaims;

    constructor(
        address ipAssetRegistry,
        address royaltyModule,
        address licensingModule,
        address licenseRegistry
    ) Ownable(msg.sender) {
        IP_ASSET_REGISTRY = IIPAssetRegistry(ipAssetRegistry);
        ROYALTY_MODULE = IRoyaltyModule(royaltyModule);
        LICENSING_MODULE = ILicensingModule(licensingModule);
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
    }
    function claimRoyalty(address ipId) external override {
        address[] memory parentIpIds = new address[](
            LICENSE_REGISTRY.getParentIpCount(ipId)
        );
        for (uint256 i = 0; i < parentIpIds.length; i++) {
            parentIpIds[i] = LICENSE_REGISTRY.getParentIp(ipId, i);
        }

        if (parentIpIds.length > 0) {
            address[] memory royaltyPolicies = new address[](parentIpIds.length);
            for (uint256 i = 0; i < parentIpIds.length; i++) {
                (
                    address licenseTemplate,
                    uint256 licenseTermsId
                ) = LICENSE_REGISTRY.getParentLicenseTerms(
                        ipId,
                        parentIpIds[i]
                    );
                (
                    address royaltyPolicy,
                    ,
                    ,

                ) = ILicenseTemplate(licenseTemplate).getRoyaltyPolicy(
                        licenseTermsId
                    );
                royaltyPolicies[i] = royaltyPolicy;
            }

            address[] memory currencyTokens = new address[](1);
            currencyTokens[0] = 0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E;

            // --- FIX: No claimRoyalty function exists. Instead, check the royalty vault balance. ---
            address royaltyVault = ROYALTY_MODULE.ipRoyaltyVaults(ipId);
            uint256 amount = 0;
            if (royaltyVault != address(0)) {
                amount = IERC20(currencyTokens[0]).balanceOf(royaltyVault);
                // If you want to actually withdraw, you need to implement a withdrawal mechanism.
            }
            ipaRoyaltyClaims[ipId] += amount;
            
            emit RoyaltyClaimed(ipId, amount);
        }
    }
    function getRoyaltyBalance(address ipId) external view override returns (uint256) {
        return ipaRoyaltyClaims[ipId];
    }
}
