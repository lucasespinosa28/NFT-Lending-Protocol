# Feature Audit Report: NFT Loan and Borrow Platform for Story IP

## 1. Introduction

The purpose of this report is to audit the implemented features of the NFT Loan and Borrow Platform against the functionalities described in its `README.md`. This audit verifies the presence and nature of key features within the platform's smart contracts, based on a review of the codebase.

## 2. Methodology

The audit was conducted through the following steps:
1.  The `README.md` file was thoroughly analyzed to compile a comprehensive list of all described features and functionalities.
2.  Core smart contracts, primarily `LendingProtocol.sol`, `LoanManager.sol` (in `src/core/lending/`), `OfferManager.sol` (in `src/core/lending/`), `RoyaltyManager.sol` (in `src/core/`), and `Liquidation.sol` (in `src/core/`), were reviewed.
3.  Each feature identified from the README was systematically cross-referenced with the codebase to ascertain its implementation status and the specifics of its operation.

## 3. Core Feature Audit

This section details each key feature, its description from the README, its implementation status, and a brief explanation of how it's implemented in the contracts.

### 3.1. NFT as Collateral
- **README Description:** Users can lock their story IP NFTs in smart contracts to borrow stablecoins or other cryptocurrencies.
- **Status:** Implemented
- **Implementation Details:**
    - Collateral is secured within the `LoanManager.sol` contract during the `acceptLoanOffer` function. This is achieved by transferring the borrower's NFT to the `LoanManager` contract address using `IERC721(...).safeTransferFrom(msg.sender, address(this), ...)`.
    - Details of the collateral, such as the NFT contract address (`nftContract`) and the specific token ID (`nftTokenId`), are stored within the `Loan` struct (defined in `ILendingProtocol.sol` and utilized in `LoanManager.sol`'s `loans` mapping).

### 3.2. Loan Origination
- **README Description:** Lenders can offer loans with specific terms (interest rate, duration, loan-to-value ratio) or contribute to liquidity pools.
- **Status:**
    - Lender-defined loan offers: Implemented
    - Pool Lending: Partially Implemented (as "Collection Offer by Single Lender")
- **Implementation Details (Lender-Defined Loan Offers):**
    - `OfferManager.sol` contract's `makeLoanOffer` function enables lenders (`msg.sender`) to create new loan offers.
    - Loan terms are specified using `ILendingProtocol.OfferParams`, which include parameters like `nftContract`, `nftTokenId` (for offers targeting specific NFTs), `currency`, `principalAmount`, `interestRateAPR`, `durationSeconds`, `expirationTimestamp`, and `originationFeeRate`.
    - Offers can be `OfferType.STANDARD` (for a unique NFT) or `OfferType.COLLECTION` (for any NFT within a specified collection).
    - Active offers are stored in the `loanOffers` mapping within `OfferManager.sol`.
- **Implementation Details (Collection Offers - Partial "Pool Lending"):**
    - The `makeLoanOffer` function in `OfferManager.sol`, when used with `OfferType.COLLECTION`, allows a lender to specify a `totalCapacity` and `maxPrincipalPerLoan` for a particular NFT collection. This enables a single lender's offer to potentially fund multiple loans.
    - This mechanism differs from traditional liquidity pools where multiple lenders contribute capital to a common, fungible pool from which loans are disbursed.

### 3.3. Interest Accrual
- **README Description:** Interest is accrued over the loan period, payable by the borrower.
- **Status:** Implemented
- **Implementation Details:**
    - `LoanManager.sol` features a `calculateInterest` view function that computes the interest due for a given `loanId`.
    - The calculation is `(loan.principalAmount * loan.interestRateAPR * timeElapsed) / (365 days * 10000)`.
    - `timeElapsed` is the duration from `loan.startTime` to the current `block.timestamp` or `loan.dueTime`, whichever is earlier.
    - The calculated interest is factored into repayment amounts in functions like `repayLoan` and `claimAndRepay`.

### 3.4. Liquidation
- **README Description:** If a borrower defaults on their loan (e.g., fails to repay within the agreed timeframe, or the collateral value drops significantly), the platform allows for the liquidation of the NFT to cover the outstanding debt. Methods include transferring the NFT to the lender or auctioning it.
- **Status:** Implemented (Note: LTV-based default trigger not apparent)
- **Implementation Details:**
    - **Default Condition:** Default is primarily time-based, determined by the `isLoanInDefault` function in `LoanManager.sol` (`block.timestamp > loan.dueTime`). Liquidation triggered by a significant drop in collateral value (LTV threshold breach) is not explicitly found in the reviewed core contracts.
    - **Direct Claim by Lender:** `LoanManager.sol`'s `claimCollateral` function permits the lender to take direct ownership of the NFT if the loan is defaulted.
    - **Auction Mechanism:** `Liquidation.sol` provides comprehensive auction functionalities:
        - `startAuction`: Initiated by the `LendingProtocol` contract for defaulted loans.
        - `placeBid`: Allows bidding on active auctions.
        - `endAuction`: Finalizes auctions.
        - `distributeProceeds`: Distributes auction proceeds if the NFT is sold.
        - `claimCollateralPostAuction`: Handles scenarios where an auction ends with no bids.
    - **Other Sale/Buyout Mechanisms:**
        - `LoanManager.sol` includes `listCollateralForSale` (borrower can list) and `buyCollateralAndRepay` (third-party purchase), suggesting integration with `PurchaseBundler.sol`.
        - `Liquidation.sol` also implements a `initiateBuyout` and `executeBuyout` feature, potentially for lenders.

### 3.5. Story IP Focus
- **README Description:** The platform is specifically designed for NFTs representing rights to stories, scripts, characters, and other narrative-based intellectual property.
- **Status:** Implemented (by design and integration points)
- **Implementation Details:**
    - `LendingProtocol.sol` is configured with addresses for Story Protocol's `IIPAssetRegistry` (`ipAssetRegistry`) and an `IRoyaltyManager` (`royaltyManager`).
    - In `LoanManager.sol`, the `acceptLoanOffer` function queries the `ipAssetRegistry` (using `ipId()` and `isRegistered()`) to verify if the collateral NFT is a registered Story Protocol IP.
    - If confirmed, `isStoryAsset` is set to true, and the `storyIpId` is stored with the loan, enabling features like royalty-backed repayments.

### 3.6. Story Protocol Integration for Royalty-Backed Repayments
- **README Description:** The platform is deeply integrated with Story Protocol, allowing borrowers to use future royalties generated by their IP as a means to repay their loans. This involves the `RoyaltyManager` calling Story Protocol's `RoyaltyModule`.
- **Status:** Implemented (Note: Relies on a `MockRoyaltyModule`)
- **Implementation Details:**
    - The `claimAndRepay` function in `LoanManager.sol` manages this process.
    - It instructs `RoyaltyManager.sol` (via `claimRoyalty`) to collect royalties for the loan's `storyIpId`.
    - `RoyaltyManager.sol`'s `claimRoyalty` function currently calls `MockRoyaltyModule(address(ROYALTY_MODULE)).collectRoyaltyTokens(...)`. This `collectRoyaltyTokens` function is part of the mock setup and simulates the action of Story Protocol's actual `RoyaltyModule`, transferring "claimed" royalties to the `RoyaltyManager` contract.
    - `RoyaltyManager.sol` tracks these funds in `ipaRoyaltyClaims`.
    - `LoanManager.sol` then retrieves the balance from `RoyaltyManager.sol` (via `getRoyaltyBalance`) and directs it to withdraw the necessary amount (via `withdrawRoyalty`) and transfer it to the lender to settle the loan.

## 4. Conceptual Flow Verification

This section assesses the implementation of the "How it Works (Conceptual Flow)" described in the README.

### 4.1. NFT Minting (External)
- **README:** An external prerequisite. For Story Protocol integration, the NFT must be registered with the `IPAssetRegistry`.
- **Status:** Confirmed. The `LoanManager.sol` contract (`acceptLoanOffer`) checks the `IPAssetRegistry` as expected.

### 4.2. User Registration (Optional)
- **README:** States users *might* need to register.
- **Status:** Not Implemented. No explicit user registration system was found in the core smart contracts.

### 4.3. Loan Request (Borrower)
- **README:** Describes a borrower listing their NFT and specifying desired loan terms.
- **Status:** Implemented Differently.
- **Details:** The current system is lender-centric. Lenders `makeLoanOffer` (via `OfferManager.sol`), and borrowers `acceptLoanOffer` (via `LoanManager.sol`). There is no mechanism for borrowers to first list their NFTs to solicit offers.

### 4.4. Loan Offer (Lender) / Pool Lending
- **README:** Lenders can make direct loan offers or contribute to liquidity pools.
- **Status:**
    - Direct Peer-to-Peer Offers: Implemented (via `OfferManager.sol`).
    - Pool Lending: Partially Implemented (as "Collection Offer by Single Lender," see section 3.2). True multi-lender liquidity pools are not present.

### 4.5. Loan Agreement
- **README:** A smart contract locks the NFT, disburses the loan, checks Story Protocol IP registration, and records loan terms.
- **Status:** Implemented.
- **Details:** These actions are handled by the `acceptLoanOffer` function in `LoanManager.sol`.

### 4.6. Standard Repayment
- **README:** The borrower repays the loan principal plus accrued interest; the NFT is returned.
- **Status:** Implemented.
- **Details:** Managed by the `repayLoan` function in `LoanManager.sol`.

### 4.7. Repayment via Royalties (Story Protocol Integration)
- **README:** Borrowers use `claimAndRepay`. `RoyaltyManager` calls Story Protocol's `RoyaltyModule`.
- **Status:** Implemented (via Mock `RoyaltyModule`).
- **Details:** As detailed in section 3.6. The flow involves `LoanManager.sol`'s `claimAndRepay` function and `RoyaltyManager.sol`, which interacts with the `MockRoyaltyModule`.

### 4.8. Default and Liquidation
- **README:** Triggered by non-repayment or LTV ratio exceeding a threshold. NFT can be transferred to the lender or auctioned.
- **Status:** Mostly Implemented.
- **Details:** Time-based default is implemented (`isLoanInDefault` in `LoanManager.sol`). LTV-based default trigger is not apparent. Liquidation occurs via direct lender claim (`claimCollateral` in `LoanManager.sol`), auction (`Liquidation.sol`), or other sale mechanisms (e.g., via `PurchaseBundler.sol`).

## 5. Summary of Gaps and Discrepancies

This section consolidates the identified differences and missing pieces between the README's description and the actual contract implementations.

*   **True Pool Lending:** The concept of multiple lenders contributing to a shared liquidity pool from which loans are made is **Not Implemented**. The existing "Collection Offer" in `OfferManager.sol` allows one lender to service multiple loans against a collection but isn't a pooled fund.
*   **Borrower-Initiated Loan Requests:** The README describes a flow where borrowers list NFTs and terms to solicit loans. This is **Not Implemented**. The current system is lender-initiated.
*   **LTV-Based Liquidation Trigger:** The README mentions liquidation due to significant drops in collateral value or LTV thresholds being breached. This specific trigger mechanism is **Not Apparent** in the core contracts; default is primarily time-based. This would likely require an oracle for NFT valuation, which is not present.
*   **`RoyaltyModule` Integration - Mock Dependency:** The royalty claim process in `RoyaltyManager.sol` relies on a `MockRoyaltyModule.sol` for the `collectRoyaltyTokens` call. While this allows testing the internal logic, it means the integration with the *actual* Story Protocol `RoyaltyModule` is not yet complete.
*   **User Registration (Optional):** As per its optional status in the README, this feature is **Not Implemented**.

## 6. Conclusion

The audit confirms that the NFT Loan and Borrow Platform has implemented a substantial set of the functionalities outlined in the `README.md`. Core mechanics such as NFT collateralization, lender-driven loan origination, interest calculation, standard repayment, and various liquidation pathways (direct claim, auction, direct sale) are present in the smart contracts.

The integration with Story Protocol for identifying IP assets (`IIPAssetRegistry`) and enabling royalty-backed repayments (`RoyaltyManager` and `MockRoyaltyModule`) is a key implemented feature, although the royalty collection currently depends on a mock component.

The primary deviations from the README include the absence of true multi-lender liquidity pools, the lack of a borrower-initiated loan request system, and no apparent LTV-based liquidation trigger. The reliance on a mock `RoyaltyModule` is a critical point for future development towards a production-ready system.

Future work should focus on addressing these gaps if they are deemed essential, particularly replacing the mock `RoyaltyModule` with a live integration, and considering the implementation of LTV-based triggers and potentially more sophisticated pooling mechanisms if desired.
