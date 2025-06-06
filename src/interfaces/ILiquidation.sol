// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ILiquidation
 * @author Your Name/Team
 * @notice Interface for managing the liquidation process of defaulted loans.
 * This includes buyouts for multi-tranche loans and auctions.
 */
interface ILiquidation {
    enum AuctionStatus {
        PENDING,
        ACTIVE,
        ENDED_NO_BIDS,
        ENDED_SOLD,
        SETTLED
    }

    struct Auction {
        bytes32 loanId;
        address nftContract;
        uint256 nftTokenId;
        bool isVault;
        address currency; // Currency for bidding
        uint256 startingBid; // Could be outstanding debt or a fraction
        uint256 highestBid;
        address highestBidder;
        uint64 startTime;
        uint64 endTime;
        AuctionStatus status;
        address[] lenders; // Lenders involved in this loan (for multi-tranche)
        uint256[] lenderShares; // Pro-rata shares or principal amounts for distribution
    }

    // --- Events ---
    event BuyoutInitiated(
        bytes32 indexed loanId, address indexed largestLender, uint256 buyoutPrice, uint64 buyoutDeadline
    );
    event BuyoutCompleted( // The largest lender who bought out others
        bytes32 indexed loanId, address indexed buyer, uint256 amountPaid
    );
    event BuyoutFailed(bytes32 indexed loanId); // e.g. deadline passed

    event AuctionStarted( // Could be loanId or a new ID
        bytes32 indexed auctionId,
        bytes32 indexed loanId,
        address nftContract,
        uint256 nftTokenId,
        uint256 startingBid,
        uint64 endTime
    );
    event BidPlaced(bytes32 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionEnded( // address(0) if no bids
        bytes32 indexed auctionId, address winner, uint256 winningBid
    );
    event ProceedsDistributed(bytes32 indexed auctionId, uint256 totalProceeds);
    event CollateralClaimedPostAuction( // If auction fails and original lender(s) claim
        bytes32 indexed auctionId, address claimer
    );

    // --- Functions ---

    /**
     * @notice Initiates the largest lien buyout process for a defaulted multi-tranche loan.
     * @dev Called by the main lending protocol or an authorized party.
     * @param loanId The ID of the defaulted loan.
     * @param largestLender The address of the lender with the largest principal.
     * @param buyoutPrice The total amount required to buy out other tranches.
     * @param buyoutDeadline Timestamp by which the buyout must be completed.
     */
    function initiateBuyout(bytes32 loanId, address largestLender, uint256 buyoutPrice, uint64 buyoutDeadline)
        external;

    /**
     * @notice Allows the largest lender to execute the buyout of other tranches.
     * @dev Transfers funds from the largest lender to other lenders.
     * @param loanId The ID of the loan being bought out.
     */
    function executeBuyout(bytes32 loanId) external payable; // payable if currency is ETH/WETH

    /**
     * @notice Initiates a 72-hour English auction if no buyout occurs or for single-lender defaults.
     * @dev Called by the main lending protocol.
     * @param loanId The ID of the defaulted loan.
     * @param nftContract Address of the collateral NFT.
     * @param nftTokenId Token ID of the collateral NFT.
     * @param isVault True if the collateral is a vault.
     * @param currency Address of the currency for bidding.
     * @param startingBid The minimum bid to start the auction (e.g., outstanding debt).
     * @param auctionDuration Duration of the auction in seconds (e.g., 72 hours).
     * @param lenders Array of lenders involved (for multi-tranche distribution).
     * @param lenderShares Pro-rata shares or principal amounts for distribution.
     * @return auctionId A unique ID for the auction.
     */
    function startAuction(
        bytes32 loanId,
        address nftContract,
        uint256 nftTokenId,
        bool isVault,
        address currency,
        uint256 startingBid,
        uint64 auctionDuration,
        address[] calldata lenders,
        uint256[] calldata lenderShares
    ) external returns (bytes32 auctionId);

    /**
     * @notice Allows participants to place a bid in an ongoing auction.
     * @dev Bids must be higher than the current highest bid by a minimum percentage (e.g., 5%).
     * @dev Requires payment in the auction currency.
     * @param auctionId The ID of the auction.
     * @param amount The bid amount.
     */
    function placeBid(bytes32 auctionId, uint256 amount) external payable; // payable if currency is ETH/WETH

    /**
     * @notice Ends an auction after its duration, determines the winner, and transfers NFT.
     * @dev Can be called by anyone after the auction end time.
     * @param auctionId The ID of the auction to end.
     */
    function endAuction(bytes32 auctionId) external;

    /**
     * @notice Handles the distribution of auction proceeds to lenders based on tranche seniority or pro-rata.
     * @dev Called after a successful auction.
     * @param auctionId The ID of the auction whose proceeds are to be distributed.
     */
    function distributeProceeds(bytes32 auctionId) external;

    /**
     * @notice Allows the original lender(s) to claim collateral if an auction fails (e.g., no bids).
     * @dev Specific logic needed for how collateral is split or claimed in multi-lender scenarios if auction fails.
     * @param auctionId The ID of the failed auction.
     */
    function claimCollateralPostAuction(bytes32 auctionId) external;

    // --- Getters ---
    function getAuction(bytes32 auctionId) external view returns (Auction memory);
    function isBuyoutActive(bytes32 loanId) external view returns (bool);
}
