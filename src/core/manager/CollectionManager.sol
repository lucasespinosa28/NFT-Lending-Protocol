// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ICollectionManager} from "../../interfaces/ICollectionManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // Changed to OpenZeppelin
/**
 * @title CollectionManager
 * @author Lucas Espinosa
 * @notice Manages whitelisted NFT collections for collateral.
 * @dev Implements ICollectionManager. This is a placeholder implementation.
 */
// aderyn-ignore-next-line(centralization-risk)
contract CollectionManager is ICollectionManager, Ownable, ReentrancyGuard {
    mapping(address => bool) private whitelistedCollections;
    address[] private collectionList;
    // mapping(address => uint256) public collectionMaxLTVs; // Example for LTV

    constructor(
        address owner,
        address[] memory initialCollections
    ) Ownable(owner) {
        for (uint256 i = 0; i < initialCollections.length; i++) {
            _addWhitelistedCollection(initialCollections[i]);
        }
    }

    function isCollectionWhitelisted(
        address collectionAddress
    ) external view override returns (bool) {
        return whitelistedCollections[collectionAddress];
    }
    // aderyn-ignore-next-line(centralization-risk)
    function addWhitelistedCollection(
        address collectionAddress
    )
        external
        override
        // aderyn-ignore-next-line(centralization-risk)
        onlyOwner
    {
        _addWhitelistedCollection(collectionAddress);
    }

    function _addWhitelistedCollection(address collectionAddress) private {
        require(collectionAddress != address(0), "Zero address");
        require(
            !whitelistedCollections[collectionAddress],
            "Collection already whitelisted"
        );

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(collectionAddress)
        }
        require(codeSize > 0, "Not a contract address");

        // Optional: Check if it supports ERC721 or ERC1155 interface
        // try IERC721(collectionAddress).supportsInterface(type(IERC721).interfaceId) returns (bool supported) {
        //     require(supported, "Not an ERC721");
        // } catch {
        //     revert("Not an ERC721 (or check failed)");
        // }

        whitelistedCollections[collectionAddress] = true;
        collectionList.push(collectionAddress);
        emit CollectionWhitelisted(collectionAddress);
    }

    function removeWhitelistedCollection(
        address collectionAddress
    )
        external
        override
        // aderyn-ignore-next-line(centralization-risk)
        onlyOwner
    {
        require(collectionAddress != address(0), "Zero address");
        require(
            whitelistedCollections[collectionAddress],
            "Collection not whitelisted"
        );

        whitelistedCollections[collectionAddress] = false;

        for (uint256 i = 0; i < collectionList.length; i++) {
            if (collectionList[i] == collectionAddress) {
                collectionList[i] = collectionList[collectionList.length - 1];
                collectionList.pop();
                break;
            }
        }
        emit CollectionRemoved(collectionAddress);
    }

    function getWhitelistedCollections()
        external
        view
        override
        returns (address[] memory)
    {
        return collectionList;
    }
}
