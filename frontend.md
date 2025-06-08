Smart Contract Frontend Design
This document outlines the frontend design for the NFT Loan and Borrow Platform for Story IP. The frontend will provide a user-friendly interface for interacting with the platform's smart contracts.

1. Overall Design & Technology
Single Page Application (SPA): The frontend will likely be a SPA for a smooth and responsive user experience.

Web3 Integration: It will use a library like ethers.js or web3.js to connect to the user's Ethereum wallet (e.g., MetaMask) and interact with the deployed smart contracts.

Responsive Design: The UI will be responsive and accessible on various devices (desktop, tablet, mobile).

Component-Based Architecture: (e.g., React, Vue, Angular) for modularity and maintainability.

Clear Visual Hierarchy: Easy navigation and clear calls to action.

Data Display: Important information (loan terms, NFT details, balances) will be displayed prominently.

2. Key User Interface Sections & Elements
2.1. Header/Navigation Bar
Logo/Project Name

Connect Wallet Button: Allows users to connect their Ethereum wallet. Displays wallet address and balance once connected.

Navigation Links:

Borrow: For users wanting to take out loans.

Lend: For users wanting to offer loans or contribute to liquidity pools.

My Dashboard: User-specific area to view active loans, collateral, offers, etc.

Marketplace/Explore NFTs (Optional): A place to view NFTs available for loans or recently liquidated.

2.2. Wallet Connection
Modal/Popup: Prompts users to connect their wallet (MetaMask, WalletConnect, etc.).

Status Indicator: Shows connection status and current network.

Network Switch Prompt: If the user is on an unsupported network, guide them to switch.

2.3. Borrow Section
My NFTs Tab:

Displays NFTs owned by the user (fetched from their connected wallet).

A "Story Protocol" badge or icon will indicate which NFTs are registered as Story IPs.

Filter/Sort options (by name, collection, potential collateral value).

For each NFT:

Image/Preview.

Name/ID.

Brief description.

Option to "Use as Collateral."

Create Loan Request Page:

Selected NFT Display: Shows details of the NFT chosen as collateral.

Appraisal Value (if available): Display estimated value of the NFT.

Loan Amount Input: Slider or input field for the desired loan amount (with LTV limits enforced).

Desired Loan Duration Input: Options for loan length (e.g., 30, 60, 90 days).

Estimated Interest Rate Display: Shows indicative interest rates based on market conditions or pool rates.

Summary: Clearly lists loan amount, collateral, duration, estimated fees, and repayment amount.

"List for Loan" / "Borrow from Pool" Button: Initiates the smart contract interaction to lock the NFT and create the loan request or borrow directly.

Active Borrows Tab (in My Dashboard):

Lists all active loans taken by the user.

For each loan:

Collateral NFT details.

Principal amount.

Interest accrued.

Remaining time / Maturity date.

"Repay Loan" button.

"Claim Royalties & Repay" button: This will be visible and active only if the collateral is a registered Story Protocol IP.

2.4. Lend Section
Available Collateral Tab / Marketplace:

Displays NFTs listed by borrowers seeking loans (peer-to-peer).

Filter/Sort options (by requested amount, duration, NFT type).

For each listed NFT:

NFT details (with Story Protocol badge if applicable).

Requested loan amount.

Desired duration.

Borrower's reputation/history (if implemented).

Option to "Fund Loan" / "Make Offer."

Fund Loan Page (Peer-to-Peer):

Displays details of the loan request.

Lender's Offer Input: Interest rate, specific terms if configurable.

"Offer Loan" Button: Initiates smart contract interaction to fund the loan and transfer funds to the borrower.

Liquidity Pools Tab (if applicable):

Displays available liquidity pools (e.g., Stablecoin Pool).

For each pool:

Total liquidity.

Current lending APY.

"Deposit" and "Withdraw" buttons.

Deposit Modal: Input for amount to deposit.

Withdraw Modal: Input for amount to withdraw.

Active Loans Funded Tab (in My Dashboard):

Lists all loans funded by the user.

For each loan:

Borrower details (anonymized ID).

Collateral NFT preview.

Principal lent.

Interest earned.

Maturity date.

Status (Active, Repaid, Defaulted).

2.5. My Dashboard Section
Summary View: Overview of user's total borrowed amount, total lent amount, active collateral, net APY.

My Collateral: NFTs currently locked as collateral.

My Borrows: Detailed list of active and past loans taken.

Option to repay active loans.

Option to use royalties for repayment on eligible loans.

My Loans (Lent): Detailed list of active and past loans funded (P2P).

My Pool Deposits: Details of liquidity provided to pools.

Notifications/Alerts: Loan maturity reminders, liquidation warnings, new offers.

2.6. NFT Details Page (General)
Accessible from various sections.

Full NFT Image/Media.

Comprehensive Metadata: Story IP details, creator, link to IP content.

Ownership History (if available).

Current Loan Status (if applicable): Whether it's collateral, available for loan, etc.

Valuation History (if available).

3. User Interaction Flows
3.1. Connecting Wallet
(As previously described)

3.2. Borrowing Process (Peer-to-Peer Example)
(As previously described)

3.3. Lending Process (Peer-to-Peer Example)
(As previously described)

3.4. Repaying a Loan (Standard)
(As previously described)

3.5. Repaying a Loan with Royalties (Story Protocol)
User navigates to "My Dashboard" -> "My Borrows."

For an active loan backed by a Story Protocol IP, the user clicks the "Claim Royalties & Repay" button.

A confirmation modal appears, explaining that the platform will attempt to claim available royalties from Story Protocol to pay down the loan. It may show an estimated available royalty amount if the data is accessible off-chain.

User confirms the action, which prompts a wallet transaction for the claimAndRepay function.

The frontend displays a loading/pending state.

Upon transaction confirmation, the UI updates:

A success notification shows the amount of royalties claimed and applied to the loan.

The loan's outstanding principal and interest are updated.

If the loan is fully paid off, its status changes to "Repaid", and the collateral is shown as returned.

3.6. Liquidation Process (Simplified)
(As previously described)

4. Smart Contract Interactions
The frontend will primarily interact with the following types of smart contract functions:

NFT Approval: approve() on the NFT contract before locking it as collateral.

Loan Management Contract (LendingProtocol.sol):

requestLoan(nftContractAddress, tokenId, loanAmount, duration)

cancelLoanRequest(requestId)

offerLoan(requestId, interestRate) (P2P)

acceptLoanOffer(offerId, nftContractAddress, nftTokenId)

repayLoan(loanId)

claimAndRepay(loanId): (Story Protocol Integration) A key function for royalty-backed repayments. It triggers the platform's RoyaltyManager to claim royalties from Story Protocol and apply them to the loan.

liquidateCollateral(loanId)

claimCollateral(loanId) (after successful liquidation by lender)

Royalty Manager Contract (RoyaltyManager.sol):

The frontend does not interact with this contract directly. It is called internally by the LendingProtocol when a user executes claimAndRepay. The RoyaltyManager is responsible for the claimRoyalty(ipId, currency) call to Story Protocol's RoyaltyModule.

Liquidity Pool Contract:

deposit(amount)

withdraw(shareAmount)

View Functions (for data display):

getLoanDetails(loanId)

getUserActiveLoans(userAddress)

getNftLoanStatus(nftContractAddress, tokenId): This would also return whether the NFT is a registered Story IP.

getPoolStats(poolId)

getOraclePrice(nftContractAddress, tokenId)

5. State Management
(As previously described)

6. Error Handling & Notifications
(As previously described, with additional notifications for royalty claim successes or failures.)
