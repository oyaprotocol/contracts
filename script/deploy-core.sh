#!/bin/bash

# ==============================================================================
# Oya Protocol Core Deployment Script
# ==============================================================================
# Deploys BundleTracker and VaultTracker contracts to any supported EVM chain
#
# Usage:
#   ./script/deploy-core.sh [chain_id] [options]
#
# Arguments:
#   chain_id    Chain ID to deploy to (1 = mainnet, 11155111 = sepolia, etc.)
#   options     Additional forge script options
#
# Environment Variables Required:
#   PRIVATE_KEY              Your deployer wallet private key
#   CHAIN_ID                 Chain ID (can be overridden by first argument)
#   [NETWORK]_RPC_URL        RPC URL for the target network
#   [optional] ESCALATION_MANAGER    Address for escalation manager
#   [optional] CREATE_INITIAL_VAULT Create initial vault (1 = yes, 0 = no)
#   [optional] INITIAL_VAULT_CONTROLLER Address for initial vault controller
#
# Examples:
#   ./script/deploy-core.sh 1                    # Deploy to Ethereum mainnet
#   ./script/deploy-core.sh 11155111             # Deploy to Sepolia testnet
#   ./script/deploy-core.sh 137 --verify       # Deploy to Polygon with verification
#
# Security Notes:
# - Never commit your .env file with private keys
# - Use a dedicated deployment wallet with limited funds
# - Verify all contract addresses before proceeding

set -e  # Exit on any error

# ==============================================================================
# Configuration and Setup
# ==============================================================================

# Script metadata
SCRIPT_NAME="deploy-core.sh"
SCRIPT_VERSION="1.0.0"
SUPPORTED_NETWORKS="1,11155111,42161,421614,8453,84532"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Supported networks mapping
declare -A NETWORK_NAMES=(
    [1]="ethereum-mainnet"
    [11155111]="ethereum-sepolia"
    [137]="polygon-mainnet"
    [80002]="polygon-testnet"
    [8453]="base"
    [84532]="base-sepolia"
)

declare -A NETWORK_RPC_VARS=(
    [1]="MAINNET_RPC_URL"
    [11155111]="SEPOLIA_RPC_URL"
    [137]="POLYGON_MAINNET_RPC_URL"
    [80002]="POLYGON_TESTNET_RPC_URL"
    [8453]="BASE_RPC_URL"
    [84532]="BASE_SEPOLIA_RPC_URL"
)

# ==============================================================================
# Utility Functions
# ==============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "================================================================="
    echo "             Oya Protocol Core Deployment Script"
    echo "================================================================="
    echo -e "${NC}"
    echo "Version: ${SCRIPT_VERSION}"
    echo "Script: ${SCRIPT_NAME}"
    echo "Supported Networks: ${SUPPORTED_NETWORKS}"
    echo ""
}

print_usage() {
    echo "Usage: ${SCRIPT_NAME} [chain_id] [options]"
    echo ""
    echo "Arguments:"
    echo "  chain_id    Chain ID to deploy to (default: from CHAIN_ID env var)"
    echo "  options     Additional forge script options"
    echo ""
    echo "Environment Variables Required:"
    echo "  PRIVATE_KEY              Your deployer wallet private key"
    echo "  CHAIN_ID                 Chain ID (can be overridden by argument)"
    echo "  [NETWORK]_RPC_URL        RPC URL for the target network"
    echo ""
    echo "Optional Environment Variables:"
    echo "  ESCALATION_MANAGER       Address for escalation manager"
    echo "  CREATE_INITIAL_VAULT     Create initial vault (1 = yes, 0 = no)"
    echo "  INITIAL_VAULT_CONTROLLER Address for initial vault controller"
    echo ""
    echo "Examples:"
    echo "  ${SCRIPT_NAME} 1                    # Deploy to Ethereum mainnet"
    echo "  ${SCRIPT_NAME} 11155111             # Deploy to Sepolia testnet"
    echo "  ${SCRIPT_NAME} 137 --verify       # Deploy to Polygon with verification"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==============================================================================
# Validation Functions
# ==============================================================================

validate_environment() {
    log_info "Validating environment configuration..."

    # Check for required environment variables
    if [[ -z "${PRIVATE_KEY}" ]]; then
        log_error "PRIVATE_KEY environment variable is required"
        log_info "Add your deployer wallet private key to your .env file"
        exit 1
    fi

    if [[ -z "${CHAIN_ID}" ]] && [[ -z "$1" ]]; then
        log_error "CHAIN_ID environment variable is required"
        log_info "Add CHAIN_ID=1 to your .env file or pass as first argument"
        exit 1
    fi

    # Use argument if provided, otherwise use environment variable
    TARGET_CHAIN_ID=${1:-${CHAIN_ID}}

    # Validate chain ID is supported
    if [[ ! ",${SUPPORTED_NETWORKS}," =~ ",${TARGET_CHAIN_ID}," ]]; then
        log_error "Unsupported chain ID: ${TARGET_CHAIN_ID}"
        log_info "Supported chain IDs: ${SUPPORTED_NETWORKS}"
        log_info "1 = Ethereum Mainnet"
        log_info "11155111 = Ethereum Sepolia"
        log_info "137 = Polygon Mainnet"
        log_info "80002 = Polygon Amoy Testnet"
        log_info "8453 = Base"
        log_info "84532 = Base Sepolia"
        exit 1
    fi

    # Check for RPC URL
    RPC_VAR=${NETWORK_RPC_VARS[$TARGET_CHAIN_ID]}
    RPC_URL=${!RPC_VAR}

    if [[ -z "${RPC_URL}" ]]; then
        log_error "RPC URL not configured for chain ID ${TARGET_CHAIN_ID}"
        log_info "Add ${RPC_VAR}=your_rpc_url_here to your .env file"
        exit 1
    fi

    log_success "Environment validation passed"
    log_info "Target Network: ${NETWORK_NAMES[$TARGET_CHAIN_ID]} (${TARGET_CHAIN_ID})"
    log_info "RPC URL: ${RPC_URL}"

    # Export validated variables
    export CHAIN_ID=${TARGET_CHAIN_ID}
    export RPC_URL
}

validate_deployment() {
    log_info "Running pre-deployment validation..."

    # Run the validation function in the deployment script
    forge script script/DeployCore.s.sol:DeployCore \
        --rpc-url "${RPC_URL}" \
        --private-key "${PRIVATE_KEY}" \
        --sig "validateEnvironment()"

    log_success "Pre-deployment validation passed"
}

# ==============================================================================
# Main Deployment Function
# ==============================================================================

deploy_contracts() {
    local chain_id=$1
    shift
    local additional_args=("$@")

    log_info "Starting deployment to ${NETWORK_NAMES[$chain_id]}..."

    # Prepare forge command
    local forge_args=(
        "script"
        "script/DeployCore.s.sol:DeployCore"
        "--rpc-url" "${RPC_URL}"
        "--private-key" "${PRIVATE_KEY}"
        "--broadcast"
    )

    # Add additional arguments if provided
    if [[ ${#additional_args[@]} -gt 0 ]]; then
        forge_args+=("${additional_args[@]}")
    fi

    log_info "Executing deployment command..."
    log_info "Command: forge ${forge_args[*]}"

    # Execute deployment
    forge "${forge_args[@]}"

    log_success "Deployment completed successfully!"
}

# ==============================================================================
# Main Script Execution
# ==============================================================================

main() {
    print_banner

    # Check if help is requested
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        print_usage
        exit 0
    fi

    # Validate environment and arguments
    validate_environment "$@"

    # Run pre-deployment validation
    validate_deployment

    # Parse additional arguments
    local chain_id=${CHAIN_ID}
    local additional_args=("${@:2}")

    # Show deployment summary
    echo ""
    log_info "Deployment Summary:"
    log_info "  Network: ${NETWORK_NAMES[$chain_id]}"
    log_info "  Chain ID: ${chain_id}"
    log_info "  Deployer: ${DEPLOYER_ADDRESS:-"Not set (check .env)"}"
    log_info "  RPC: ${RPC_URL}"
    log_info "  Contracts: BundleTracker, VaultTracker"

    if [[ ${#additional_args[@]} -gt 0 ]]; then
        log_info "  Additional options: ${additional_args[*]}"
    fi

    # Show optional configurations
    if [[ -n "${ESCALATION_MANAGER}" ]] && [[ "${ESCALATION_MANAGER}" != "0x0000000000000000000000000000000000000000" ]]; then
        log_info "  Escalation Manager: ${ESCALATION_MANAGER}"
    fi

    if [[ "${CREATE_INITIAL_VAULT:-0}" == "1" ]]; then
        log_info "  Initial Vault: Will be created"
        log_info "  Vault Controller: ${INITIAL_VAULT_CONTROLLER:-"Deployer address"}"
    fi

    echo ""
    read -p "Proceed with deployment? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    # Execute deployment
    deploy_contracts "${chain_id}" "${additional_args[@]}"

    # Show post-deployment instructions
    echo ""
    log_success "🎉 Deployment completed successfully!"
    echo ""
    log_info "Next steps:"
    log_info "1. Verify contract addresses on the block explorer"
    log_info "2. Test the contracts using the deployed addresses"
    log_info "3. Save the deployment addresses for your frontend/integration"
    log_info "4. Consider running tests against the deployed contracts"
    echo ""
    log_info "Useful commands:"
    log_info "  # Test the deployment:"
    log_info "  forge test --fork-url \${RPC_URL}"
    log_info ""
    log_info "  # View contracts on explorer:"
    echo -e "  ${BLUE}https://etherscan.io/address/[CONTRACT_ADDRESS]${NC}"
    echo ""
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Handle script being sourced vs executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
