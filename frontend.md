# Smart Contract Frontend Design

This document outlines the frontend design for the NFT Loan and Borrow Platform for Story IP. The frontend will provide a user-friendly interface for interacting with the platform's smart contracts.

## 1. Overall Design & Technology

*   **Single Page Application (SPA):** The frontend will likely be a SPA for a smooth and responsive user experience.
*   **Web3 Integration:** It will use a library like `ethers.js` or `web3.js` to connect to the user's Ethereum wallet (e.g., MetaMask) and interact with the deployed smart contracts.
*   **Responsive Design:** The UI will be responsive and accessible on various devices (desktop, tablet, mobile).
*   **Component-Based Architecture:** (e.g., React, Vue, Angular) for modularity and maintainability.
*   **Clear Visual Hierarchy:** Easy navigation and clear calls to action.
*   **Data Display:** Important information (loan terms, NFT details, balances) will be displayed prominently.

## 2. Key User Interface Sections & Elements

### 2.1. Header/Navigation Bar

*   **Logo/Project Name**
*   **Connect Wallet Button:** Allows users to connect their Ethereum wallet. Displays wallet address and balance once connected.
*   **Navigation Links:**
    *   **Borrow:** For users wanting to take out loans.
    *   **Lend:** For users wanting to offer loans or contribute to liquidity pools.
    *   **My Dashboard:** User-specific area to view active loans, collateral, offers, etc.
    *   **Marketplace/Explore NFTs (Optional):** A place to view NFTs available for loans or recently liquidated.

### 2.2. Wallet Connection

*   **Modal/Popup:** Prompts users to connect their wallet (MetaMask, WalletConnect, etc.).
*   **Status Indicator:** Shows connection status and current network.
*   **Network Switch Prompt:** If the user is on an unsupported network, guide them to switch.

### 2.3. Borrow Section

*   **My NFTs Tab:**
    *   Displays NFTs owned by the user (fetched from their connected wallet).
    *   Filter/Sort options (by name, collection, potential collateral value).
    *   For each NFT:
        *   Image/Preview.
        *   Name/ID.
        *   Brief description.
        *   Option to "Use as Collateral."
*   **Create Loan Request Page:**
    *   **Selected NFT Display:** Shows details of the NFT chosen as collateral.
    *   **Appraisal Value (if available):** Display estimated value of the NFT. This might be from an oracle or platform-defined.
    *   **Loan Amount Input:** Slider or input field for the desired loan amount (with LTV limits enforced).
    *   **Desired Loan Duration Input:** Options for loan length (e.g., 30, 60, 90 days).
    *   **Estimated Interest Rate Display:** Shows indicative interest rates based on market conditions or pool rates.
    *   **Summary:** Clearly lists loan amount, collateral, duration, estimated fees, and repayment amount.
    *   **"List for Loan" / "Borrow from Pool" Button:** Initiates the smart contract interaction to lock the NFT and create the loan request or borrow directly.
*   **Active Borrows Tab (in My Dashboard):**
    *   Lists all active loans taken by the user.
    *   For each loan:
        *   Collateral NFT details.
        *   Principal amount.
        *   Interest accrued.
        *   Remaining time / Maturity date.
        *   "Repay Loan" button.

### 2.4. Lend Section

*   **Available Collateral Tab / Marketplace:**
    *   Displays NFTs listed by borrowers seeking loans (peer-to-peer).
    *   Filter/Sort options (by requested amount, duration, NFT type).
    *   For each listed NFT:
        *   NFT details.
        *   Requested loan amount.
        *   Desired duration.
        *   Borrower's reputation/history (if implemented).
        *   Option to "Fund Loan" / "Make Offer."
*   **Fund Loan Page (Peer-to-Peer):**
    *   Displays details of the loan request.
    *   **Lender's Offer Input:** Interest rate, specific terms if configurable.
    *   **"Offer Loan" Button:** Initiates smart contract interaction to fund the loan and transfer funds to the borrower.
*   **Liquidity Pools Tab (if applicable):**
    *   Displays available liquidity pools (e.g., Stablecoin Pool).
    *   For each pool:
        *   Total liquidity.
        *   Current lending APY.
        *   "Deposit" and "Withdraw" buttons.
    *   **Deposit Modal:** Input for amount to deposit.
    *   **Withdraw Modal:** Input for amount to withdraw (showing available liquidity share).
*   **Active Loans Funded Tab (in My Dashboard):**
    *   Lists all loans funded by the user.
    *   For each loan:
        *   Borrower details (anonymized ID).
        *   Collateral NFT preview.
        *   Principal lent.
        *   Interest earned.
        *   Maturity date.
        *   Status (Active, Repaid, Defaulted).

### 2.5. My Dashboard Section

*   **Summary View:** Overview of user's total borrowed amount, total lent amount, active collateral, net APY.
*   **My Collateral:** NFTs currently locked as collateral.
*   **My Borrows:** Detailed list of active and past loans taken.
    *   Option to repay active loans.
*   **My Loans (Lent):** Detailed list of active and past loans funded (P2P).
*   **My Pool Deposits:** Details of liquidity provided to pools.
*   **Notifications/Alerts:** Loan maturity reminders, liquidation warnings, new offers.

### 2.6. NFT Details Page (General)

*   Accessible from various sections.
*   **Full NFT Image/Media.**
*   **Comprehensive Metadata:** Story IP details, creator, link to IP content.
*   **Ownership History (if available).**
*   **Current Loan Status (if applicable):** Whether it's collateral, available for loan, etc.
*   **Valuation History (if available).**

## 3. User Interaction Flows

### 3.1. Connecting Wallet

1.  User clicks "Connect Wallet."
2.  Wallet provider modal appears (e.g., MetaMask).
3.  User selects wallet and approves connection in their wallet application.
4.  Frontend updates to show connected status, address, and relevant balances.

### 3.2. Borrowing Process (Peer-to-Peer Example)

1.  User navigates to "Borrow" -> "My NFTs."
2.  Selects an NFT and clicks "Use as Collateral."
3.  Redirected to "Create Loan Request Page."
4.  Enters desired loan amount and duration.
5.  Reviews terms and clicks "List for Loan."
6.  Wallet prompts for transaction confirmation (to approve NFT transfer and list).
7.  Once confirmed, NFT is listed, and the request appears in the "Available Collateral" for lenders.

### 3.3. Lending Process (Peer-to-Peer Example)

1.  User navigates to "Lend" -> "Available Collateral."
2.  Browses listed NFTs and selects one.
3.  Clicks "Fund Loan."
4.  Reviews borrower's request and loan terms. May input their offered interest rate if applicable.
5.  Clicks "Offer Loan" / "Fund Loan."
6.  Wallet prompts for transaction confirmation (to transfer loan funds).
7.  Once confirmed, loan is active, NFT is locked in the smart contract, and funds are disbursed to the borrower.

### 3.4. Repaying a Loan

1.  User navigates to "My Dashboard" -> "My Borrows."
2.  Selects an active loan and clicks "Repay Loan."
3.  Frontend displays total repayment amount (principal + interest).
4.  User clicks "Confirm Repayment."
5.  Wallet prompts for transaction confirmation (to transfer repayment funds).
6.  Once confirmed, funds are transferred, and the smart contract releases/unlocks the collateral NFT back to the borrower.

### 3.5. Liquidation Process (Simplified)

1.  **Automated Check (Backend/Keepers) or Manual Trigger (Lender):** System identifies a defaulted loan (past maturity or LTV breached).
2.  **Frontend Display:**
    *   In "My Dashboard" (for lender): Shows loan in "Defaulted" status with "Liquidate Collateral" option.
    *   In a "Liquidations" or "Auction" section: Lists NFTs available for liquidation.
3.  **Lender Initiates Liquidation (if manual):**
    *   Lender clicks "Liquidate Collateral."
    *   Wallet prompts for transaction confirmation.
    *   Smart contract processes liquidation (e.g., transfers NFT to lender or starts an auction).
4.  **Auction (if implemented):**
    *   Users can bid on the NFT.
    *   Frontend facilitates bidding process.
    *   Highest bidder wins NFT after auction period.

## 4. Smart Contract Interactions

The frontend will primarily interact with the following types of smart contract functions:

*   **NFT Approval:** `approve()` on the NFT contract before locking it as collateral.
*   **Loan Management Contract:**
    *   `requestLoan(nftContractAddress, tokenId, loanAmount, duration)`
    *   `cancelLoanRequest(requestId)`
    *   `offerLoan(requestId, interestRate)` (P2P)
    *   `acceptLoanOffer(offerId)` (P2P)
    *   `borrowFromPool(poolId, amount, nftContractAddress, tokenId)` (Pool)
    *   `repayLoan(loanId)`
    *   `liquidateCollateral(loanId)`
    *   `claimCollateral(loanId)` (after successful liquidation by lender)
*   **Liquidity Pool Contract:**
    *   `deposit(amount)`
    *   `withdraw(shareAmount)`
*   **View Functions (for data display):**
    *   `getLoanDetails(loanId)`
    *   `getUserActiveLoans(userAddress)`
    *   `getNftLoanStatus(nftContractAddress, tokenId)`
    *   `getPoolStats(poolId)`
    *   `getOraclePrice(nftContractAddress, tokenId)` (if an oracle is used)

## 5. State Management

*   **Local UI State:** Component-level state for form inputs, modals, etc.
*   **Global Application State:** (e.g., using Redux, Zustand, Vuex, Context API)
    *   User's wallet connection status, address, network.
    *   Fetched data from smart contracts (loan lists, NFT details, pool info).
    *   Notifications and alerts.
*   **Data Fetching & Caching:** Efficiently query blockchain data and cache it where appropriate to reduce load times and RPC calls. Listen for contract events to update state proactively.

## 6. Error Handling & Notifications

*   **Clear Error Messages:** For transaction failures, network issues, insufficient funds, unmet contract conditions (e.g., LTV too high).
*   **Transaction Status Updates:** Pending, success, failure notifications (e.g., using toast messages).
*   **Input Validation:** Frontend validation for forms (e.g., loan amount within limits).
*   **Guidance:** Tooltips and helper texts for complex actions.

This frontend design provides a comprehensive starting point. Specific details and components will be refined during the development process.
