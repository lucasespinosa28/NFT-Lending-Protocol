// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/LendingProtocol.sol";
import "../src/core/CollectionManager.sol";
import "../src/core/CurrencyManager.sol";
import "../src/core/RoyaltyManager.sol";
import "../src/core/VaultsFactory.sol";
import "../src/interfaces/ILendingProtocol.sol";
import "../src/mocks/ERC721Mock.sol";
import "../src/mocks/ERC20Mock.sol";
import "../src/mocks/MockIIPAssetRegistry.sol";
import "../src/mocks/MockRoyaltyModule.sol";
import "../src/core/PurchaseBundler.sol";
import "../src/core/Liquidation.sol"; // Added for constructor

contract E2ETests is Test {
    // Protocol Contracts
    LendingProtocol internal lendingProtocol;
    CollectionManager internal collectionManager;
    CurrencyManager internal currencyManager;
    RoyaltyManager internal royaltyManager;
    VaultsFactory internal vaultsFactory;
    PurchaseBundler internal purchaseBundler;
    Liquidation internal liquidation; // Added
    MockIIPAssetRegistry internal mockIpAssetRegistry;
    MockRoyaltyModule internal mockRoyaltyModule;

    // Mock Tokens
    ERC721Mock internal mockNft;
    ERC20Mock internal weth; // Mock WETH

    // Actors
     address internal owner = address(0x1);
    address internal lender = address(0x1001);
    address internal borrower = address(0x1002);
    address internal buyer = address(0x1003);
    address internal admin = address(this);

    // Constants
    uint256 internal constant NFT_ID = 1;
    uint256 internal constant LOAN_PRINCIPAL = 1 ether;
    // For 10% APR, if contract expects rate as (percentage * 100), e.g. 10% = 1000.
    // If it's basis points (percentage * 10000), then 10% = 100.
    // The original LendingProtocol used 500 for 5%, 600 for 6%. So 10% = 1000.
    uint256 internal constant LOAN_RATE_APR = 1000; // 10% APR
    uint32 internal constant LOAN_DURATION = 7 days;
    uint256 internal constant SALE_PRICE = 1.5 ether;

    function setUp() public virtual {
        // Deploy Mock IP Asset Registry and Royalty Module
        mockIpAssetRegistry = new MockIIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule();

        // Deploy Core Protocol Contracts
        // Use admin (address(this)) as owner for Ownable contracts
        collectionManager = new CollectionManager(admin, new address[](0));
        currencyManager = new CurrencyManager(new address[](0));

        // RoyaltyManager constructor: address ipAssetRegistry, address royaltyModule, address licensingModule, address licenseRegistry
        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry),
            address(mockRoyaltyModule),
            address(0), // Dummy licensing module
            address(0) // Dummy license registry
        );

        // VaultsFactory constructor: string memory _name, string memory _symbol
        vaultsFactory = new VaultsFactory("E2E Vaults", "E2EV");

        // Liquidation and PurchaseBundler need LendingProtocol address, but LP needs them too.
        // Deploy with address(0) for LP initially, then set LP address later.
        liquidation = new Liquidation(address(0)); // Actual Liquidation contract
        purchaseBundler = new PurchaseBundler(address(0)); // Actual PurchaseBundler

        // LendingProtocol constructor: address currencyManager, address collectionManager, address vaultsFactory,
        //                            address liquidationContract, address purchaseBundler, address royaltyManager, address ipAssetRegistry
        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidation),
            address(purchaseBundler),
            address(royaltyManager),
            address(mockIpAssetRegistry)
        );

        // Set LendingProtocol address in Liquidation and PurchaseBundler
        liquidation.setLendingProtocol(address(lendingProtocol));
        purchaseBundler.setLendingProtocol(address(lendingProtocol));

        // Deploy Mock Tokens
        mockNft = new ERC721Mock("MockNFT", "MNFT");
        weth = new ERC20Mock("Wrapped Ether", "WETH"); // Default 18 decimals

        // Initialize Managers (assuming admin is owner from constructor)
        collectionManager.addWhitelistedCollection(address(mockNft));
        currencyManager.addSupportedCurrency(address(weth));

        // Deal initial balances
        vm.deal(lender, 10 ether);
        vm.deal(borrower, 1 ether);
        vm.deal(buyer, 10 ether);

        // Mint NFT to borrower
        mockNft.mint(borrower, NFT_ID);

        // Mint WETH to lender (as vm.deal gives ETH, not WETH)
        weth.mint(lender, 10 ether);
        // Mint WETH for buyer
        weth.mint(buyer, 10 ether);

        // Initial Approvals
        vm.startPrank(lender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower);
        mockNft.setApprovalForAll(address(lendingProtocol), true);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(buyer);
        weth.approve(address(purchaseBundler), type(uint256).max);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();
    }

    function test_E2E_SellAndRepay() public {
        // Arrange: Create an active loan
        vm.startPrank(lender);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: NFT_ID,
            currency: address(weth),
            principalAmount: LOAN_PRINCIPAL,
            interestRateAPR: LOAN_RATE_APR,
            durationSeconds: LOAN_DURATION,
            expirationTimestamp: uint64(block.timestamp + 1 hours),
            originationFeeRate: 0,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), NFT_ID);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);

        // Arrange: Determine sale price (must cover debt at maturity + surplus)
        vm.warp(loan.dueTime); // Go to loan maturity to calculate max interest
        uint256 interestAtMaturity = lendingProtocol.calculateInterest(loanId);
        uint256 minSalePrice = loan.principalAmount + interestAtMaturity;
        uint256 actualSalePrice = minSalePrice + 0.5 ether; // Add surplus for borrower

        // Warp to a point in time for the actual sale (e.g., mid-loan)
        uint256 loanDuration = loan.dueTime - loan.startTime;
        uint256 saleTime = loan.startTime + (loanDuration / 2);
        vm.warp(saleTime);

        // Act (Borrower): List collateral for sale via LendingProtocol
        // This assumes LendingProtocol.listCollateralForSale exists and calls PurchaseBundler.listItem
        // and that PurchaseBundler is designed to allow LendingProtocol (as current NFT owner) to list.
        vm.startPrank(borrower); // Borrower initiates listing
        lendingProtocol.listCollateralForSale(loanId, actualSalePrice);
        vm.stopPrank();

        // Assert: Verify SaleListing is active in PurchaseBundler
        // This requires PurchaseBundler to expose listings in a way that can be checked.
        IPurchaseBundler.SaleListing memory listing = purchaseBundler.getSaleListing(loanId);
        assertEq(listing.price, actualSalePrice, "Listing price incorrect");
        // Seller in SaleListing is the original borrower as per PurchaseBundler.listCollateralForSale
        assertEq(listing.seller, borrower, "Listing seller should be the borrower");
        assertTrue(listing.isActive, "Listing should be active");

        // Act (Buyer): Buy collateral via PurchaseBundler
        uint256 buyerWethBalanceBefore = weth.balanceOf(buyer);
        uint256 lenderWethBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBefore = weth.balanceOf(borrower); // This is after loan principal was received

        // Interest accrued up to the point of sale
        uint256 currentInterestAtSale = lendingProtocol.calculateInterest(loanId);
        uint256 totalDebtAtSale = loan.principalAmount + currentInterestAtSale;

        require(actualSalePrice >= totalDebtAtSale, "Sale price must cover debt at sale time");

        vm.startPrank(buyer);
        // Assuming buyListedCollateral on PurchaseBundler handles the WETH transfer from buyer,
        // NFT transfer to buyer, payment to lender, and surplus to borrower.
        // The listingId is the loanId.
        purchaseBundler.buyListedCollateral(loanId, actualSalePrice);
        vm.stopPrank();

        // Assert: Post-sale and repayment state
        assertEq(mockNft.ownerOf(NFT_ID), buyer, "NFT should be transferred to buyer");

        uint256 lenderWethBalanceAfter = weth.balanceOf(lender);
        assertEq(
            lenderWethBalanceAfter, lenderWethBalanceBefore + totalDebtAtSale, "Lender should receive full repayment"
        );

        uint256 borrowerWethBalanceAfter = weth.balanceOf(borrower);
        uint256 expectedSurplus = actualSalePrice - totalDebtAtSale;
        assertEq(
            borrowerWethBalanceAfter, borrowerWethBalanceBefore + expectedSurplus, "Borrower should receive surplus"
        );

        uint256 buyerWethBalanceAfter = weth.balanceOf(buyer);
        assertEq(
            buyerWethBalanceAfter,
            buyerWethBalanceBefore - actualSalePrice,
            "Buyer's WETH should decrease by sale price"
        );

        ILendingProtocol.Loan memory finalLoanStatus = lendingProtocol.getLoan(loanId);
        assertEq(
            uint8(finalLoanStatus.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID"
        );
    }
}
