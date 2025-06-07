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
        // Assuming admin (address(this)) becomes owner by Ownable pattern
        collectionManager = new CollectionManager(new address[](0));
        currencyManager = new CurrencyManager(new address[](0));

        // RoyaltyManager constructor: address ipAssetRegistry, address royaltyModule, address licensingModule, address licenseRegistry
        royaltyManager = new RoyaltyManager(
            address(mockIpAssetRegistry),
            address(mockRoyaltyModule),
            address(0), // Dummy licensing module
            address(0)  // Dummy license registry
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

    function test_E2E_HappyPath_StandardLoan() public {
        // Arrange: Initial setup is largely done in setUp()
        // uint256 initialLenderWethBalance = weth.balanceOf(lender); // Unused variable
        uint256 initialBorrowerWethBalance = weth.balanceOf(borrower); // Should be 0 from setUp

        // Act (Lender): Make a loan offer
        vm.startPrank(lender);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: NFT_ID,
            currency: address(weth),
            principalAmount: LOAN_PRINCIPAL,
            interestRateAPR: LOAN_RATE_APR,
            durationSeconds: LOAN_DURATION,
            expirationTimestamp: uint64(block.timestamp + 1 days), // Offer valid for 1 day
            originationFeeRate: 0, // No origination fee for this happy path test
            totalCapacity: 0, // Not used for standard offers
            maxPrincipalPerLoan: 0, // Not used for standard offers
            minNumberOfLoans: 0 // Not used for standard offers
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        assertTrue(offerId != bytes32(0), "Offer ID should not be zero");

        // Act (Borrower): Accept the loan offer
        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), NFT_ID); // For standard offer, these might not be needed if offerId is specific enough
        vm.stopPrank();

        assertTrue(loanId != bytes32(0), "Loan ID should not be zero");

        // Assert: Post-acceptance state
        assertEq(mockNft.ownerOf(NFT_ID), address(lendingProtocol), "NFT should be held by LendingProtocol");

        uint256 borrowerWethBalanceAfterLoan = weth.balanceOf(borrower);
        assertEq(borrowerWethBalanceAfterLoan, initialBorrowerWethBalance + LOAN_PRINCIPAL, "Borrower WETH balance should increase by principal");

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan status should be ACTIVE");
        assertEq(loan.principalAmount, LOAN_PRINCIPAL, "Loan principal amount incorrect");
        assertEq(loan.borrower, borrower, "Loan borrower incorrect");
        assertEq(loan.lender, lender, "Loan lender incorrect");


        // Act (Borrower): Repay the loan
        // Advance time to the due date for interest accrual
        vm.warp(block.timestamp + LOAN_DURATION);

        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = loan.principalAmount + interest;

        // Borrower received LOAN_PRINCIPAL. They need `interest` more to repay fully.
        // Mint the required interest directly to the borrower for WETH.
        weth.mint(borrower, interest);
        // Borrower should have approved weth spending by lendingProtocol in setUp

        uint256 lenderWethBalanceBeforeRepay = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBeforeRepay = weth.balanceOf(borrower);


        vm.startPrank(borrower);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        // Assert: Post-repayment state
        assertEq(mockNft.ownerOf(NFT_ID), borrower, "NFT should be returned to borrower");

        uint256 lenderWethBalanceAfterRepay = weth.balanceOf(lender);
        // Lender's balance should be their initial loan amount given out, plus the total repayment (principal + interest)
        // Initial lender balance - principal_loaned_out + total_repayment
        // = initialLenderWethBalance - LOAN_PRINCIPAL + totalRepayment
        // However, the LOAN_PRINCIPAL was already transferred from lender to borrower during acceptLoanOffer.
        // So, lender's balance before repay was initialLenderWethBalance - LOAN_PRINCIPAL (if no origination fee to lender)
        // After repay, it should be (initialLenderWethBalance - LOAN_PRINCIPAL) + totalRepayment
        // Let's use the balance just before repay for clarity:
        assertEq(lenderWethBalanceAfterRepay, lenderWethBalanceBeforeRepay + totalRepayment, "Lender WETH balance after repay incorrect");

        uint256 borrowerWethBalanceAfterRepay = weth.balanceOf(borrower);
        assertEq(borrowerWethBalanceAfterRepay, borrowerWethBalanceBeforeRepay - totalRepayment, "Borrower WETH balance after repay incorrect");


        ILendingProtocol.Loan memory repaidLoan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(repaidLoan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");
        assertEq(repaidLoan.accruedInterest, interest, "Loan accrued interest incorrect");
    }

    function test_E2E_Default_ClaimCollateral() public {
        // Arrange: Create an active loan (similar to initial steps of Happy Path)
        vm.startPrank(lender);
        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(mockNft),
            nftTokenId: NFT_ID,
            currency: address(weth),
            principalAmount: LOAN_PRINCIPAL,
            interestRateAPR: LOAN_RATE_APR,
            durationSeconds: LOAN_DURATION,
            expirationTimestamp: uint64(block.timestamp + 1 hours), // Offer expiration
            originationFeeRate: 0, // Assuming 0 for simplicity
            totalCapacity: 0, // Not used for standard offers
            maxPrincipalPerLoan: 0, // Not used for standard offers
            minNumberOfLoans: 0 // Not used for standard offers
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        assertTrue(offerId != bytes32(0), "Offer ID should not be zero");

        vm.startPrank(borrower);
        // For standard offer, nftContract and nftTokenId might be redundant if offerId is specific enough,
        // but acceptLoanOffer signature in LendingProtocol.sol expects them.
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), NFT_ID);
        vm.stopPrank();

        assertTrue(loanId != bytes32(0), "Loan ID should not be zero");

        // Assert loan is active
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan status should be ACTIVE initially");
        assertEq(mockNft.ownerOf(NFT_ID), address(lendingProtocol), "NFT should be held by LendingProtocol during active loan");

        // Act: Advance time past the loan's due time
        // loan.dueTime is already populated correctly by acceptLoanOffer (startTime + durationSeconds)
        // vm.warp wants an absolute timestamp
        vm.warp(loan.dueTime + 1 days); // Advance time to be clearly after due time

        // Act (Lender): Claim collateral
        uint256 lenderWethBalanceBeforeClaim = weth.balanceOf(lender);

        vm.startPrank(lender);
        lendingProtocol.claimCollateral(loanId);
        vm.stopPrank();

        // Assert: Post-claim state
        ILendingProtocol.Loan memory defaultedLoan = lendingProtocol.getLoan(loanId); // Re-fetch loan state
        assertEq(uint8(defaultedLoan.status), uint8(ILendingProtocol.LoanStatus.DEFAULTED), "Loan status should be DEFAULTED");
        assertEq(mockNft.ownerOf(NFT_ID), lender, "NFT (collateral) should be transferred to the lender");

        // Verify lender's WETH balance hasn't changed (as they claimed NFT, not WETH)
        assertEq(weth.balanceOf(lender), lenderWethBalanceBeforeClaim, "Lender WETH balance should not change on collateral claim");
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
            totalCapacity: 0, maxPrincipalPerLoan: 0, minNumberOfLoans: 0
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
        assertEq(lenderWethBalanceAfter, lenderWethBalanceBefore + totalDebtAtSale, "Lender should receive full repayment");

        uint256 borrowerWethBalanceAfter = weth.balanceOf(borrower);
        uint256 expectedSurplus = actualSalePrice - totalDebtAtSale;
        assertEq(borrowerWethBalanceAfter, borrowerWethBalanceBefore + expectedSurplus, "Borrower should receive surplus");

        uint256 buyerWethBalanceAfter = weth.balanceOf(buyer);
        assertEq(buyerWethBalanceAfter, buyerWethBalanceBefore - actualSalePrice, "Buyer's WETH should decrease by sale price");

        ILendingProtocol.Loan memory finalLoanStatus = lendingProtocol.getLoan(loanId);
        assertEq(uint8(finalLoanStatus.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");
    }

    function test_E2E_StoryProtocol_ClaimAndRepay() public {
        // Arrange: Register NFT with MockIIPAssetRegistry to get an ipId
        // Correctly convert keccak256 hash to address
        address expectedIpId = address(uint160(uint256(keccak256(abi.encodePacked(block.chainid, address(mockNft), NFT_ID)))));

        vm.prank(borrower); // Borrower owns the NFT, so should be the one registering it
        mockIpAssetRegistry.register(block.chainid, address(mockNft), NFT_ID); // chainId is arbitrary for mock

        // Arrange: Create an active loan. isStoryAsset and storyIpId are set by acceptLoanOffer.
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
            // Fields below are not strictly for standard offer but part of struct
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(mockNft), NFT_ID);
        vm.stopPrank();

        // Assert: Loan details include Story Protocol info
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertTrue(loan.isStoryAsset, "Loan should be marked as Story Asset");
        assertEq(loan.storyIpId, expectedIpId, "Loan storyIpId mismatch");
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan should be ACTIVE");

        // Arrange: Fund MockRoyaltyModule with royalties for this ipId
        vm.warp(loan.dueTime); // Advance time to loan maturity for full interest calculation

        uint256 interestDue = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepaymentDue = loan.principalAmount + interestDue;

        // Fund the MockRoyaltyModule so it can simulate having royalties
        weth.mint(address(mockRoyaltyModule), totalRepaymentDue);
        // Set the amount available for the specific IP ID
        // MockRoyaltyModule's setRoyaltyAmount uses address for ipId
        mockRoyaltyModule.setRoyaltyAmount(expectedIpId, address(weth), totalRepaymentDue);

        uint256 lenderWethBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBefore = weth.balanceOf(borrower);
        uint256 borrowerEthBalanceBefore = borrower.balance;

        // Act (Borrower): Call claimAndRepay
        vm.startPrank(borrower);
        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        // Assert: Post claimAndRepay state
        uint256 lenderWethBalanceAfter = weth.balanceOf(lender);
        assertEq(lenderWethBalanceAfter, lenderWethBalanceBefore + totalRepaymentDue, "Lender should receive full repayment from royalties");

        uint256 borrowerWethBalanceAfter = weth.balanceOf(borrower);
        assertEq(borrowerWethBalanceAfter, borrowerWethBalanceBefore, "Borrower's WETH balance should not change");

        // Check that the borrower's ETH balance did not decrease significantly (i.e., they didn't pay the loan with ETH)
        // Gas costs might be negligible or handled differently by the test environment for pranked accounts.
        assertTrue(borrowerEthBalanceBefore - borrower.balance < 0.1 ether, "Borrower ETH balance decreased too much (unexpectedly paid loan with ETH)");


        assertEq(mockNft.ownerOf(NFT_ID), borrower, "NFT should be returned to borrower");

        ILendingProtocol.Loan memory finalLoan = lendingProtocol.getLoan(loanId); // Re-fetch loan
        assertEq(uint8(finalLoan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");
        assertEq(finalLoan.accruedInterest, interestDue, "Loan accrued interest should be set");

        // Verify royalty balance in RoyaltyManager is now zero for the IP
        uint256 remainingRoyaltiesInRM = royaltyManager.getRoyaltyBalance(expectedIpId, address(weth));
        assertEq(remainingRoyaltiesInRM, 0, "Royalty balance in RoyaltyManager for ipId should be zero after claimAndRepay");
    }
}
