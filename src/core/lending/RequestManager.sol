// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILendingProtocol} from "../../interfaces/ILendingProtocol.sol";
import {ICurrencyManager} from "../../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../../interfaces/ICollectionManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RequestManager is ReentrancyGuard {
    // --- State Variables ---
    mapping(bytes32 => ILendingProtocol.LoanRequest) public loanRequests;
    uint256 internal requestCounter; // Internal to be accessible by LendingProtocol or for internal logic

    // --- Events ---
    // Events are defined in ILendingProtocol.sol and will be emitted by LendingProtocol

    // --- External Dependencies (to be provided by inheriting contract, e.g., LendingProtocol) ---
    function _getCurrencyManager() internal view virtual returns (ICurrencyManager) {
        // revert("RequestManager: CurrencyManager not set");
        return ICurrencyManager(address(0));
    }

    function _getCollectionManager() internal view virtual returns (ICollectionManager) {
        // revert("RequestManager: CollectionManager not set");
        return ICollectionManager(address(0));
    }

    // --- Functions ---

    /**
     * @notice Creates a loan request.
     * @param params Parameters for the loan request.
     * @return requestId The ID of the newly created loan request.
     */
    function makeLoanRequest(ILendingProtocol.LoanRequestParams calldata params)
        public
        virtual
        nonReentrant
        returns (bytes32 requestId)
    {
        ICurrencyManager currencyManager = _getCurrencyManager();
        ICollectionManager collectionManager = _getCollectionManager();

        require(currencyManager.isCurrencySupported(params.currency), "RM: Currency not supported");
        require(collectionManager.isCollectionWhitelisted(params.nftContract), "RM: Collection not whitelisted");
        require(IERC721(params.nftContract).ownerOf(params.nftTokenId) == msg.sender, "RM: Not NFT owner");
        // It's also good practice to check if the protocol is approved to transfer this NFT upon acceptance.
        // However, this might be better handled at the point of acceptance or require pre-approval.
        // For now, owner check is the primary gate here.

        require(params.principalAmount > 0, "RM: Principal must be > 0");
        require(params.durationSeconds > 0, "RM: Duration must be > 0");
        require(params.expirationTimestamp > block.timestamp, "RM: Expiration in past");

        requestCounter++;
        requestId = keccak256(
            abi.encodePacked(
                "loanRequest", requestCounter, msg.sender, block.timestamp, params.nftContract, params.nftTokenId
            )
        );

        loanRequests[requestId] = ILendingProtocol.LoanRequest({
            requestId: requestId,
            borrower: msg.sender,
            nftContract: params.nftContract,
            nftTokenId: params.nftTokenId,
            currency: params.currency,
            principalAmount: params.principalAmount,
            interestRateAPR: params.interestRateAPR,
            durationSeconds: params.durationSeconds,
            expirationTimestamp: params.expirationTimestamp,
            isActive: true
        });

        // Event emission will be handled by LendingProtocol after this call.
        // emit ILendingProtocol.LoanRequestMade(...);
        return requestId;
    }

    /**
     * @notice Cancels an active loan request.
     * @param requestId The ID of the loan request to cancel.
     */
    function cancelLoanRequest(bytes32 requestId) public virtual nonReentrant {
        ILendingProtocol.LoanRequest storage request = loanRequests[requestId];
        require(request.borrower == msg.sender, "RM: Not request owner");
        require(request.isActive, "RM: Request not active");

        request.isActive = false;

        // Event emission will be handled by LendingProtocol.
        // emit ILendingProtocol.LoanRequestCancelled(requestId, msg.sender);
    }

    /**
     * @notice Retrieves details of a specific loan request.
     * @param requestId The ID of the loan request.
     * @return The LoanRequest struct.
     */
    function getLoanRequest(bytes32 requestId) public view virtual returns (ILendingProtocol.LoanRequest memory) {
        return loanRequests[requestId];
    }

    /**
     * @notice Sets a loan request as inactive. Typically called when a request is accepted.
     * @dev Meant to be called internally by LoanManager/LendingProtocol.
     * @param requestId The ID of the loan request to deactivate.
     */
    function _setLoanRequestInactive(bytes32 requestId) internal virtual {
        ILendingProtocol.LoanRequest storage request = loanRequests[requestId];
        require(request.isActive, "RM: Request already inactive or does not exist");
        request.isActive = false;
    }
}
