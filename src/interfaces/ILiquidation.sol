// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ILiquidation
 * @author Lucas Espinosa
 * @notice Interface for managing the liquidation process of defaulted loans.
 * This includes buyouts for multi-tranche loans and auctions.
 * @dev Defines events, structs, and functions for liquidation and auction logic.
 */
interface ILiquidation {
    /**
     * @notice Enum representing the status of an auction.
     */
    enum AuctionStatus {
        PENDING,
        ACTIVE,
        ENDED_NO_BIDS,
        ENDED_SOLD,
        SETTLED
    }

    /**
     * @notice Struct representing an auction for a defaulted loan's collateral.
     * @dev Contains auction parameters and state.
     */
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

    /**
     * @notice Emitted when an auction is started for a defaulted loan's collateral.
     * @param auctionId The unique ID for the auction.
     * @param loanId The ID of the defaulted loan.
     * @param nftContract The address of the NFT contract.
     * @param nftTokenId The token ID of the NFT.
     * @param startingBid The minimum bid to start the auction.
     * @param endTime The timestamp when the auction ends.
     */
    event AuctionStarted( // Could be loanId or a new ID
        bytes32 indexed auctionId,
        bytes32 indexed loanId,
        address nftContract,
        uint256 nftTokenId,
        uint256 startingBid,
        uint64 endTime
    );

    /**
     * @notice Emitted when a bid is placed in an auction.
     * @param auctionId The ID of the auction.
     * @param bidder The address of the bidder.
     * @param amount The bid amount.
     */
    event BidPlaced(bytes32 indexed auctionId, address indexed bidder, uint256 amount);

    /**
     * @notice Emitted when an auction ends.
     * @param auctionId The ID of the auction.
     * @param winner The address of the winning bidder (address(0) if no bids).
     * @param winningBid The winning bid amount.
     */
    event AuctionEnded( // address(0) if no bids
    bytes32 indexed auctionId, address winner, uint256 winningBid);

    /**
     * @notice Emitted when auction proceeds are distributed to lenders.
     * @param auctionId The ID of the auction.
     * @param totalProceeds The total amount distributed.
     */
    event ProceedsDistributed(bytes32 indexed auctionId, uint256 totalProceeds);

    /**
     * @notice Emitted when collateral is claimed by lender(s) after a failed auction.
     * @param auctionId The ID of the auction.
     * @param claimer The address of the lender claiming the collateral.
     */
    event CollateralClaimedPostAuction( // If auction fails and original lender(s) claim
    bytes32 indexed auctionId, address claimer);

    // --- Functions ---

    /**
     * @notice Initiates an English auction if no buyout occurs or for single-lender defaults.
     * @dev Called by the main lending protocol.
     * @param loanId The ID of the defaulted loan.
     * @param nftContract Address of the collateral NFT.
     * @param nftTokenId Token ID of the collateral NFT.
     * @param isVault True if the collateral is a vault.
     * @param currency Address of the currency for bidding.
     * @param startingBid The minimum bid to start the auction (e.g., outstanding debt).
     * @param auctionDuration Duration of the auction in seconds.
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

    /**
     * @notice Gets the details of an auction by its ID.
     * @param auctionId The ID of the auction.
     * @return The Auction struct.
     */
    function getAuction(bytes32 auctionId) external view returns (Auction memory);
}
