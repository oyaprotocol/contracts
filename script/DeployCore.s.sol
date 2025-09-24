// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BundleTracker} from "../src/implementation/BundleTracker.sol";
import {VaultTracker} from "../src/implementation/VaultTracker.sol";

/**
 * @title DeployCore
 * @notice Deployment script for Oya Protocol core contracts (BundleTracker and VaultTracker)
 * @dev Supports multi-chain deployment with network-specific configurations
 *
 * Deployment Flow:
 * 1. Validates environment and network configuration
 * 2. Reads protocol rules from rules/ directory
 * 3. Deploys BundleTracker with UMA integration
 * 4. Deploys VaultTracker with UMA integration
 * 5. Configures initial settings (escalation manager, initial vault)
 * 6. Logs deployment summary for verification
 *
 * @custom:security This script uses environment variables for sensitive data
 * @custom:security All private keys and API keys are handled externally
 */
contract DeployCore is Script {
    // Deployed contract addresses
    BundleTracker public bundleTracker;
    VaultTracker public vaultTracker;

    // Network configuration structure
    struct NetworkConfig {
        string name;                    // Network name for logging
        address umaFinder;             // UMA Finder contract address
        address collateralToken;       // Collateral token (USDC, WETH, etc.)
        uint256 defaultBondAmount;     // Base bond amount for proposals
        bytes32 defaultIdentifier;     // UMA identifier for validation
        uint64 defaultLiveness;        // Challenge window in seconds
    }

    // Protocol rules cache
    string private cachedRules;

    /**
     * @notice Gets network-specific configuration based on chain ID
     * @param chainId The chain ID to get configuration for
     * @return NetworkConfig for the specified chain
     * @dev Add new networks here as needed
     */
    function getNetworkConfig(uint256 chainId) internal pure returns (NetworkConfig memory) {
        // Ethereum Mainnet
        if (chainId == 1) {
            return NetworkConfig({
                name: "ethereum-mainnet",
                umaFinder: 0x40f941E48A552bF496B154Af6bf55725f18D77c3,
                collateralToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
                defaultBondAmount: 100e6, // 100 USDC
                defaultIdentifier: keccak256("ASSERT_TRUTH"),
                defaultLiveness: 7200 // 2 hours
            });
        }
        // Ethereum Sepolia Testnet
        else if (chainId == 11155111) {
            return NetworkConfig({
                name: "ethereum-sepolia",
                umaFinder: 0x1aa7392D6C1c5d7C0C5f6b0d3A7E4E8E3b0e4d0d, // UMA testnet finder
                collateralToken: 0x6f14C02Fc1F68422c6f4aE8B5c7A7B1B8B8B0B5B, // Test USDC
                defaultBondAmount: 10e6, // 10 USDC
                defaultLiveness: 3600, // 1 hour
                defaultIdentifier: keccak256("ASSERT_TRUTH")
            });
        }
        // Arbitrum One
        else if (chainId == 42161) {
            return NetworkConfig({
                name: "arbitrum-one",
                umaFinder: 0x1234567890abcdef1234567890abcdef12345678, // TODO: Add actual UMA finder on Arbitrum
                collateralToken: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // USDC.e on Arbitrum
                defaultBondAmount: 100e6, // 100 USDC
                defaultLiveness: 7200, // 2 hours
                defaultIdentifier: keccak256("ASSERT_TRUTH")
            });
        }
        // Arbitrum Sepolia
        else if (chainId == 421614) {
            return NetworkConfig({
                name: "arbitrum-sepolia",
                umaFinder: 0xabcdef1234567890abcdef1234567890abcdef12, // TODO: Add actual UMA finder on Arbitrum Sepolia
                collateralToken: 0x6f14C02Fc1F68422c6f4aE8B5c7A7B1B8B8B0B5B, // Test USDC on Arbitrum Sepolia
                defaultBondAmount: 10e6, // 10 USDC
                defaultLiveness: 3600, // 1 hour
                defaultIdentifier: keccak256("ASSERT_TRUTH")
            });
        }
        // Base
        else if (chainId == 8453) {
            return NetworkConfig({
                name: "base",
                umaFinder: 0x1234567890abcdef1234567890abcdef12345678, // TODO: Add actual UMA finder on Base
                collateralToken: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // USDC on Base
                defaultBondAmount: 100e6, // 100 USDC
                defaultLiveness: 7200, // 2 hours
                defaultIdentifier: keccak256("ASSERT_TRUTH")
            });
        }
        // Base Sepolia
        else if (chainId == 84532) {
            return NetworkConfig({
                name: "base-sepolia",
                umaFinder: 0xabcdef1234567890abcdef1234567890abcdef12, // TODO: Add actual UMA finder on Base Sepolia
                collateralToken: 0x6f14C02Fc1F68422c6f4aE8B5c7A7B1B8B8B0B5B, // Test USDC on Base Sepolia
                defaultBondAmount: 10e6, // 10 USDC
                defaultLiveness: 3600, // 1 hour
                defaultIdentifier: keccak256("ASSERT_TRUTH")
            });
        }
        else {
            revert(string.concat("Unsupported network with chain ID: ", vm.toString(chainId)));
        }
    }

    /**
     * @notice Reads protocol rules from the rules/ directory
     * @return Protocol rules as string
     * @dev Reads from rules/global.txt only
     * @custom:security Validates that rules are not empty
     */
    function getProtocolRules() internal view returns (string memory) {
        if (bytes(cachedRules).length > 0) {
            return cachedRules;
        }

        // Read protocol rules from global.txt
        try vm.readFile("rules/global.txt") returns (string memory rules) {
            if (bytes(rules).length > 0) {
                cachedRules = rules;
                return rules;
            }
        } catch {
            // Fall through to revert
        }

        revert("Protocol rules not found. Please ensure rules/global.txt contains valid rule files.");
    }

    /**
     * @notice Main deployment function
     * @dev Deploys BundleTracker and VaultTracker with proper configuration
     * @custom:security Uses environment variables for sensitive configuration
     */
    function run() public {
        // Get deployment configuration
        uint256 chainId = vm.envUint("CHAIN_ID");
        NetworkConfig memory config = getNetworkConfig(chainId);
        string memory rules = getProtocolRules();

        // Log deployment header
        console.log("=== Oya Protocol Core Deployment ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", chainId);
        console.log("Deployer:", msg.sender);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);
        console.log("=====================================");

        // Validate configuration
        require(config.umaFinder != address(0), "UMA Finder address cannot be zero");
        require(config.collateralToken != address(0), "Collateral token address cannot be zero");
        require(config.defaultBondAmount > 0, "Bond amount must be greater than zero");
        require(config.defaultLiveness > 0, "Liveness must be greater than zero");
        require(bytes(rules).length > 0, "Protocol rules cannot be empty");

        console.log("Protocol Rules Preview:", bytes(rules).length, "characters");
        console.log("Collateral Token:", config.collateralToken);
        console.log("Bond Amount:", config.defaultBondAmount);
        console.log("Liveness Period:", config.defaultLiveness, "seconds");
        console.log("=====================================");

        // Start deployment broadcast
        vm.startBroadcast();

        // Deploy BundleTracker
        console.log("\n1. Deploying BundleTracker...");
        bundleTracker = new BundleTracker(
            config.umaFinder,
            config.collateralToken,
            config.defaultBondAmount,
            rules,
            config.defaultIdentifier,
            config.defaultLiveness
        );
        console.log("✅ BundleTracker deployed at:", address(bundleTracker));

        // Deploy VaultTracker
        console.log("\n2. Deploying VaultTracker...");
        vaultTracker = new VaultTracker(
            config.umaFinder,
            config.collateralToken,
            config.defaultBondAmount,
            rules,
            config.defaultIdentifier,
            config.defaultLiveness
        );
        console.log("✅ VaultTracker deployed at:", address(vaultTracker));

        // Optional: Set escalation manager if provided
        address escalationManager = vm.envOr("ESCALATION_MANAGER", address(0));
        if (escalationManager != address(0)) {
            console.log("\n3. Setting escalation manager...");
            if (address(bundleTracker).code.length > 0) {
                bundleTracker.setEscalationManager(escalationManager);
                console.log("✅ BundleTracker escalation manager set to:", escalationManager);
            }
            if (address(vaultTracker).code.length > 0) {
                vaultTracker.setEscalationManager(escalationManager);
                console.log("✅ VaultTracker escalation manager set to:", escalationManager);
            }
        }

        // Optional: Create initial vault if specified
        uint256 initialVaultId = vm.envOr("CREATE_INITIAL_VAULT", uint256(0));
        if (initialVaultId > 0) {
            console.log("\n4. Creating initial vault...");
            address vaultController = vm.envOr("INITIAL_VAULT_CONTROLLER", msg.sender);
            vaultTracker.createVault(vaultController);
            console.log("✅ Initial vault created with ID:", initialVaultId);
            console.log("✅ Vault controller set to:", vaultController);
        }

        vm.stopBroadcast();

        // Log deployment summary
        logDeploymentSummary(config);

        console.log("\n=== Core Deployment Complete ===");
        console.log("BundleTracker:", address(bundleTracker));
        console.log("VaultTracker:", address(vaultTracker));
        console.log("=================================");
    }

    /**
     * @notice Logs comprehensive deployment summary
     * @param config Network configuration used for deployment
     */
    function logDeploymentSummary(NetworkConfig memory config) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", block.chainid);
        console.log("Deployed By:", msg.sender);
        console.log("Deployment Time:", block.timestamp);

        console.log("\n--- Contract Addresses ---");
        console.log("BundleTracker:", address(bundleTracker));
        console.log("VaultTracker:", address(vaultTracker));

        console.log("\n--- Network Configuration ---");
        console.log("UMA Finder:", config.umaFinder);
        console.log("Collateral Token:", config.collateralToken);
        console.log("Bond Amount:", config.defaultBondAmount);
        console.log("Liveness Period:", config.defaultLiveness, "seconds");
        console.log("Identifier:", vm.toString(config.defaultIdentifier));

        console.log("\n--- Protocol Configuration ---");
        console.log("Rules Length:", bytes(cachedRules).length, "characters");

        // Log optional configurations
        address escalationManager = vm.envOr("ESCALATION_MANAGER", address(0));
        if (escalationManager != address(0)) {
            console.log("Escalation Manager:", escalationManager);
        }

        uint256 initialVaultId = vm.envOr("CREATE_INITIAL_VAULT", uint256(0));
        if (initialVaultId > 0) {
            console.log("Initial Vault Created:", true);
            console.log("Initial Vault Controller:", vm.envOr("INITIAL_VAULT_CONTROLLER", msg.sender));
        }

        console.log("==========================");
    }

    /**
     * @notice Validates that the deployment environment is correct
     * @dev Can be called externally for pre-deployment checks
     */
    function validateEnvironment() external view {
        uint256 chainId = vm.envUint("CHAIN_ID");
        NetworkConfig memory config = getNetworkConfig(chainId);

        require(config.umaFinder != address(0), "Invalid UMA Finder address");
        require(config.collateralToken != address(0), "Invalid collateral token address");
        require(config.defaultBondAmount > 0, "Invalid bond amount");
        require(config.defaultLiveness > 0, "Invalid liveness period");

        string memory rules = getProtocolRules();
        require(bytes(rules).length > 0, "Protocol rules not found");

        console.log("✅ Environment validation passed for network:", config.name);
    }
}
