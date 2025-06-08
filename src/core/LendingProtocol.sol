// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ILendingProtocol} from "../interfaces/ILendingProtocol.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// ReentrancyGuard is inherited via managers

// Manager contracts to inherit from
import {OfferManager} from "./lending/OfferManager.sol";
import {LoanManager} from "./lending/LoanManager.sol";
import {AdminManager} from "./lending/AdminManager.sol";

// Interfaces for state variables
import {ICurrencyManager} from "../interfaces/ICurrencyManager.sol";
import {ICollectionManager} from "../interfaces/ICollectionManager.sol";
import {IVaultsFactory} from "../interfaces/IVaultsFactory.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";
import {IPurchaseBundler} from "../interfaces/IPurchaseBundler.sol";
import {IRoyaltyManager} from "../interfaces/IRoyaltyManager.sol";
import {IIPAssetRegistry} from "@storyprotocol/contracts/interfaces/registries/IIPAssetRegistry.sol";

contract LendingProtocol is
    ILendingProtocol,
    OfferManager,
    LoanManager,
    AdminManager
{
    ICurrencyManager public currencyManager;
    ICollectionManager public collectionManager;
    IVaultsFactory public vaultsFactory;
    ILiquidation public liquidationContract;
    IPurchaseBundler public purchaseBundler;
    IRoyaltyManager public royaltyManager;
    IIPAssetRegistry public ipAssetRegistry;

    constructor(
        address _currencyManager,
        address _collectionManager,
        address _vaultsFactory,
        address _liquidationContract,
        address _purchaseBundler,
        address _royaltyManager,
        address _ipAssetRegistry
    ) AdminManager() { // Calls AdminManager's constructor which calls Ownable(msg.sender)
        require(_currencyManager != address(0), "LP: CurrencyManager zero address");
        require(_collectionManager != address(0), "LP: CollectionManager zero address");
        require(_liquidationContract != address(0), "LP: LiquidationContract zero address");
        require(_purchaseBundler != address(0), "LP: PurchaseBundler zero address");
        require(_royaltyManager != address(0), "LP: RoyaltyManager zero address");
        require(_ipAssetRegistry != address(0), "LP: IPAssetRegistry zero address");

        currencyManager = ICurrencyManager(_currencyManager);
        collectionManager = ICollectionManager(_collectionManager);
        if (_vaultsFactory != address(0)) {
            vaultsFactory = IVaultsFactory(_vaultsFactory);
        }
        liquidationContract = ILiquidation(_liquidationContract);
        purchaseBundler = IPurchaseBundler(_purchaseBundler);
        royaltyManager = IRoyaltyManager(_royaltyManager);
        ipAssetRegistry = IIPAssetRegistry(_ipAssetRegistry);
    }

    // --- Bridging functions for Manager Contracts ---
    // These are LendingProtocol's implementations of virtual functions declared in managers,
    // allowing managers to access shared state or cross-manager functionality via LendingProtocol.

    // For OfferManager, LoanManager
    function _getCurrencyManager() internal view override(OfferManager, LoanManager) returns (ICurrencyManager) {
        return currencyManager;
    }

    // For OfferManager, LoanManager
    function _getCollectionManager() internal view override(OfferManager, LoanManager) returns (ICollectionManager) {
        return collectionManager;
    }

    // For LoanManager
    function _getVaultsFactory() internal view override(LoanManager) returns (IVaultsFactory) {
        return vaultsFactory;
    }

    function _getIpAssetRegistry() internal view override(LoanManager) returns (IIPAssetRegistry) {
        return ipAssetRegistry;
    }

    function _getRoyaltyManager() internal view override(LoanManager) returns (IRoyaltyManager) {
        return royaltyManager;
    }

    function _getPurchaseBundler() internal view override(LoanManager) returns (IPurchaseBundler) {
        return purchaseBundler;
    }

    // Bridge for LoanManager to access OfferManager's public getLoanOffer
    function _getLoanOffer(bytes32 offerId) internal view override(LoanManager) returns (ILendingProtocol.LoanOffer memory) {
        return this.getLoanOffer(offerId); // Calls OfferManager.getLoanOffer() via inheritance
    }

    // Bridge for LoanManager to access OfferManager's internal _setLoanOfferInactive
    function _setLoanOfferInactive(bytes32 offerId) internal override(LoanManager, OfferManager) {
        OfferManager._setLoanOfferInactive(offerId); // DIAGNOSTIC: Explicit call
    }

    // --- AdminManager setter implementations ---
    function _setCurrencyManager(ICurrencyManager newManager) internal override(AdminManager) { currencyManager = newManager; }
    function _setCollectionManager(ICollectionManager newManager) internal override(AdminManager) { collectionManager = newManager; }
    function _setVaultsFactory(IVaultsFactory newFactory) internal override(AdminManager) { vaultsFactory = newFactory; }
    function _setLiquidationContract(ILiquidation newContract) internal override(AdminManager) { liquidationContract = newContract; }
    function _setPurchaseBundler(IPurchaseBundler newBundler) internal override(AdminManager) { purchaseBundler = newBundler; }
    function _setRoyaltyManager(IRoyaltyManager newManager) internal override(AdminManager) { royaltyManager = newManager; }
    function _setIpAssetRegistry(IIPAssetRegistry newRegistry) internal override(AdminManager) { ipAssetRegistry = newRegistry; }

    // --- ILendingProtocol Interface Implementation ---
    // These functions override both ILendingProtocol and the respective manager's virtual function.
    // They delegate the call to the manager's implementation via `super`.

    function makeLoanOffer(ILendingProtocol.OfferParams calldata params) public override(ILendingProtocol, OfferManager) returns (bytes32 offerId) {
        return super.makeLoanOffer(params);
    }

    function acceptLoanOffer(bytes32 offerId, address nftContract, uint256 nftTokenId) public override(ILendingProtocol, LoanManager) returns (bytes32 loanId) {
        return super.acceptLoanOffer(offerId, nftContract, nftTokenId);
    }

    function cancelLoanOffer(bytes32 offerId) public override(ILendingProtocol, OfferManager) {
        super.cancelLoanOffer(offerId);
    }

    function repayLoan(bytes32 loanId) public override(ILendingProtocol, LoanManager) {
        super.repayLoan(loanId);
    }

    function claimAndRepay(bytes32 loanId) public override(ILendingProtocol, LoanManager) {
        super.claimAndRepay(loanId);
    }

    function claimCollateral(bytes32 loanId) public override(ILendingProtocol, LoanManager) {
        super.claimCollateral(loanId);
    }

    function listCollateralForSale(bytes32 loanId, uint256 price) public override(ILendingProtocol, LoanManager) {
        super.listCollateralForSale(loanId, price);
    }

    function cancelCollateralSale(bytes32 loanId) public override(ILendingProtocol, LoanManager) {
        super.cancelCollateralSale(loanId);
    }

    function buyCollateralAndRepay(bytes32 loanId, uint256 salePrice) public override(ILendingProtocol, LoanManager) {
        super.buyCollateralAndRepay(loanId, salePrice);
    }

    function recordLoanRepaymentViaSale(bytes32 loanId, uint256 principalRepaid, uint256 interestRepaid) public override(ILendingProtocol, LoanManager) {
        super.recordLoanRepaymentViaSale(loanId, principalRepaid, interestRepaid);
    }

    function getLoan(bytes32 loanId) public view override(ILendingProtocol, LoanManager) returns (ILendingProtocol.Loan memory) {
        return super.getLoan(loanId);
    }

    function getLoanOffer(bytes32 offerId) public view override(ILendingProtocol, OfferManager) returns (ILendingProtocol.LoanOffer memory) {
        return super.getLoanOffer(offerId);
    }

    function calculateInterest(bytes32 loanId) public view override(ILendingProtocol, LoanManager) returns (uint256 interestDue) {
        return super.calculateInterest(loanId);
    }

    function isLoanRepayable(bytes32 loanId) public view override(ILendingProtocol, LoanManager) returns (bool) {
        return super.isLoanRepayable(loanId);
    }

    function isLoanInDefault(bytes32 loanId) public view override(ILendingProtocol, LoanManager) returns (bool) {
        return super.isLoanInDefault(loanId);
    }

    // onERC721Received is handled by LoanManager and inherited.
    // LendingProtocol is an IERC721Receiver via LoanManager.

    // Bridge functions previously used by RefinanceManager that might still be needed by LoanManager internally,
    // or were overridden by LoanManager. We need to ensure LoanManager still has these if it declares them.
    // If LoanManager._setLoanStatus, _incrementLoanCounter, _addLoan, _updateLoanAfterRenegotiation
    // were *only* overridden to be exposed to RefinanceManager from LendingProtocol,
    // and LoanManager itself doesn't have a `super` call to a base version of these,
    // then their declarations in LoanManager might become unused if not called internally.
    // For now, we assume LoanManager's own versions are sufficient.
    // We removed the LendingProtocol level overrides that specified RefinanceManager.
    // LoanManager's own declarations of these (if any) are untouched by this diff.

    receive() external payable {}
}
