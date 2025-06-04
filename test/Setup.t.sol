// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol"; // console is kept for potential debugging in setup
import {Vm} from "forge-std/Vm.sol";

// Imports from Protocol.t.sol to be moved here
import {LendingProtocol} from "../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {CollectionManager} from "../src/core/CollectionManager.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {PurchaseBundler} from "../src/core/PurchaseBundler.sol";
import {ILendingProtocol} from "../src/interfaces/ILendingProtocol.sol";
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";

// Moved from bottom of Protocol.t.sol
interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// Moved from bottom of Protocol.t.sol
contract ReentrantBorrowerRepay is IERC721Receiver {
    LendingProtocol public lp;
    ERC20Mock public wethToken; // Renamed to avoid conflict with weth state variable in ProtocolSetup
    ERC721Mock public nftCollectionMock; // Renamed to avoid conflict
    bytes32 public loanId;
    uint256 public currentNftId; // Renamed to avoid conflict
    address public attacker;
    bool public reentrantCallMade;
    bool public reentrantCallSucceeded;

    constructor(LendingProtocol _lp, ERC20Mock _weth, ERC721Mock _nft, address _attacker) {
        lp = _lp;
        wethToken = _weth;
        nftCollectionMock = _nft;
        attacker = _attacker;
    }

    function setLoanId(bytes32 _loanId) public {
        loanId = _loanId;
    }

    function setNftId(uint256 _nftId) public { // Renamed from setNftId to avoid issues if inherited
        currentNftId = _nftId;
    }

    function approveNftToLP(address _lendingProtocol) public {
        nftCollectionMock.approve(_lendingProtocol, currentNftId);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        if (msg.sender == address(lp)) {
            reentrantCallMade = true;
            try lp.getLoan(loanId) {
                reentrantCallSucceeded = true;
            } catch {
                reentrantCallSucceeded = false;
            }
        }
        return this.onERC721Received.selector;
    }
}

contract ProtocolSetup is Test {
    // State variables moved from Protocol.t.sol
    LendingProtocol public lendingProtocol;
    CurrencyManager public currencyManager;
    CollectionManager public collectionManager;
    VaultsFactory public vaultsFactory;
    Liquidation public liquidation;
    PurchaseBundler public purchaseBundler;

    ERC20Mock public weth;
    ERC20Mock public usdc;
    ERC721Mock public nftCollection;

    address public alice = vm.addr(1); // Lender
    address public bob = vm.addr(2); // Borrower
    address public charlie = vm.addr(3); // Another user

    uint256 internal constant WETH_STARTING_BALANCE = 1000 ether;
    uint256 internal constant USDC_STARTING_BALANCE = 1000000 * 1e6; // 1M USDC

    // setUp function moved from Protocol.t.sol
    function setUp() public virtual {
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
        liquidation = new Liquidation(address(0)); // Initialize with address(0)
        purchaseBundler = new PurchaseBundler(address(0)); // Initialize with address(0)

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
        deal(address(weth), alice, WETH_STARTING_BALANCE);
        deal(address(weth), bob, WETH_STARTING_BALANCE);
        deal(address(usdc), alice, USDC_STARTING_BALANCE);
        deal(address(usdc), bob, USDC_STARTING_BALANCE);

        // Mint NFT to Bob
        nftCollection.mint(bob, 1);
        nftCollection.mint(bob, 2);

        // Mint NFT to Charlie
        nftCollection.mint(charlie, 3);

        // Fund Charlie
        deal(address(weth), charlie, WETH_STARTING_BALANCE);
        deal(address(usdc), charlie, USDC_STARTING_BALANCE);

        // Mint another NFT to Bob for vault testing
        nftCollection.mint(bob, 10);
    }
}
