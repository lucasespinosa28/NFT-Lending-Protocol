// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721 as ExternalIERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155 as ExternalIERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IVaultsFactory} from "../interfaces/IVaultsFactory.sol";

/**
 * @title VaultsFactory
 * @author Lucas Espinosa
 * @notice Creates and manages ERC721-compliant vaults for bundling NFTs.
 * @dev Each vault is an ERC721 token minted by this factory.
 * This contract will also act as the ERC721 contract for the vaults themselves.
 */
contract VaultsFactory is IVaultsFactory, ERC721, Ownable, IERC721Receiver, IERC1155Receiver {
    /**
     * @notice Struct representing the content of a vault.
     * @param items Array of NFT items in the vault.
     * @param exists True if the vault exists.
     */
    struct VaultContent {
        IVaultsFactory.NFTItem[] items;
        bool exists;
    }

    mapping(uint256 => VaultContent) private vaultContents; // vaultId => content
    uint256 private vaultCounter;

    // Address of this contract, used for checking if NFT is a vault managed by this factory
    address public immutable selfAddress;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) Ownable(msg.sender) {
        selfAddress = address(this);
    }

    /**
     * @notice Internal function to check if a token ID has been minted.
     * @param tokenId The token ID to check.
     * @return True if minted, false otherwise.
     */
    function _isMinted(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function mintVault(
        address owner,
        IVaultsFactory.NFTItem[] calldata nftItems // Type comes from interface
    ) external override returns (uint256 vaultId) {
        require(owner != address(0), "Owner cannot be zero address");
        require(nftItems.length > 0, "Cannot create empty vault");

        vaultCounter++;
        vaultId = vaultCounter; // Simple counter for unique vault IDs

        _mint(owner, vaultId); // Mint the new ERC721 vault token to the owner

        VaultContent storage newVaultContent = vaultContents[vaultId];
        newVaultContent.exists = true; // Mark that this vaultId has associated content data

        for (uint256 i = 0; i < nftItems.length; i++) {
            // nftItems[i] is already IVaultsFactory.NFTItem calldata
            IVaultsFactory.NFTItem calldata item = nftItems[i];
            require(item.contractAddress != address(0), "NFT contract is zero address");

            if (item.isERC1155) {
                ExternalIERC1155(item.contractAddress).safeTransferFrom(
                    msg.sender, // NFTs are transferred from the caller (who should own/be approved for them)
                    address(this), // VaultsFactory holds the NFTs
                    item.tokenId,
                    item.amount,
                    abi.encodePacked(vaultId) // data, could be used to identify the vault
                );
                // Pushing a qualified IVaultsFactory.NFTItem
                newVaultContent.items.push(
                    IVaultsFactory.NFTItem(item.contractAddress, item.tokenId, item.amount, true)
                );
            } else {
                // ERC721
                ExternalIERC721(item.contractAddress).safeTransferFrom(msg.sender, address(this), item.tokenId);
                // Pushing a qualified IVaultsFactory.NFTItem
                newVaultContent.items.push(IVaultsFactory.NFTItem(item.contractAddress, item.tokenId, 1, false));
            }
        }

        emit VaultCreated(vaultId, owner, _getNftContracts(nftItems), _getTokenIds(nftItems), _getAmounts(nftItems));
        return vaultId;
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function addContentToVault(
        uint256 vaultId,
        IVaultsFactory.NFTItem[] calldata nftItems // Type comes from interface
    ) external override {
        require(_isMinted(vaultId), "Vault does not exist"); // Use _isMinted (which uses _ownerOf)
        require(ownerOf(vaultId) == msg.sender, "Not vault owner");
        require(nftItems.length > 0, "No items to add");

        VaultContent storage currentVaultContent = vaultContents[vaultId];
        require(currentVaultContent.exists, "Vault content data missing");

        for (uint256 i = 0; i < nftItems.length; i++) {
            IVaultsFactory.NFTItem calldata item = nftItems[i];
            require(item.contractAddress != address(0), "NFT contract is zero address");

            if (item.isERC1155) {
                ExternalIERC1155(item.contractAddress).safeTransferFrom(
                    msg.sender, address(this), item.tokenId, item.amount, abi.encodePacked(vaultId)
                );
                currentVaultContent.items.push(
                    IVaultsFactory.NFTItem(item.contractAddress, item.tokenId, item.amount, true)
                );
            } else {
                // ERC721
                ExternalIERC721(item.contractAddress).safeTransferFrom(msg.sender, address(this), item.tokenId);
                currentVaultContent.items.push(IVaultsFactory.NFTItem(item.contractAddress, item.tokenId, 1, false));
            }
        }
        emit VaultContentAdded(vaultId, _getNftContracts(nftItems), _getTokenIds(nftItems), _getAmounts(nftItems));
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function removeContentFromVault(
        uint256 vaultId,
        IVaultsFactory.NFTItem[] calldata nftItemsToRemove // Type comes from interface
    ) external override {
        require(_isMinted(vaultId), "Vault does not exist"); // Use _isMinted
        require(ownerOf(vaultId) == msg.sender, "Not vault owner");
        require(nftItemsToRemove.length > 0, "No items specified for removal");

        VaultContent storage currentVaultContent = vaultContents[vaultId];
        require(currentVaultContent.exists, "Vault content data missing");
        require(currentVaultContent.items.length >= nftItemsToRemove.length, "Removing too many items");

        for (uint256 i = 0; i < nftItemsToRemove.length; i++) {
            IVaultsFactory.NFTItem calldata itemToRemove = nftItemsToRemove[i];
            bool foundAndRemoved = false;
            for (uint256 j = 0; j < currentVaultContent.items.length; j++) {
                // currentVaultContent.items[j] is IVaultsFactory.NFTItem storage
                IVaultsFactory.NFTItem storage currentItem = currentVaultContent.items[j];
                if (
                    currentItem.contractAddress == itemToRemove.contractAddress
                        && currentItem.tokenId == itemToRemove.tokenId && currentItem.isERC1155 == itemToRemove.isERC1155
                        && (!itemToRemove.isERC1155 || currentItem.amount >= itemToRemove.amount)
                ) {
                    if (itemToRemove.isERC1155) {
                        ExternalIERC1155(itemToRemove.contractAddress).safeTransferFrom(
                            address(this), msg.sender, itemToRemove.tokenId, itemToRemove.amount, ""
                        );
                        currentItem.amount -= itemToRemove.amount;
                        if (currentItem.amount == 0) {
                            currentVaultContent.items[j] =
                                currentVaultContent.items[currentVaultContent.items.length - 1];
                            currentVaultContent.items.pop();
                        }
                    } else {
                        // ERC721
                        ExternalIERC721(itemToRemove.contractAddress).safeTransferFrom(
                            address(this), msg.sender, itemToRemove.tokenId
                        );
                        currentVaultContent.items[j] = currentVaultContent.items[currentVaultContent.items.length - 1];
                        currentVaultContent.items.pop();
                    }
                    foundAndRemoved = true;
                    break;
                }
            }
            require(foundAndRemoved, "Item to remove not found in vault or insufficient amount");
        }
        emit VaultContentRemoved(
            vaultId, _getNftContracts(nftItemsToRemove), _getTokenIds(nftItemsToRemove), _getAmounts(nftItemsToRemove)
        );
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function burnVault(uint256 vaultId) external override {
        require(_isMinted(vaultId), "Vault does not exist"); // Use _isMinted
        require(ownerOf(vaultId) == msg.sender, "Not vault owner");

        VaultContent storage currentVaultContent = vaultContents[vaultId];
        require(currentVaultContent.exists, "Vault content data missing for burn");
        // itemsToReturn will be an array of IVaultsFactory.NFTItem memory
        IVaultsFactory.NFTItem[] memory itemsToReturn = currentVaultContent.items;

        for (uint256 i = 0; i < itemsToReturn.length; i++) {
            IVaultsFactory.NFTItem memory item = itemsToReturn[i];
            if (item.isERC1155) {
                ExternalIERC1155(item.contractAddress).safeTransferFrom(
                    address(this), msg.sender, item.tokenId, item.amount, ""
                );
            } else {
                // ERC721
                ExternalIERC721(item.contractAddress).safeTransferFrom(address(this), msg.sender, item.tokenId);
            }
        }

        delete vaultContents[vaultId]; // Clear storage for the vault content data
        _burn(vaultId); // Burn the ERC721 vault token
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function getVaultContent(uint256 vaultId) external view override returns (IVaultsFactory.NFTItem[] memory) {
        // Return type from interface
        require(_isMinted(vaultId), "Vault token ID not minted");
        require(vaultContents[vaultId].exists, "Vault content data does not exist or is empty");
        return vaultContents[vaultId].items;
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function isVault(uint256 vaultId) external view override returns (bool) {
        // A token ID is a vault if it has been minted by this contract.
        return _isMinted(vaultId);
    }

    /**
     * @inheritdoc IVaultsFactory
     */
    function ownerOfVault(uint256 vaultId) external view override returns (address) {
        // Return type from interface
        require(_isMinted(vaultId), "Vault token ID not minted"); // Check if the token has an owner
        return ERC721.ownerOf(vaultId); // ownerOf itself will revert if token doesn't exist.
    }

    // --- IERC721Receiver ---
    /**
     * @notice Handles receipt of ERC721 tokens.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    // --- IERC1155Receiver ---
    /**
     * @notice Handles receipt of a single ERC1155 token type.
     */
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @notice Handles receipt of multiple ERC1155 token types.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // --- Helpers to extract arrays for events ---
    /**
     * @notice Helper to extract NFT contract addresses from NFTItem array.
     */
    function _getNftContracts(IVaultsFactory.NFTItem[] calldata nftItems) private pure returns (address[] memory) {
        address[] memory contracts = new address[](nftItems.length);
        for (uint256 i = 0; i < nftItems.length; i++) {
            contracts[i] = nftItems[i].contractAddress;
        }
        return contracts;
    }

    /**
     * @notice Helper to extract token IDs from NFTItem array.
     */
    function _getTokenIds(IVaultsFactory.NFTItem[] calldata nftItems) private pure returns (uint256[] memory) {
        uint256[] memory tokenIds = new uint256[](nftItems.length);
        for (uint256 i = 0; i < nftItems.length; i++) {
            tokenIds[i] = nftItems[i].tokenId;
        }
        return tokenIds;
    }

    /**
     * @notice Helper to extract amounts from NFTItem array.
     */
    function _getAmounts(IVaultsFactory.NFTItem[] calldata nftItems) private pure returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](nftItems.length);
        for (uint256 i = 0; i < nftItems.length; i++) {
            amounts[i] = nftItems[i].amount;
        }
        return amounts;
    }

    /**
     * @notice Returns the base URI for vault metadata.
     */
    function _baseURI() internal view override returns (string memory) {
        return "api/vault/"; // Placeholder
    }

    /**
     * @notice Checks if the contract supports a given interface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IVaultsFactory).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
