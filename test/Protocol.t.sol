// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {LendingProtocol} from "../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {CollectionManager} from "../src/core/CollectionManager.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {PurchaseBundler} from "../src/core/PurchaseBundler.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";

// Mocks - Updated to local mocks
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";

contract ProtocolTest is Test {
    LendingProtocol lendingProtocol;
    CurrencyManager currencyManager;
    CollectionManager collectionManager;
    VaultsFactory vaultsFactory;
    Liquidation liquidation;
    PurchaseBundler purchaseBundler;

    ERC20Mock weth;
    ERC20Mock usdc;
    ERC721Mock nftCollection;

    address alice = vm.addr(1); // Lender
    address bob = vm.addr(2); // Borrower
    address charlie = vm.addr(3); // Another user

    uint256 constant WETH_STARTING_BALANCE = 1000 ether;
    uint256 constant USDC_STARTING_BALANCE = 1000000 * 1e6; // 1M USDC

    function setUp() public {
        // Deploy Mock Tokens
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy NFT Collection
        nftCollection = new ERC721Mock("Test NFT", "TNFT");

        // Deploy Managers
        address[] memory initialCurrencies = new address[](1);
        initialCurrencies[0] = address(weth);
        currencyManager = new CurrencyManager(initialCurrencies);
        currencyManager.addSupportedCurrency(address(usdc));

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(nftCollection);
        collectionManager = new CollectionManager(initialCollections);

        // Deploy VaultsFactory (optional)
        vaultsFactory = new VaultsFactory("Test Vaults", "TVF");

        // Deploy Liquidation and PurchaseBundler (need LP address later)
        liquidation = new Liquidation(address(0));
        purchaseBundler = new PurchaseBundler(address(0));

        // Deploy LendingProtocol
        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory),
            address(liquidation),
            address(purchaseBundler)
        );

        // Set LP address in Liquidation and PurchaseBundler
        liquidation.setLendingProtocol(address(lendingProtocol));
        purchaseBundler.setLendingProtocol(address(lendingProtocol));

        // Fund users
        weth.mint(alice, WETH_STARTING_BALANCE);
        weth.mint(bob, WETH_STARTING_BALANCE);
        usdc.mint(alice, USDC_STARTING_BALANCE);
        usdc.mint(bob, USDC_STARTING_BALANCE);

        // Mint NFT to Bob
        nftCollection.mint(bob, 1);
        nftCollection.mint(bob, 2);
    }

    function test_InitialSetup() public {
        assertTrue(currencyManager.isCurrencySupported(address(weth)));
        assertTrue(currencyManager.isCurrencySupported(address(usdc)));
        assertTrue(collectionManager.isCollectionWhitelisted(address(nftCollection)));
        assertEq(nftCollection.ownerOf(1), bob);
    }

    function test_LenderMakesOffer_BorrowerAccepts_RepaysLoan() public {
        // Alice (lender) makes an offer
        uint256 principal = 1 ether;
        uint256 apr = 500; // 5%
        uint256 duration = 30 days;
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 originationFee = 100; // 1%

        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), principal + (principal * originationFee / 10000));

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 1,
            currency: address(weth),
            principalAmount: principal,
            interestRateAPR: apr,
            durationSeconds: duration,
            expirationTimestamp: expiration,
            originationFeeRate: originationFee,
            totalCapacity: 0, // Not used for standard offer
            maxPrincipalPerLoan: 0, // Not used for standard offer
            minNumberOfLoans: 0 // Not used for standard offer
        });

        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        ILendingProtocol.LoanOffer memory offer = lendingProtocol.getLoanOffer(offerId);
        assertTrue(offer.isActive);
        assertEq(offer.lender, alice);

        // Bob (borrower) accepts the offer
        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        bytes32 loanId = lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.borrower, bob);
        assertEq(loan.lender, alice);
        assertEq(loan.principalAmount, principal);
        assertEq(nftCollection.ownerOf(1), address(lendingProtocol));
        assertTrue(
            weth.balanceOf(bob) >= WETH_STARTING_BALANCE + principal - (principal * originationFee / 10000) - 100 wei
        );

        // Fast forward time (but not past due date)
        vm.warp(block.timestamp + 15 days);

        // Bob repays the loan
        uint256 interest = lendingProtocol.calculateInterest(loanId);
        uint256 totalRepayment = principal + interest;

        vm.startPrank(bob);
        weth.approve(address(lendingProtocol), totalRepayment);
        lendingProtocol.repayLoan(loanId);
        vm.stopPrank();

        loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LoanStatus.REPAID), "Loan status should be REPAID");
        assertEq(nftCollection.ownerOf(1), bob);
        assertTrue(weth.balanceOf(alice) > WETH_STARTING_BALANCE);
    }

    function test_Fail_AcceptExpiredOffer() public {
        vm.startPrank(alice);
        weth.approve(address(lendingProtocol), 1 ether);

        ILendingProtocol.OfferParams memory offerParams = ILendingProtocol.OfferParams({
            offerType: ILendingProtocol.OfferType.STANDARD,
            nftContract: address(nftCollection),
            nftTokenId: 1,
            currency: address(weth),
            principalAmount: 1 ether,
            interestRateAPR: 500,
            durationSeconds: 30 days,
            expirationTimestamp: uint64(block.timestamp + 1 hours),
            originationFeeRate: 0,
            totalCapacity: 0,
            maxPrincipalPerLoan: 0,
            minNumberOfLoans: 0
        });
        bytes32 offerId = lendingProtocol.makeLoanOffer(offerParams);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours); // Expire the offer

        vm.startPrank(bob);
        nftCollection.approve(address(lendingProtocol), 1);
        vm.expectRevert("Offer expired");
        lendingProtocol.acceptLoanOffer(offerId, address(nftCollection), 1);
        vm.stopPrank();
    }

    // Add more tests:
    // - Collection offers
    // - Refinancing
    // - Renegotiation
    // - Liquidation (claim collateral, auction)
    // - Sell & Repay
    // - Vaults
    // - Edge cases, security checks (reentrancy, access control)
}
