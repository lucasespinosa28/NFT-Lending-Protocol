// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract MockIIPAssetRegistry is IIPAssetRegistry {
    mapping(address => bool) private _isRegistered; // Renamed from public isRegistered
    mapping(uint256 => mapping(address => mapping(uint256 => address))) public ipAssets;

    // --- IIPAssetRegistry Functions ---

    function register(uint256 chainId, address tokenContract, uint256 tokenId)
        external
        override
        returns (address _ipId)
    {
        _ipId = computeIpId(chainId, tokenContract, tokenId);
        _isRegistered[_ipId] = true;
        ipAssets[chainId][tokenContract][tokenId] = _ipId;
        // Emit IPRegistered event (optional for mock, but good practice)
        emit IPRegistered(_ipId, chainId, tokenContract, tokenId, "MockNFT", "", block.timestamp);
        return _ipId;
    }

    function ipId(uint256 chainId, address tokenContract, uint256 tokenId) external view override returns (address) {
        return ipAssets[chainId][tokenContract][tokenId];
    }

    // Interface uses `id` as parameter name, ensuring consistency
    function isRegistered(address id) external view override returns (bool) {
        return _isRegistered[id];
    }
    // aderyn-fp-next-line(empty-block)

    function setRegistrationFee(address, /*treasury*/ address, /*feeToken*/ uint96 /*feeAmount*/ ) external override {
        // Emit RegistrationFeeSet event (optional)
        return;
    }
    // aderyn-fp-next-line(empty-block)

    function totalSupply() external pure override returns (uint256) {
        return 0; // Mocked value
    }
    // aderyn-fp-next-line(empty-block)

    function upgradeIPAccountImpl(address /*newIpAccountImpl*/ ) external override {
        return;
    }

    function getTreasury() external pure override returns (address) {
        return address(0); // Mocked value
    }

    function getFeeToken() external pure override returns (address) {
        return address(0); // Mocked value
    }

    function getFeeAmount() external pure override returns (uint96) {
        return 0; // Mocked value
    }

    // --- IIPAccountRegistry Functions (inherited by IIPAssetRegistry) ---

    function ipAccount(uint256, /*chainId*/ address, /*tokenContract*/ uint256 /*tokenId*/ )
        external
        pure
        override
        returns (address)
    {
        return address(0); // Mocked value, could be a mock IPAccount if needed
    }

    function getIPAccountImpl() external pure override returns (address) {
        return address(0); // Mocked value
    }

    // --- Helper Functions (not part of the interface, but used by this mock) ---

    function computeIpId(uint256 chainId, address tokenContract, uint256 tokenId) public pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(chainId, tokenContract, tokenId)))));
    }
}
