// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
// import {StdCheats} from "forge-std/StdCheats.sol"; // Test includes StdCheats

// Protocol Core Contracts
import {LendingProtocol} from "../../../src/core/LendingProtocol.sol";
import {LoanOfferLogic} from "../../../src/core/logic/LoanOfferLogic.sol";
import {LoanManagementLogic} from "../../../src/core/logic/LoanManagementLogic.sol";
// import {CollateralLogic} from "../../../src/core/logic/CollateralLogic.sol";
import {StoryIntegrationLogic} from "../../../src/core/logic/StoryIntegrationLogic.sol";

// Manager Contracts & Actual Implementations
import {CurrencyManager} from "../../../src/core/CurrencyManager.sol";
import {CollectionManager} from "../../../src/core/CollectionManager.sol";
import {VaultsFactory} from "../../../src/core/VaultsFactory.sol";
import {Liquidation} from "../../../src/core/Liquidation.sol";
import {PurchaseBundler} from "../../../src/core/PurchaseBundler.sol";
import {RoyaltyManager} from "../../../src/core/RoyaltyManager.sol";

// Interfaces
import "../../../src/interfaces/ILendingProtocol.sol"; // General import
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

// Mocks
import {ERC20Mock} from "../../../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../../../src/mocks/ERC721Mock.sol";
import {MockRoyaltyModule} from "../../../src/mocks/MockRoyaltyModule.sol";
import {MockIPAssetRegistry} from "../../../src/mocks/MockIPAssetRegistry.sol";

contract LoanManagementLogicTest is Test {
    // --- Constants ---
    uint256 internal constant DEFAULT_PRINCIPAL = 1 ether; // Standardized for easier use
    uint256 internal constant DEFAULT_INTEREST_RATE_APR = 1000; // 10%
    uint256 internal constant DEFAULT_DURATION_SECONDS = 30 days;
    uint64 internal constant DEFAULT_EXPIRATION_TIMESTAMP_OFFSET = 7 days;
    uint256 internal constant DEFAULT_ORIGINATION_FEE_RATE = 100; // 1%
    uint256 internal constant BORROWER_NFT_ID = 1;
    uint256 internal constant LENDER_INITIAL_WETH_BALANCE = 100 ether;

    // --- Users ---
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");
    address internal admin = makeAddr("admin");
    address internal otherUser = makeAddr("otherUser");
    address internal newLender = makeAddr("newLender");

    // --- Contracts ---
    LendingProtocol internal lendingProtocol;
    LoanOfferLogic internal loanOfferLogic;
    LoanManagementLogic internal loanManagementLogic;
    StoryIntegrationLogic internal storyIntegrationLogic;

    CurrencyManager internal currencyManager;
    CollectionManager internal collectionManager;
    VaultsFactory internal vaultsFactory;
    Liquidation internal liquidationContract;
    PurchaseBundler internal purchaseBundlerContract;
    RoyaltyManager internal royaltyManager;
    MockIPAssetRegistry internal ipAssetRegistry;
    MockRoyaltyModule internal mockRoyaltyModule;

    // --- Mocks ---
    ERC20Mock internal weth;
    ERC20Mock internal usdc; // Though its decimals won't be 6 with current ERC20Mock
    ERC721Mock internal testNft;

    function setUp() public virtual {
        vm.startPrank(admin);

        weth = new ERC20Mock("Wrapped Ether", "WETH");
        usdc = new ERC20Mock("USD Coin", "USDC");
        testNft = new ERC721Mock("Test NFT", "TNFT");

        ipAssetRegistry = new MockIPAssetRegistry();
        mockRoyaltyModule = new MockRoyaltyModule();

        address[] memory initialCurrencies = new address[](2);
        initialCurrencies[0] = address(weth);
        initialCurrencies[1] = address(usdc);
        currencyManager = new CurrencyManager(initialCurrencies);

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(testNft);
        collectionManager = new CollectionManager(admin, initialCollections);

        vaultsFactory = new VaultsFactory("TestVault", "TV");
        liquidationContract = new Liquidation(address(0));
        purchaseBundlerContract = new PurchaseBundler(address(0));
        royaltyManager = new RoyaltyManager(
            address(ipAssetRegistry),
            address(mockRoyaltyModule),
            makeAddr("licensingModule"),
            makeAddr("licenseRegistry")
        );

        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidationContract),
            address(purchaseBundlerContract),
            address(royaltyManager),
            address(ipAssetRegistry)
        );

        liquidationContract.setLendingProtocol(address(lendingProtocol));
        purchaseBundlerContract.setLendingProtocol(address(lendingProtocol));

        vm.stopPrank();

        loanOfferLogic = lendingProtocol.loanOfferLogic();
        loanManagementLogic = lendingProtocol.loanManagementLogic();
        storyIntegrationLogic = lendingProtocol.storyIntegrationLogic();

        weth.mint(lender, LENDER_INITIAL_WETH_BALANCE);
        weth.mint(newLender, LENDER_INITIAL_WETH_BALANCE);
        testNft.mint(borrower, BORROWER_NFT_ID);

        vm.startPrank(lender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(newLender);
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(borrower);
        testNft.setApprovalForAll(address(lendingProtocol), true);
        weth.mint(borrower, DEFAULT_PRINCIPAL * 3); // Mint enough for repayment & fee tests
        weth.approve(address(lendingProtocol), type(uint256).max);
        vm.stopPrank();

        weth.mint(address(this), 200 ether);
        weth.approve(address(mockRoyaltyModule), 200 ether);
        mockRoyaltyModule.fundModule(address(weth), 100 ether);
    }

    // --- Helper Functions ---
    function _makeOfferParams(
        address _nftContract,
        uint256 _nftTokenId,
        address _currency,
        uint256 _principalAmount,
        uint256 _interestRateAPR,
        uint256 _durationSeconds,
        uint256 _originationFeeRate
    ) internal view returns (ILendingProtocol.OfferParams memory) {
        uint64 expiration = uint64(block.timestamp + DEFAULT_EXPIRATION_TIMESTAMP_OFFSET);
        ILendingProtocol.OfferParams memory params;
        params.offerType = ILendingProtocol.OfferType.STANDARD;
        params.nftContract = _nftContract;
        params.nftTokenId = _nftTokenId;
        params.currency = _currency;
        params.principalAmount = _principalAmount;
        params.interestRateAPR = _interestRateAPR;
        params.durationSeconds = _durationSeconds;
        params.expirationTimestamp = expiration;
        params.originationFeeRate = _originationFeeRate;
        params.totalCapacity = 0;
        params.maxPrincipalPerLoan = 0;
        params.minNumberOfLoans = 0;
        return params;
    }

    function _makeAndGetStandardOfferId(address _lender, uint256 _principal, uint256 _nftTokenId) internal returns (bytes32) {
        vm.startPrank(_lender);
        ILendingProtocol.OfferParams memory params = _makeOfferParams(
            address(testNft),
            _nftTokenId,
            address(weth),
            _principal,
            DEFAULT_INTEREST_RATE_APR,
            DEFAULT_DURATION_SECONDS,
            DEFAULT_ORIGINATION_FEE_RATE
        );
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
        return offerId;
    }

    function _makeOfferWithSpecifics(
        address _lender,
        uint256 _principal,
        uint256 _nftTokenId,
        uint256 _interestRateAPR,
        uint256 _durationSeconds,
        uint256 _originationFeeRate
    ) internal returns (bytes32) {
        vm.startPrank(_lender);
        ILendingProtocol.OfferParams memory params = _makeOfferParams(
            address(testNft),
            _nftTokenId,
            address(weth),
            _principal,
            _interestRateAPR,
            _durationSeconds,
            _originationFeeRate
        );
        bytes32 offerId = lendingProtocol.makeLoanOffer(params);
        vm.stopPrank();
        return offerId;
    }

    function _makeAndGetActiveLoan() internal returns (bytes32 loanId, bytes32 offerId) {
        offerId = _makeAndGetStandardOfferId(lender, DEFAULT_PRINCIPAL, BORROWER_NFT_ID);
        vm.startPrank(borrower);
        loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();
        return (loanId, offerId); // Added missing return statement
    }
    // Removed duplicated/erroneous _makeAndGetActiveLoan function

    // --- Tests Moved from LendingProtocol.t.sol ---

    function test_AcceptStandardLoanOffer_Success() public {
        // 1. Lender makes an offer (use helper)
        bytes32 offerId = _makeAndGetStandardOfferId(lender, 1 ether, BORROWER_NFT_ID);

        // 2. Borrower accepts the offer
        vm.startPrank(borrower);
        uint256 lenderWethBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerWethBalanceBefore = weth.balanceOf(borrower);
        // Protocol WETH balance should ideally remain 0 if fees are directly transferred or handled by logic contracts.
        // However, LendingProtocol.sol's acceptLoanOffer has fund transfers.
        // LoanManagementLogic.createLoan has the actual transfers.
        // Lender pays principal to borrower, and fee to self (or treasury).
        // For this test, fee goes to lender in LoanManagementLogic.createLoan.
        // So, lender's balance change = -principalAmount. Borrower's change = principalAmount - fee.

        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        assertTrue(loanId != bytes32(0), "Loan ID should not be zero");
        vm.stopPrank();

        // 3. Verify states
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(loan.borrower, borrower, "Loan borrower incorrect");
        assertEq(loan.lender, lender, "Loan lender incorrect");
        assertEq(loan.nftContract, address(testNft), "Loan NFT contract incorrect");
        assertEq(loan.nftTokenId, BORROWER_NFT_ID, "Loan NFT token ID incorrect");
        assertEq(loan.principalAmount, 1 ether, "Loan principal incorrect");
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.ACTIVE), "Loan status not ACTIVE"); // Qualified

        assertEq(testNft.ownerOf(BORROWER_NFT_ID), address(lendingProtocol), "NFT not escrowed by protocol");

        uint256 originationFee = (1 ether * DEFAULT_ORIGINATION_FEE_RATE) / 10000;
        assertEq(weth.balanceOf(lender), lenderWethBalanceBefore - (1 ether - originationFee) + originationFee, "Lender WETH balance after loan incorrect");
        assertEq(weth.balanceOf(borrower), borrowerWethBalanceBefore + (1 ether - originationFee), "Borrower WETH balance after loan incorrect");

        ILendingProtocol.LoanOffer memory acceptedOffer = lendingProtocol.getLoanOffer(offerId); // Qualified
        assertFalse(acceptedOffer.isActive, "Accepted offer should be inactive");
    }

    function test_AcceptLoanOffer_WithStoryAsset_Success() public {
        vm.prank(admin); // Or borrower if they own the IP registration right
        ipAssetRegistry.register(block.chainid, address(testNft), BORROWER_NFT_ID);
        address expectedIpId = ipAssetRegistry.ipId(block.chainid, address(testNft), BORROWER_NFT_ID);
        assertTrue(expectedIpId != address(0));

        bytes32 offerId = _makeAndGetStandardOfferId(lender, 1 ether, BORROWER_NFT_ID);

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertTrue(loan.isStoryAsset, "Loan should be marked as Story asset");
        assertEq(loan.storyIpId, expectedIpId, "Loan storyIpId incorrect");
    }

    function test_ClaimAndRepay_StoryAsset_FullRepaymentByRoyalty() public {
        vm.prank(admin); // Register asset
        ipAssetRegistry.register(block.chainid, address(testNft), BORROWER_NFT_ID);
        address ipId = ipAssetRegistry.ipId(block.chainid, address(testNft), BORROWER_NFT_ID);

        bytes32 offerId = _makeOfferWithSpecifics(
            lender, 1 ether, BORROWER_NFT_ID,
            36500, // 1% per day APR
            1 days,
            0 // originationFeeRate
        );

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days); // Advance time for interest

        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;

        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), totalRepaymentDue);

        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        // vm.expectEmit(true, true, true, true, address(lendingProtocol)); // Event is from LML
        // emit ILendingProtocol.LoanRepaid(loanId, borrower, lender, 1 ether, expectedInterest);
        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID)); // Qualified
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue);
        assertEq(testNft.ownerOf(BORROWER_NFT_ID), borrower);
    }

    function test_ClaimAndRepay_StoryAsset_PartialRepaymentByRoyalty() public {
        vm.prank(admin);
        ipAssetRegistry.register(block.chainid, address(testNft), BORROWER_NFT_ID);
        address ipId = ipAssetRegistry.ipId(block.chainid, address(testNft), BORROWER_NFT_ID);

        bytes32 offerId = _makeOfferWithSpecifics(
            lender, 1 ether, BORROWER_NFT_ID,
            36500, // APR
            1 days,
            0 // originationFeeRate
        );

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;
        uint256 royaltyAvailable = 0.5 ether;
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), royaltyAvailable);

        uint256 remainingForBorrower = totalRepaymentDue - royaltyAvailable;
        // weth.mint(borrower, remainingForBorrower); // Already minted enough in setUp
        vm.startPrank(borrower);
        // weth.approve(address(lendingProtocol), remainingForBorrower); // Already approved max in setUp
        uint256 lenderWethBefore = weth.balanceOf(lender);
        uint256 borrowerWethBefore = weth.balanceOf(borrower);
        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID)); // Qualified
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue);
        assertEq(weth.balanceOf(borrower), borrowerWethBefore - remainingForBorrower);
        assertEq(testNft.ownerOf(BORROWER_NFT_ID), borrower);
    }

    function test_ClaimAndRepay_StoryAsset_NoRoyaltyBalance() public {
        vm.prank(admin);
        ipAssetRegistry.register(block.chainid, address(testNft), BORROWER_NFT_ID);
        address ipId = ipAssetRegistry.ipId(block.chainid, address(testNft), BORROWER_NFT_ID);

        bytes32 offerId = _makeOfferWithSpecifics(
            lender, 1 ether, BORROWER_NFT_ID,
            36500, // APR
            1 days,
            0 // originationFeeRate
        );

        vm.startPrank(borrower);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(testNft), BORROWER_NFT_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        mockRoyaltyModule.setRoyaltyAmount(ipId, address(weth), 0);

        uint256 expectedInterest = (1 ether * 36500 * 1) / (365 * 10000);
        uint256 totalRepaymentDue = 1 ether + expectedInterest;
        // weth.mint(borrower, totalRepaymentDue); // Already minted
        // vm.startPrank(borrower);
        // weth.approve(address(lendingProtocol), totalRepaymentDue); // Already approved
        // vm.stopPrank();

        vm.startPrank(borrower);
        uint256 lenderWethBefore = weth.balanceOf(lender);
        uint256 borrowerWethBefore = weth.balanceOf(borrower);
        lendingProtocol.claimAndRepay(loanId);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID)); // Qualified
        assertEq(weth.balanceOf(lender), lenderWethBefore + totalRepaymentDue);
        assertEq(weth.balanceOf(borrower), borrowerWethBefore - totalRepaymentDue);
        assertEq(testNft.ownerOf(BORROWER_NFT_ID), borrower);
    }

    // --- New/Stubbed Tests for LoanManagementLogic ---

    function test_RepayLoan_Success() public {
        (bytes32 loanId, ) = _makeAndGetActiveLoan();

        // Advance time, but not past due date
        vm.warp(block.timestamp + DEFAULT_DURATION_SECONDS / 2);
        uint256 interestToList = lendingProtocol.calculateInterest(loanId);

        vm.startPrank(borrower);
        uint256 lenderBalanceBefore = weth.balanceOf(lender);
        uint256 borrowerBalanceBefore = weth.balanceOf(borrower);

        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(uint8(loan.status), uint8(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID"); // Qualified
        assertEq(testNft.ownerOf(BORROWER_NFT_ID), borrower, "NFT should be returned to borrower");
        assertEq(weth.balanceOf(lender), lenderBalanceBefore + DEFAULT_PRINCIPAL + interestToList, "Lender balance incorrect");
        assertEq(weth.balanceOf(borrower), borrowerBalanceBefore - (DEFAULT_PRINCIPAL + interestToList), "Borrower balance incorrect");
        assertEq(loan.accruedInterest, interestToList, "Accrued interest stored incorrectly");
    }

    function test_Fail_RepayLoan_NotBorrower() public {
        (bytes32 loanId, ) = _makeAndGetActiveLoan();
        vm.startPrank(otherUser); // Not the borrower
        vm.expectRevert("LP: Not borrower");
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_Fail_RepayLoan_PastDue() public {
        (bytes32 loanId, ) = _makeAndGetActiveLoan();
        vm.warp(block.timestamp + DEFAULT_DURATION_SECONDS + 1 days); // Past due
        vm.startPrank(borrower);
        // LML:repayLoan has: require(block.timestamp <= currentLoan.dueTime, "LML: Loan past due (defaulted)");
        vm.expectRevert("LML: Loan past due (defaulted)");
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();
    }

    function test_GetLoan_ViewFunction() public {
        (bytes32 loanId, ) = _makeAndGetActiveLoan();
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId); // Qualified
        assertEq(loan.loanId, loanId);
        assertEq(loan.borrower, borrower);
        assertEq(loan.lender, lender);
    }

    function test_IsLoanRepayable_And_IsLoanInDefault_ViewFunctions() public {
        (bytes32 loanId, ) = _makeAndGetActiveLoan();
        assertTrue(lendingProtocol.isLoanRepayable(loanId), "Loan should be repayable");
        assertFalse(lendingProtocol.isLoanInDefault(loanId), "Loan should not be in default initially");

        vm.warp(block.timestamp + DEFAULT_DURATION_SECONDS + 1 days); // Past due
        assertFalse(lendingProtocol.isLoanRepayable(loanId), "Loan should not be repayable after due time");
        assertTrue(lendingProtocol.isLoanInDefault(loanId), "Loan should be in default after due time");
    }

    // TODO: test_Fail_RepayLoan_InsufficientFunds (requires modifying borrower's balance or approval)
    // TODO: test_ClaimCollateral_Success (after default, involves LoanManagementLogic.setLoanStatusDefaulted and CollateralLogic)
    // TODO: test_RefinanceLoan_Success and failure cases
    // TODO: test_ProposeRenegotiation_Success and failure cases
    // TODO: test_AcceptRenegotiation_Success and failure cases
}

// Minimal mock for AddressProvider if needed by CurrencyManager's addCurrency
contract MockAddressProvider {
    address private _feed;
    constructor(address feed) { _feed = feed; }
}

// Minimal mock for RangeValidator if needed by CollectionManager
contract MockRangeValidator {
    address private _validator;
    constructor(address validator) { _validator = validator; }
}
