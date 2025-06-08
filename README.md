# NFT Lending Protocol

This repository contains smart contracts for an NFT Lending Protocol, with a focus on royalty management for NFTs registered as IP assets.

## Overview

The protocol enables users to:

- Register NFTs as IP assets.
- Manage and claim royalties associated with these IP assets.
- Withdraw collected royalties in ERC20 tokens to designated recipients.

The contracts interact with mock implementations of Story Protocol's IP asset registry and royalty modules for testing purposes.

## Key Contracts

### RoyaltyManager

- Handles the claiming and withdrawal of royalties for registered IP assets.
- Integrates with external modules (mocked in tests) to collect royalties in ERC20 tokens.
- Maintains balances for each IP asset and currency.

### ERC721Mock

- A mock ERC721 contract used for testing NFT registration and royalty flows.

### MockIIPAssetRegistry

- A mock implementation of an IP asset registry, simulating Story Protocol's registry for tests.

### MockRoyaltyModule

- A mock royalty module that simulates royalty accrual and collection logic.

### ERC20Mock

- A mock ERC20 token used as the currency for royalty payments in tests.

## Testing

The protocol includes comprehensive tests (see `test/maneger/RoyaltyManager.t.sol`) that cover:

- Registering NFTs as IP assets.
- Claiming royalties for an IP asset.
- Withdrawing royalties to recipients.
- Handling edge cases such as insufficient balances.

## Usage

This repository is intended for research, development, and educational purposes. The contracts are not audited for production use.

---
