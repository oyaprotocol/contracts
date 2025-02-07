# Oya Onchain

**Oya Onchain** is the smart contract suite for **Oya**, a natural language blockchain protocol. Assets deposited into these smart contracts on existing EVM chains can be used on the Oya natural language blockchain. Blocks on the Oya chain are verified using [UMA’s Optimistic Oracle](https://umaproject.org/), ensuring decentralized, permissionless validation of block data and proposals.

> _“Oya is a blockchain that interprets natural language rules and transactions, enabling a new paradigm for decentralized applications, ideal for both humans and AI agents.”_

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
  - [OptimisticProposer](#optimisticproposer)
  - [BlockTracker](#blocktracker)
  - [VaultTracker](#vaulttracker)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Deployment](#deployment)
- [Usage](#usage)
- [Testing](#testing)
- [Contributing](#contributing)
- [Contact](#contact)

---

## Overview

The Oya Onchain repository contains the Solidity smart contracts that enable a natural language blockchain by integrating with UMA’s Optimistic Oracle for dispute resolution. The main components include:

- **OptimisticProposer:** Provides a reusable framework for proposing and verifying onchain transactions or proposals via UMA’s optimistic validation mechanism.
- **BlockTracker:** Handles the proposal of new blocks (with natural language-based block data) and integrates with UMA’s Optimistic Oracle to verify the proposals.
- **VaultTracker:** Manages vaults that control assets deposited into the smart contracts. It enables vault creation, management (controllers, guardians), and chain-level freeze/unfreeze functionality.

Together, these contracts allow any ERC20 or ERC721 assets on existing EVM chains to be bridged to the Oya blockchain and governed by natural language rules.

---

## Architecture

### OptimisticProposer

The `OptimisticProposer` contract is a core component that abstracts the interaction with UMA’s Optimistic Oracle. It provides:
- A mechanism to propose transactions or data assertions.
- Bond management using ERC20 collateral.
- Support for dispute resolution callbacks (e.g., automatic deletion of disputed proposals).
- Functions to set global rules, liveness periods, and identifiers used to validate proposals.

This contract is inherited by both the `BlockTracker` and `VaultTracker`, ensuring consistent behavior when proposing and validating assertions.

### BlockTracker

The `BlockTracker` contract is responsible for tracking new blocks on the Oya natural language blockchain. Key features include:
- **Block Proposal:** Nodes can propose new blocks by submitting natural language block data.
- **Optimistic Verification:** Each block proposal triggers an assertion via UMA’s Optimistic Oracle. If the assertion is validated, the block is finalized.
- **Event Emission:** Emits events such as `BlockProposed` and `BlockTrackerDeployed` for offchain monitoring and integration.

### VaultTracker

The `VaultTracker` contract manages vaults that hold assets bridged to the Oya blockchain. Its features include:
- **Vault Management:** Creation and administration of vaults (e.g., setting controllers, guardians, and vault-specific rules).
- **Chain Controls:** Functions to freeze or unfreeze individual vaults or the entire chain (useful for emergency shutdowns).
- **Proposal Execution:** Inherits the OptimisticProposer functionality to propose and execute transactions affecting vault states.
- **Inheritance from Safe:** Inherits from the [Safe](https://safe.global/) `Executor` contract to allow secure execution of proposals.

---

## Getting Started

### Prerequisites

- **Node.js** – for managing JavaScript dependencies.
- **Foundry** – our Solidity development framework. You can install Foundry by following the instructions at [foundry.rs](https://book.getfoundry.sh/).
- **Solidity Compiler (v0.8.6 or later)** – ensure your environment uses a compatible compiler version.

### Installation

Clone the repository and install dependencies:

```bash
git clone https://github.com/pemulis/oya-onchain.git
cd oya-onchain
forge install
```

Make sure to configure your Foundry settings (such as network endpoints and private keys) according to the [Foundry Book](https://book.getfoundry.sh/).

---

## Deployment

The contracts are designed to be deployed on EVM-compatible chains. Deployment involves:

1. **Configuring the Deployment Parameters:**
   - Set the UMA Finder address.
   - Specify the ERC20 collateral token and bond amounts.
   - Define the global rules.
   - Set the UMA identifier for assertions.
   - Choose the liveness period for assertions.

2. **Deploying Contracts:**
   - Deploy the `OptimisticProposer`-based contracts (e.g., `BlockTracker` and `VaultTracker`).
   - Ensure the UMA Optimistic Oracle’s address is correctly synced via the `_sync()` functions.

Example deployment using Foundry:

```bash
# Deploy BlockTracker
RULES="$(cat ./rules/global.txt)"
forge create \
  --etherscan-api-key <etherscan-api-key> --verify \
  --constructor-args <finderAddress> <collateralAddress> <bondAmount> "<rules>" <identifier> <liveness> \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key> \
  src/implementation/BlockTracker.sol:BlockTracker

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

---

## Usage

### Proposing a Block

Users interact with the `BlockTracker` contract by calling the `proposeBlock` function with their block data written in natural language. The data structure is described in the protocol's global rules. The process is as follows:

- The contract records the block proposal along with the current timestamp and the proposer's address.
- UMA’s Optimistic Oracle is invoked to assert the truthfulness of the block proposal.
- A `BlockProposed` event is emitted containing the timestamp, proposer address, and block data.
- If the assertion is validated (i.e., no disputes are raised within the liveness period), the block is finalized.

### Managing Vaults

The `VaultTracker` contract provides methods to manage vaults, which hold the bridged assets used on the Oya blockchain. Key functions include:

- **Creating Vaults:** Use `createVault(controllerAddress)` to initialize a new vault with a specified controller.
- **Setting Vault Rules:** Vault-specific rules can be defined or updated using the `setVaultRules` function.
- **Managing Controllers and Guardians:** 
  - `setController` assigns or changes the controller for a vault.
  - `setGuardian` allows designated accounts to act as guardians.
  - `removeGuardian` (requires proposal execution) removes a guardian from a vault.
- **Chain Controls:** 
  - `freezeVault` and `unfreezeVault` allow guardians to temporarily halt or resume operations for individual vaults.
  - `freezeChain` and `unfreezeChain` can be called by a designated role (the Crisis Action Team, or CAT) to temporarily freeze the entire chain in case of emergencies. The CAT is a multisignature wallet whose signatories are controlled by Oya tokenholder governance.
- **Executing Proposals:** Once a proposal is verified by the Optimistic Oracle, the `executeProposal` function executes a series of transactions that may update vault states or enforce tokenholder governance decisions.

### Interacting with UMA’s Optimistic Oracle

Both the `BlockTracker` and `VaultTracker` rely on UMA’s Optimistic Oracle for dispute resolution:

- After a proposal is asserted, if no disputes arise during the liveness period, the proposal is considered valid and can be executed.
- If a dispute occurs, the relevant callbacks (such as `assertionDisputedCallback` or `assertionResolvedCallback`) handle the resolution by deleting or finalizing the proposal.

For more details on interacting with UMA’s Optimistic Oracle, please refer to [UMA’s documentation](https://docs.umaproject.org/).

---

## Testing

Our tests are located in the `./test/` directory, with the following files:
- `BlockTracker.t.sol`
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

* Block proposal and finalization in `BlockTracker`.
* Transaction proposals and execution in `OptimisticProposer`.
* Vault management, including freezing/unfreezing and role assignments in `VaultTracker`.

---

## Contributing

Contributions are welcome! If you would like to contribute, please follow these steps:

1. **Fork the Repository:** Create a personal fork of the project.
2. **Create a Feature Branch:** Develop your feature or bug fix in a dedicated branch.
3. **Write Tests:** Ensure your changes are covered by tests.
4. **Submit a Pull Request:** Provide a clear description of your changes, linking to any relevant issues.

Please ensure that your code adheres to the project's style guidelines and passes all tests before submitting your pull request.

---

## Contact

For questions or support, please open an issue in this repository.

---

*Happy building on the Oya Protocol – where natural language + blockchain = better together!*