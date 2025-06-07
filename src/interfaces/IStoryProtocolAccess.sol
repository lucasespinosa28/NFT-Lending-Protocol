// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IStoryProtocolAccess
 * @author Your Name/Team
 * @notice Interface defining structures for interacting with Story Protocol.
 * This helps the lending protocol locate necessary Story Protocol contracts.
 */
interface IStoryProtocolAccess {
    /**
     * @notice Holds the addresses of key Story Protocol contracts.
     * @param ipAssetRegistry The address of Story Protocol's IPAssetRegistry.
     * @param royaltyModule The address of Story Protocol's RoyaltyModule.
     */
    struct StoryProtocolAddresses {
        address ipAssetRegistry; // To resolve NFT to storyIpId and verify IP registration
        address royaltyModule; // To find IpRoyaltyVault for a storyIpId
    }
}
