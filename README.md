# Oya Contracts

`oyaprotocol/contracts` is the smart contract suite for **Oya**, a natural language protocol. Assets deposited into these smart contracts on existing EVM chains can be used on the Oya natural language protocol. Bundles of transactions in the Oya protocol are verified using [UMA’s Optimistic Oracle](https://umaproject.org/), ensuring decentralized, permissionless validation of bundle data and proposals.

> _“Oya is a protocol that interprets natural language rules and transactions, enabling a new paradigm for decentralized applications, ideal for both humans and AI.”_

**WARNING: These contracts are unaudited and experimental. They should not be used in production. No official Oya Protocol contracts have been deployed on mainnet, nor any official Oya token.**

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [OptimisticProposer](#optimisticproposer)
  - [BundleTracker](#bundletracker)
  - [VaultTracker](#vaulttracker)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Deployment](#deployment)
- [Usage](#usage)
- [Testing](#testing)
- [Contributing](#contributing)
- [Contact](#contact)

## Overview

This repository contains the Solidity smart contracts that enable a natural language protocol by integrating with UMA’s Optimistic Oracle for dispute resolution. The main components include:

- **OptimisticProposer:** Provides a reusable framework for proposing and verifying onchain transactions or proposals via UMA’s optimistic validation mechanism.
- **BundleTracker:** Handles the proposal of new bundles (with natural language-based bundle data) and integrates with UMA’s Optimistic Oracle to verify the proposals.
- **VaultTracker:** Manages vaults that control assets deposited into the smart contracts. It enables vault creation, management (controllers, guardians), and protocol-level freeze/unfreeze functionality.

Together, these contracts allow any ERC20 or ERC721 assets on existing EVM chains to be bridged to the Oya protocol and governed by natural language rules.

## Architecture

### OptimisticProposer

The `OptimisticProposer` contract is a core component that abstracts the interaction with UMA’s Optimistic Oracle. It provides:
- A mechanism to propose transactions or data assertions.
- Bond management using ERC20 collateral.
- Support for dispute resolution callbacks (e.g., automatic deletion of disputed proposals).
- Functions to set global rules, liveness periods, and identifiers used to validate proposals.

This contract is inherited by both the `BundleTracker` and `VaultTracker`, ensuring consistent behavior when proposing and validating assertions.

### BundleTracker

The `BundleTracker` contract is responsible for tracking new bundles on the Oya natural language protocol. Key features include:
- **Bundle Proposal:** Nodes can propose new bundles by submitting natural language bundle data.
- **Optimistic Verification:** Each bundle proposal triggers an assertion via UMA’s Optimistic Oracle. If the assertion is validated, the bundle is finalized.
- **Event Emission:** Emits events such as `BundleProposed` and `BundleTrackerDeployed` for offchain monitoring and integration.

### VaultTracker

The `VaultTracker` contract manages vaults that hold assets bridged to the Oya protocol. Its features include:
- **Vault Management:** Creation and administration of vaults (e.g., setting controllers, guardians, and vault-specific rules).
- **Protocol Controls:** Functions to freeze or unfreeze individual vaults or the entire protocol (useful for emergency shutdowns).
- **Proposal Execution:** Inherits the OptimisticProposer functionality to propose and execute transactions affecting vault states.
- **Inheritance from Safe:** Inherits from the [Safe](https://safe.global/) `Executor` contract to allow secure execution of proposals.

## Getting Started

### Prerequisites

- **Node.js** – for managing JavaScript dependencies.
- **Foundry** – our Solidity development framework. You can install Foundry by following the instructions at [foundry.rs](https://book.getfoundry.sh/).
- **Solidity Compiler (v0.8.6 or later)** – ensure your environment uses a compatible compiler version.

### Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/oyaprotocol/contracts.git
cd contracts
forge install
```

Make sure to configure your Foundry settings (such as network endpoints and private keys) according to the [Foundry Book](https://book.getfoundry.sh/).

## Deployment

The contracts are designed to be deployed on EVM-compatible chains. Deployment involves:

1. **Configuring the Deployment Parameters:**
   - Set the UMA Finder address.
   - Specify the ERC20 collateral token and bond amounts.
   - Define the global rules.
   - Set the UMA identifier for assertions.
   - Choose the liveness period for assertions.

2. **Deploying Contracts:**
   - Deploy the `OptimisticProposer`-based contracts (e.g., `BundleTracker` and `VaultTracker`).
   - Ensure the UMA Optimistic Oracle’s address is correctly synced via the `_sync()` functions.

Example deployment using Foundry:

```bash
# Deploy BundleTracker
RULES="$(cat ./rules/global.txt)"
forge create \
  --etherscan-api-key <etherscan-api-key> --verify \
  --constructor-args <finderAddress> <collateralAddress> <bondAmount> "<rules>" <identifier> <liveness> \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  src/implementation/BundleTracker.sol:BundleTracker

# Deploy VaultTracker
RULES="$(cat ./rules/global.txt)"
forge create \
  --etherscan-api-key <etherscan-api-key> --verify \
  --constructor-args <finderAddress> <collateralAddress> <bondAmount> "$<rules>$" <identifier> <liveness> \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  src/implementation/VaultTracker.sol:VaultTracker
```

Replace the constructor arguments, Etherscan API key, RPC URL, and private key with your actual deployment parameters.

## Usage

### Testnet Contracts
Sample `BundleTracker` and `VaultTracker` contracts have been deployed on Sepolia Testnet for testing. The contract addresses are below. 

*Disclaimer: These contracts are for testing only, verifier nodes are not activeyl checking proposals sent to the contracts.*

- BundleTracker: `0xF96cd74e7EEcb93a773105269b7ef5187db30aef`
- VaultTracker: `0xD08F6cc38DCa6278f0bD9aB167E9E0d82855354A`


### Proposing a Bundle

Users interact with the `BundleTracker` contract by calling the `proposeBundle` function with their bundle data written in natural language. The data structure is described in the protocol's global rules. The process is as follows:

- The contract records the bundle proposal along with the current timestamp and the proposer's address.
- UMA’s Optimistic Oracle is invoked to assert the truthfulness of the bundle proposal.
- A `BundleProposed` event is emitted containing the timestamp, proposer address, and bundle data.
- If the assertion is validated (i.e., no disputes are raised within the liveness period), the bundle is finalized.

### Managing Vaults

The `VaultTracker` contract provides methods to manage vaults, which hold the bridged assets used on the Oya protocol. Key functions include:

- **Creating Vaults:** Use `createVault(controllerAddress)` to initialize a new vault with a specified controller.
- **Setting Vault Rules:** Vault-specific rules can be defined or updated using the `setVaultRules` function.
- **Managing Controllers and Guardians:** 
  - `setController` assigns or changes the controller for a vault.
  - `setGuardian` allows designated accounts to act as guardians.
  - `removeGuardian` (requires proposal execution) removes a guardian from a vault.
- **Executing Proposals:** Once a proposal is verified by the Optimistic Oracle, the `executeProposal` function executes a series of transactions that may update vault states or enforce tokenholder governance decisions.

### Interacting with UMA’s Optimistic Oracle

Both the `BundleTracker` and `VaultTracker` rely on UMA’s Optimistic Oracle for dispute resolution:

- After a proposal is asserted, if no disputes arise during the liveness period, the proposal is considered valid and can be executed.
- If a dispute occurs, the relevant callbacks (such as `assertionDisputedCallback` or `assertionResolvedCallback`) handle the resolution by deleting or finalizing the proposal.

For more details on interacting with UMA’s Optimistic Oracle, please refer to [UMA’s documentation](https://docs.umaproject.org/).

## Testing

Our tests are located in the `./test/` directory, with the following files:
- `BundleTracker.t.sol`
- `OptimisticProposer.t.sol`
- `VaultTracker.t.sol`

To run the tests, follow these steps:

1. **Configure Your Test Environment:**
   - Ensure your Foundry configuration (`foundry.toml`) is set up correctly for your local or public test network.
   - Update any necessary network parameters or environment variables.

2. **Run the Tests:**
   - Execute the tests using Foundry's built-in test runner:

```bash
forge test -vv
```

These tests cover key functionalities, including:

* Bundle proposal and finalization in `BundleTracker`.
* Transaction proposals and execution in `OptimisticProposer`.
* Vault management, including freezing/unfreezing and role assignments in `VaultTracker`.

## Contributing

Contributions are welcome! If you would like to contribute, please follow these steps:

1. **Fork the Repository:** Create a personal fork of the project.
2. **Create a Feature Branch:** Develop your feature or bug fix in a dedicated branch.
3. **Write Tests:** Ensure your changes are covered by tests.
4. **Submit a Pull Request:** Provide a clear description of your changes, linking to any relevant issues.

Please ensure that your code adheres to the project's style guidelines and passes all tests before submitting your pull request.

## Contact

For questions or support, please open an issue in this repository.

*Happy building on the Oya Protocol – where natural language + blockchain = better together!*
