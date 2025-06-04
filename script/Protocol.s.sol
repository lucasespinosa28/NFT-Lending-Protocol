// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
//import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

import {LendingProtocol} from "../src/core/LendingProtocol.sol";
import {CurrencyManager} from "../src/core/CurrencyManager.sol";
import {CollectionManager} from "../src/core/CollectionManager.sol";
import {VaultsFactory} from "../src/core/VaultsFactory.sol";
import {Liquidation} from "../src/core/Liquidation.sol";
import {PurchaseBundler} from "../src/core/PurchaseBundler.sol";
import {RangeValidator} from "../src/core/RangeValidator.sol";
import {Stash} from "../src/core/Stash.sol";

// Mocks - Updated to local mocks
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {ERC721Mock} from "../src/mocks/ERC721Mock.sol";


contract DeployProtocol is Script {
    CurrencyManager currencyManager;
    CollectionManager collectionManager;
    VaultsFactory vaultsFactory;
    Liquidation liquidation;
    PurchaseBundler purchaseBundler;
    RangeValidator rangeValidator;
    // Stash stash; // Deploy if needed for specific collections
    LendingProtocol lendingProtocol;

    ERC20Mock weth;
    ERC20Mock usdc;
    ERC721Mock mockNftCollection1;

    function run() external returns (
        LendingProtocol,
        CurrencyManager,
        CollectionManager,
        VaultsFactory, // Can be address(0) if not used
        Liquidation,
        PurchaseBundler
    ) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // If no private key, use a default for local testing
        // address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock Tokens (for local/testnet)
        weth = new ERC20Mock("Wrapped Ether", "WETH");
        usdc = new ERC20Mock("USD Coin", "USDC");
        console.log("Deployed WETH at:", address(weth));
        console.log("Deployed USDC at:", address(usdc));

        mockNftCollection1 = new ERC721Mock("Mock NFT Collection 1", "MNFT1");
        console.log("Deployed MockNFTCollection1 at:", address(mockNftCollection1));

        // 2. Deploy Managers & Validators
        address[] memory initialCurrencies = new address[](2);
        initialCurrencies[0] = address(weth);
        initialCurrencies[1] = address(usdc);
        currencyManager = new CurrencyManager(initialCurrencies);
        console.log("Deployed CurrencyManager at:", address(currencyManager));

        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(mockNftCollection1);
        collectionManager = new CollectionManager(initialCollections);
        console.log("Deployed CollectionManager at:", address(collectionManager));

        rangeValidator = new RangeValidator(); // Basic validator
        console.log("Deployed RangeValidator at:", address(rangeValidator));

        // 3. Deploy VaultsFactory (optional, can be address(0) if not used initially)
        vaultsFactory = new VaultsFactory("NFT Vault Shares", "NVS");
        console.log("Deployed VaultsFactory at:", address(vaultsFactory));

        // 4. Deploy Liquidation and PurchaseBundler (these need LendingProtocol address, but LP needs them too - chicken/egg)
        // Temporary: Deploy them, then set addresses later, or deploy LP first and then set its dependencies.
        // For simplicity, deploy LP first, then deploy these and set them on LP.
        // OR, deploy these with address(0) for LP, then update.
        // Let's deploy LP first, then these, then set on LP. This is cleaner.

        // 5. Deploy LendingProtocol (dependencies will be set after they are deployed)
        // For now, deploy with placeholder addresses or address(0) and set later.
        // This is not ideal. A better pattern might be for LP to allow setting these post-deployment.
        // The current LP constructor requires them. So, we deploy them first.

        // Re-order: Deploy dependencies of LP first.
        // Liquidation and PurchaseBundler need LP address.
        // Let's assume they are set via an `initialize` or `setLendingProtocol` function.

        // Deploy Liquidation (will need setLendingProtocol called on it)
        // For constructor, it takes LP address. We'll deploy LP and then set it.
        // This means Liquidation and PurchaseBundler might need a setter for LP,
        // or LP needs setters for them. The provided interfaces imply LP has setters.

        // Deploy core protocol components
        // The Liquidation and PurchaseBundler contracts in this example take the LP address in constructor
        // This creates a circular dependency if LP also takes them in constructor.
        // Let's modify Liquidation and PurchaseBundler to have a setter for LP,
        // and LP takes them in its constructor.

        // So, deploy Liquidation and PurchaseBundler *without* LP address initially,
        // then deploy LP, then call setters on Liquidation/PurchaseBundler.
        // OR, LP constructor takes them, and they are deployed first.
        // The current core contracts for Liquidation & PurchaseBundler take LP in constructor.
        // This means LP must be deployed *after* them, and they get a dummy or pre-known LP address.
        // This is complex. A common pattern:
        // - Deploy A, B, C (managers)
        // - Deploy MainContract (takes A,B,C)
        // - Deploy D, E (depend on MainContract)
        // - MainContract.setDependencies(D,E)
        // - D.setMainContract(MainContractAddress)
        // - E.setMainContract(MainContractAddress)

        // Let's stick to LP taking dependencies in constructor.
        // Liquidation and PurchaseBundler will be deployed first.
        // They will need a `setLendingProtocol` function, which they have.
        // So, deploy them, then deploy LP with their addresses, then call setLendingProtocol on them.

        liquidation = new Liquidation(address(0)); // Deploy with temp address(0) for LP
        console.log("Deployed Liquidation at:", address(liquidation));

        purchaseBundler = new PurchaseBundler(address(0)); // Deploy with temp address(0) for LP
        console.log("Deployed PurchaseBundler at:", address(purchaseBundler));


        lendingProtocol = new LendingProtocol(
            address(currencyManager),
            address(collectionManager),
            address(vaultsFactory), // Use address(vaultsFactory) or address(0)
            address(liquidation),
            address(purchaseBundler)
        );
        console.log("Deployed LendingProtocol at:", address(lendingProtocol));

        // Now set the LendingProtocol address in Liquidation and PurchaseBundler
        liquidation.setLendingProtocol(address(lendingProtocol));
        console.log("Set LendingProtocol on Liquidation contract");
        purchaseBundler.setLendingProtocol(address(lendingProtocol));
        console.log("Set LendingProtocol on PurchaseBundler contract");

        // Transfer ownership of ownable contracts to a Gnosis Safe or a governance contract
        // address multisig = address(0x...); // Your multisig/governance address
        // currencyManager.transferOwnership(multisig);
        // collectionManager.transferOwnership(multisig);
        // ... and so on for all Ownable contracts.

        vm.stopBroadcast();

        return (
            lendingProtocol,
            currencyManager,
            collectionManager,
            vaultsFactory,
            liquidation,
            purchaseBundler
        );
    }
}

