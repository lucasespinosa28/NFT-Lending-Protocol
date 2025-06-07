// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract MockIPAssetRegistry is IIPAssetRegistry {
    // Mock storage
    uint256 private _totalSupply;
    address private _treasury;
    address private _feeToken;
    uint96 private _feeAmount;
    mapping(address => bool) private _registered;
    address private _ipAccountImpl;

    function ipId(uint256 chainId, address nftContract, uint256 tokenId) public view override returns (address) {
        // For testing, return a deterministic address based on inputs
        return address(uint160(uint256(keccak256(abi.encodePacked(chainId, nftContract, tokenId)))));
    }

    function setRegistrationFee(address treasury, address feeToken, uint96 feeAmount) external override {
        _treasury = treasury;
        _feeToken = feeToken;
        _feeAmount = feeAmount;
        emit RegistrationFeeSet(treasury, feeToken, feeAmount);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function register(uint256 chainid, address tokenContract, uint256 tokenId) external override returns (address id) {
        id = ipId(chainid, tokenContract, tokenId);
        _registered[id] = true;
        _totalSupply += 1;
        emit IPRegistered(id, chainid, tokenContract, tokenId, "MockName", "MockURI", block.timestamp);
    }

    function getIPAccountImpl() external view override returns (address) {
        return _ipAccountImpl;
    }

    function upgradeIPAccountImpl(address /*newIpAccountImpl*/ ) external pure override {
        // No-op for mock
    }

    function isRegistered(address id) external view override returns (bool) {
        return _registered[id];
    }

    function getTreasury() external view override returns (address) {
        return _treasury;
    }

    function getFeeToken() external view override returns (address) {
        return _feeToken;
    }

    function getFeeAmount() external view override returns (uint96) {
        return _feeAmount;
    }

    function ipAccount(uint256 chainId, address tokenContract, uint256 tokenId) external view override returns (address) {
        // Mock logic, e.g., same as ipId
        return ipId(chainId, tokenContract, tokenId);
    }
}
