#!/bin/bash

# ==============================================================================
# Oya Token Deployment Script
# ==============================================================================
# Deploys the Oya ERC20 token contract to any supported EVM chain
#
# Usage:
#   ./script/deploy-oya.sh [rpc_url] [options]
#
# Arguments:
#   rpc_url     RPC URL for the target network (e.g., $MAINNET_RPC_URL)
#   options     Additional forge script options
#
# Environment Variables Required:
#   PRIVATE_KEY              Your deployer wallet private key
#   [optional] DEPLOYER_ADDRESS Deployer wallet address (for logging)
#
# Examples:
#   ./script/deploy-oya.sh $MAINNET_RPC_URL              # Deploy to Ethereum mainnet
#   ./script/deploy-oya.sh $SEPOLIA_RPC_URL              # Deploy to Sepolia testnet
#   ./script/deploy-oya.sh $POLYGON_MAINNET_RPC_URL --verify # Deploy to Polygon with verification
#
# Security Notes:
# - Never commit your .env file with private keys
# - Use a dedicated deployment wallet with limited funds
# - The Oya token will mint 1 billion tokens to the deployer address

set -e  # Exit on any error

# ==============================================================================
# Configuration and Setup
# ==============================================================================

# Script metadata
SCRIPT_NAME="deploy-oya.sh"
SCRIPT_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Utility Functions
# ==============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "================================================================="
    echo "                   Oya Token Deployment Script"
    echo "================================================================="
    echo -e "${NC}"
    echo "Version: ${SCRIPT_VERSION}"
    echo "Script: ${SCRIPT_NAME}"
    echo "Token Supply: 1,000,000,000 OYA"
    echo "Symbol: OYA"
    echo ""
}

print_usage() {
    echo "Usage: ${SCRIPT_NAME} [rpc_url] [options]"
    echo ""
    echo "Arguments:"
    echo "  rpc_url     RPC URL for the target network"
    echo "  options     Additional forge script options"
    echo ""
    echo "Environment Variables Required:"
    echo "  PRIVATE_KEY              Your deployer wallet private key"
    echo "  [optional] DEPLOYER_ADDRESS Deployer wallet address (for logging)"
    echo ""
    echo "Examples:"
    echo "  ${SCRIPT_NAME} \$MAINNET_RPC_URL              # Deploy to Ethereum mainnet"
    echo "  ${SCRIPT_NAME} \$SEPOLIA_RPC_URL              # Deploy to Sepolia testnet"
    echo "  ${SCRIPT_NAME} \$POLYGON_MAINNET_RPC_URL --verify # Deploy to Polygon with verification"
    echo ""
    echo "Note: The Oya token will mint 1 billion tokens to the deployer address"
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

    # Validate RPC URL is provided
    if [[ -z "$1" ]]; then
        log_error "RPC URL is required as the first argument"
        print_usage
        exit 1
    fi

    RPC_URL="$1"
    shift

    # Validate RPC URL format (basic check)
    if [[ ! "${RPC_URL}" =~ ^https?:// ]]; then
        log_error "Invalid RPC URL format: ${RPC_URL}"
        log_info "RPC URL should start with http:// or https://"
        exit 1
    fi

    log_success "Environment validation passed"
    log_info "Target RPC: ${RPC_URL}"
    log_info "Deployer: ${DEPLOYER_ADDRESS:-"Not specified (check .env)"}"
}

# ==============================================================================
# Main Deployment Function
# ==============================================================================

deploy_oya_token() {
    local rpc_url=$1
    shift
    local additional_args=("$@")

    log_info "Starting Oya token deployment..."

    # Prepare forge command
    local forge_args=(
        "script"
        "script/Oya.s.sol:OyaScript"
        "--rpc-url" "${rpc_url}"
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

    log_success "Oya token deployment completed successfully!"
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

    # Parse additional arguments
    local additional_args=("${@:2}")

    # Show deployment summary
    echo ""
    log_info "Deployment Summary:"
    log_info "  RPC URL: ${RPC_URL}"
    log_info "  Deployer: ${DEPLOYER_ADDRESS:-"Not specified"}"
    log_info "  Token: Oya (OYA)"
    log_info "  Initial Supply: 1,000,000,000 OYA"
    log_info "  Recipient: Deployer address (msg.sender)"

    if [[ ${#additional_args[@]} -gt 0 ]]; then
        log_info "  Additional options: ${additional_args[*]}"
    fi

    echo ""
    log_warning "⚠️  IMPORTANT SECURITY NOTICE:"
    log_warning "   The Oya token will mint 1 billion tokens to the deployer address"
    log_warning "   Make sure you trust the deployment wallet and RPC endpoint"
    log_warning "   Consider using a fresh wallet for token deployments"
    echo ""

    read -p "Proceed with Oya token deployment? (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    # Execute deployment
    deploy_oya_token "${RPC_URL}" "${additional_args[@]}"

    # Show post-deployment instructions
    echo ""
    log_success "🎉 Oya token deployment completed successfully!"
    echo ""
    log_info "Next steps:"
    log_info "1. Verify the token contract address on the block explorer"
    log_info "2. Check that the token has the correct name, symbol, and supply"
    log_info "3. Save the token address for use in your application"
    log_info "4. Consider transferring ownership to a multi-sig wallet"
    log_info "5. Test token transfers and approvals"
    echo ""
    log_info "Useful commands:"
    log_info "  # Check token balance:"
    log_info "  cast call [TOKEN_ADDRESS] \"balanceOf(address)\" [YOUR_ADDRESS] --rpc-url \${RPC_URL}"
    log_info ""
    log_info "  # Check token details:"
    log_info "  cast call [TOKEN_ADDRESS] \"name()\" --rpc-url \${RPC_URL}"
    log_info "  cast call [TOKEN_ADDRESS] \"symbol()\" --rpc-url \${RPC_URL}"
    log_info "  cast call [TOKEN_ADDRESS] \"totalSupply()\" --rpc-url \${RPC_URL}"
    echo ""
    log_info "  # View contract on explorer:"
    echo -e "  ${BLUE}https://etherscan.io/address/[TOKEN_ADDRESS]${NC}"
    echo ""
    log_warning "💡 Remember: The token owner can mint additional tokens at any time!"
    echo ""
}

# ==============================================================================
# Script Entry Point
# ==============================================================================

# Handle script being sourced vs executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
