// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract MockIIPAssetRegistry is IIPAssetRegistry {
    mapping(address => bool) private _isRegistered; // Renamed from public isRegistered
    mapping(uint256 => mapping(address => mapping(uint256 => address))) public ipAssets;

    // --- IIPAssetRegistry Functions ---

    function register(uint256 chainId, address tokenContract, uint256 tokenId) external override returns (address ipId) {
        ipId = computeIpId(chainId, tokenContract, tokenId);
        _isRegistered[ipId] = true;
        ipAssets[chainId][tokenContract][tokenId] = ipId;
        // Emit IPRegistered event (optional for mock, but good practice)
        emit IPRegistered(ipId, chainId, tokenContract, tokenId, "MockNFT", "", block.timestamp);
        return ipId;
    }

    function ipId(uint256 chainId, address tokenContract, uint256 tokenId) external view override returns (address) {
        return ipAssets[chainId][tokenContract][tokenId];
    }

    // Interface uses `id` as parameter name, ensuring consistency
    function isRegistered(address id) external view override returns (bool) {
        return _isRegistered[id];
    }

    function setRegistrationFee(address /*treasury*/, address /*feeToken*/, uint96 /*feeAmount*/) external override {
        // Emit RegistrationFeeSet event (optional)
    }

    function totalSupply() external view override returns (uint256) {
        return 0; // Mocked value
    }

    function upgradeIPAccountImpl(address /*newIpAccountImpl*/) external override {
        // Mocked
    }

    function getTreasury() external view override returns (address) {
        return address(0); // Mocked value
    }

    function getFeeToken() external view override returns (address) {
        return address(0); // Mocked value
    }

    function getFeeAmount() external view override returns (uint96) {
        return 0; // Mocked value
    }

    // --- IIPAccountRegistry Functions (inherited by IIPAssetRegistry) ---

    function ipAccount(uint256 /*chainId*/, address /*tokenContract*/, uint256 /*tokenId*/) external view override returns (address) {
        return address(0); // Mocked value, could be a mock IPAccount if needed
    }

    function getIPAccountImpl() external view override returns (address) {
        return address(0); // Mocked value
    }

    // --- Helper Functions (not part of the interface, but used by this mock) ---

    function computeIpId(uint256 chainId, address tokenContract, uint256 tokenId) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(chainId, tokenContract, tokenId)))));
    }

    // --- Removed Functions Not in IIPAssetRegistry or IIPAccountRegistry ---
    // EXPIRY_NEVER, POLICY_FRAMEWORK_MANAGER_HOOK_TAG, etc. (all TAG functions)
    // attachLicenseTerms (both overloads)
    // initialize
    // owner
    // pause, paused, unpause
    // proxiableUUID
    // register (overloaded version with string URI etc.)
    // registerDerivative, registerDerivativeWithLicenseTokens
    // setBaseURI, setBeneficiary, setRoyaltyPolicy, setTokenContract
    // supportsInterface
    // upgradeToAndCall
    // metadata, beneficiaryOf, parentIpIdsOf, childIpIdsOf, royaltyPolicyOf
    // tokenContractOf, tokenIdOf, chainIdOf, uri, exists
}
