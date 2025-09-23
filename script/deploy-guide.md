# Oya Protocol Deployment Guide

This guide provides step-by-step instructions for deploying the Oya Protocol contracts to any supported EVM chain.

## Quick Start

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env with your configuration

# 2. Deploy Oya token (once)
./script/deploy-oya.sh $MAINNET_RPC_URL

# 3. Deploy core contracts (per chain)
./script/deploy-core.sh 1                    # Ethereum mainnet
./script/deploy-core.sh 11155111             # Sepolia testnet
./script/deploy-core.sh 42161                # Arbitrum One
```

## Prerequisites

### Required Software
- **Foundry** (latest version)
- **Git**
- **Bash** (Linux/macOS) or **Git Bash** (Windows)

### Required Accounts
- **Deployer Wallet**: Wallet with sufficient funds for gas fees
- **Block Explorer API Keys**: For contract verification (optional but recommended)

### Get API Keys
- **Etherscan**: https://etherscan.io/apis
- **ArbitrumScan**: https://arbiscan.io/apis
- **BaseScan**: https://basescan.org/apis

## Environment Setup

### 1. Configure Environment Variables

Copy the template and configure your settings:

```bash
cp .env.example .env
# Edit .env with your actual values
```

**Required Variables:**
```bash
# Your deployment wallet
PRIVATE_KEY=0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
DEPLOYER_ADDRESS=0x1234567890123456789012345678901234567890

# Target chain ID (1 = mainnet, 11155111 = sepolia, etc.)
CHAIN_ID=1

# RPC endpoints for supported networks
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_ONE_RPC_URL=https://arb1.arbitrum.io/rpc
ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org

# Block explorer API keys (for verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
ARBITRUMSCAN_API_KEY=your_arbitrumscan_api_key
BASESCAN_API_KEY=your_basescan_api_key
```

**Optional Variables:**
```bash
# Protocol configuration
ESCALATION_MANAGER=0x0000000000000000000000000000000000000000
CREATE_INITIAL_VAULT=1
INITIAL_VAULT_CONTROLLER=0x1234567890123456789012345678901234567890
```

### 2. Supported Networks

| Network | Chain ID | Status | RPC Variable |
|---------|----------|---------|--------------|
| Ethereum Mainnet | 1 | ✅ Active | `MAINNET_RPC_URL` |
| Ethereum Sepolia | 11155111 | ✅ Active | `SEPOLIA_RPC_URL` |
| Arbitrum One | 42161 | ✅ Active | `ARBITRUM_ONE_RPC_URL` |
| Arbitrum Sepolia | 421614 | ✅ Active | `ARBITRUM_SEPOLIA_RPC_URL` |
| Base | 8453 | ✅ Active | `BASE_RPC_URL` |
| Base Sepolia | 84532 | ✅ Active | `BASE_SEPOLIA_RPC_URL` |

## Oya Token Deployment

Deploy the Oya ERC20 token contract. **Deploy once and use across all chains.**

```bash
# Deploy to mainnet (recommended)
./script/deploy-oya.sh $MAINNET_RPC_URL

# Or deploy to testnet for testing
./script/deploy-oya.sh $SEPOLIA_RPC_URL

# With verification
./script/deploy-oya.sh $MAINNET_RPC_URL --verify
```

**What happens:**
- ✅ Deploys Oya token with 1 billion initial supply
- ✅ Mints all tokens to the deployer address
- ✅ Token owner can mint additional tokens later
- ✅ Contract is verified on block explorer (if `--verify` used)

## Core Protocol Deployment

Deploy BundleTracker and VaultTracker contracts to each target chain.

```bash
# Deploy to Ethereum mainnet
./script/deploy-core.sh 1

# Deploy to Sepolia testnet
./script/deploy-core.sh 11155111

# Deploy to Arbitrum One
./script/deploy-core.sh 42161

# Deploy to Arbitrum Sepolia
./script/deploy-core.sh 421614

# Deploy to Base
./script/deploy-core.sh 8453

# With verification
./script/deploy-core.sh 1 --verify
```

**What happens:**
- ✅ Deploys BundleTracker with UMA integration
- ✅ Deploys VaultTracker with UMA integration
- ✅ Configures protocol rules from `rules/` directory
- ✅ Sets up collateral tokens and bond amounts
- ✅ Contracts are verified on block explorer (if `--verify` used)

## Verification

### Automatic Verification
Add `--verify` flag to deployment commands:
```bash
./script/deploy-oya.sh $MAINNET_RPC_URL --verify
./script/deploy-core.sh 1 --verify
```

### Manual Verification
```bash
# Verify specific contract
forge verify-contract [CONTRACT_ADDRESS] src/implementation/[ContractName].sol:[ContractName] --etherscan-api-key [API_KEY]
```

### Check Verification Status
Visit the block explorer and search for your contract address.

