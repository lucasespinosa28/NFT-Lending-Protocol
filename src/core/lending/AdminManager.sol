// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../../interfaces/ICollectionManager.sol";
import {ILiquidation} from "../../interfaces/ILiquidation.sol";
import {IPurchaseBundler} from "../../interfaces/IPurchaseBundler.sol";
import {IRoyaltyManager} from "../../interfaces/IRoyaltyManager.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

// This contract will be inherited by LendingProtocol.
// The state variables like currencyManager, collectionManager, etc.,
// are expected to be declared in LendingProtocol and made accessible
// (e.g. public or internal) so these functions can modify them.

contract AdminManager is Ownable {
    constructor() Ownable(msg.sender) {
        // The Ownable constructor is called with msg.sender, which will be the deployer
        // of the LendingProtocol contract, effectively making the LendingProtocol deployer
        // the initial owner.
    }

    using SafeERC20 for IERC20;

    // --- Placeholder functions to be implemented by LendingProtocol ---
    // These functions ensure that AdminManager can interact with the
    // state variables that will reside in LendingProtocol.
    // LendingProtocol will override these to provide access to its state.

    function _setCurrencyManager(ICurrencyManager newManager) internal virtual { revert("AM: Not implemented"); }
    function _setCollectionManager(ICollectionManager newManager) internal virtual { revert("AM: Not implemented"); }
    function _setLiquidationContract(ILiquidation newContract) internal virtual { revert("AM: Not implemented"); }
    function _setPurchaseBundler(IPurchaseBundler newBundler) internal virtual { revert("AM: Not implemented"); }
    function _setRoyaltyManager(IRoyaltyManager newManager) internal virtual { revert("AM: Not implemented"); }
    function _setIpAssetRegistry(IIPAssetRegistry newRegistry) internal virtual { revert("AM: Not implemented"); }


    // --- Admin Functions ---

    /**
     * @notice Sets a new CurrencyManager contract address.
     * @param newManager The address of the new CurrencyManager.
     */
    function setCurrencyManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        _setCurrencyManager(ICurrencyManager(newManager));
    }

    /**
     * @notice Sets a new CollectionManager contract address.
     * @param newManager The address of the new CollectionManager.
     */
    function setCollectionManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        _setCollectionManager(ICollectionManager(newManager));
    }

    /**
     * @notice Sets a new Liquidation contract address.
     * @param newContract The address of the new Liquidation contract.
     */
    function setLiquidationContract(address newContract) external onlyOwner {
        require(newContract != address(0), "zero address");
        _setLiquidationContract(ILiquidation(newContract));
    }

    /**
     * @notice Sets a new PurchaseBundler contract address.
     * @param newBundler The address of the new PurchaseBundler.
     */
    function setPurchaseBundler(address newBundler) external onlyOwner {
        require(newBundler != address(0), "zero address");
        _setPurchaseBundler(IPurchaseBundler(newBundler));
    }

    /**
     * @notice Sets a new RoyaltyManager contract address.
     * @param newManager The address of the new RoyaltyManager.
     */
    function setRoyaltyManager(address newManager) external onlyOwner {
        require(newManager != address(0), "zero address");
        _setRoyaltyManager(IRoyaltyManager(newManager));
    }

    /**
     * @notice Sets a new IPAssetRegistry contract address.
     * @param newRegistry The address of the new IPAssetRegistry.
     */
    function setIpAssetRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "zero address");
        _setIpAssetRegistry(IIPAssetRegistry(newRegistry));
    }

    /**
     * @notice Emergency function to withdraw ERC20 tokens from the contract.
     * @param token The address of the ERC20 token.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Emergency function to withdraw ERC721 tokens from the contract.
     * @param nftContract The address of the NFT contract.
     * @param to The recipient address.
     * @param tokenId The token ID to withdraw.
     */
    function emergencyWithdrawERC721(address nftContract, address to, uint256 tokenId) external onlyOwner {
        // This contract (AdminManager itself) is the owner of the NFT if it was transferred to LendingProtocol
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }

    /**
     * @notice Emergency function to withdraw native ETH from the contract.
     * @param to The recipient address.
     * @param amount The amount to withdraw.
     */
    function emergencyWithdrawNative(address payable to, uint256 amount) external onlyOwner {
        (bool success,) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }
}
