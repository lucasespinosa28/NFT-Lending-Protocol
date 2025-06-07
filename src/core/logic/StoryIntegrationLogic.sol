// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; // For currency type, though not directly used for transfers here
import {IRoyaltyManager} from "../../interfaces/IRoyaltyManager.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

/**
 * @title StoryIntegrationLogic
 * @author Your Name/Team
 * @notice Handles interactions with Story Protocol for royalty claims and payments.
 * @dev Separated logic from LoanManagementLogic.
 */
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StoryIntegrationLogic is Ownable, ReentrancyGuard {
    IRoyaltyManager public royaltyManager;
    IIPAssetRegistry public ipAssetRegistry;

    event RoyaltyWithdrawn(
        bytes32 indexed loanId, // Or some other relevant ID
        address indexed ipId,
        address indexed recipient, // lender
        uint256 amount
    );

    constructor(
        address _royaltyManagerAddress,
        address _ipAssetRegistryAddress,
        address _initialOwner // Expected to be LoanManagementLogic or LendingProtocol
    ) Ownable(_initialOwner) {
        require(_royaltyManagerAddress != address(0), "SIL: RoyaltyManager zero address");
        require(_ipAssetRegistryAddress != address(0), "SIL: IPAssetRegistry zero address");

        royaltyManager = IRoyaltyManager(_royaltyManagerAddress);
        ipAssetRegistry = IIPAssetRegistry(_ipAssetRegistryAddress);
    }

    /**
     * @notice Determines the IP ID for a given NFT.
     * @param nftContractAddress The address of the NFT contract.
     * @param nftTokenId The ID of the NFT.
     * @return The IP ID address if registered, otherwise address(0).
     */
    function getIpId(
        address nftContractAddress,
        uint256 nftTokenId
    ) public view returns (address) {
        // block.chainid might not be available or always correct depending on context.
        // Consider if chainId needs to be configurable or passed in.
        // For now, using block.chainid as it was in the original code.
        address retrievedIpId = ipAssetRegistry.ipId(block.chainid, nftContractAddress, nftTokenId);
        if (retrievedIpId != address(0) && ipAssetRegistry.isRegistered(retrievedIpId)) {
            return retrievedIpId;
        }
        return address(0);
    }

    /**
     * @notice Attempts to pay a portion of a debt using Story Protocol royalties.
     * @param loanId Identifier for the loan, used in event.
     * @param effectiveIpId The pre-determined IP ID to use for royalty claim (could be loan.storyIpId or dynamically fetched).
     * @param currency The address of the ERC20 currency for the loan.
     * @param totalRepaymentDue The total amount outstanding on the loan.
     * @param lender The address of the lender to receive royalty payments.
     * @return amountPaidFromRoyalty The amount of debt paid using royalties.
     * @dev This function will claim royalties, check balance, and withdraw if funds are available.
     */
    function attemptRoyaltyPayment(
        bytes32 loanId, // For event logging
        address effectiveIpId,
        address currency,
        uint256 totalRepaymentDue,
        address lender
    ) external nonReentrant returns (uint256 amountPaidFromRoyalty) { // nonReentrant might be good practice
        if (effectiveIpId == address(0)) {
            return 0; // No IP ID, no royalty payment possible.
        }

        // It's assumed that only the owner (LoanManagementLogic) calls this,
        // so msg.sender is not the end-user but the calling contract.
        // The `lender` address is passed explicitly for the withdrawal.

        royaltyManager.claimRoyalty(effectiveIpId, currency); // Claim any pending royalties
        uint256 royaltyBalance = royaltyManager.getRoyaltyBalance(effectiveIpId, currency);

        if (royaltyBalance > 0) {
            amountPaidFromRoyalty = royaltyBalance >= totalRepaymentDue ? totalRepaymentDue : royaltyBalance;

            if (amountPaidFromRoyalty > 0) {
                royaltyManager.withdrawRoyalty(
                    effectiveIpId,
                    currency,
                    lender, // Withdraw directly to the lender
                    amountPaidFromRoyalty
                );
                emit RoyaltyWithdrawn(loanId, effectiveIpId, lender, amountPaidFromRoyalty);
            }
            return amountPaidFromRoyalty;
        }
        return 0;
    }
}
