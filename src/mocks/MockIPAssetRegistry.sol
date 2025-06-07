// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract MockIPAssetRegistry {
    function ipId(uint256 chainId, address nftContract, uint256 tokenId) external pure returns (address) {
        // For testing, return a deterministic address based on inputs
        return address(uint160(uint256(keccak256(abi.encodePacked(chainId, nftContract, tokenId)))));
    }
}
