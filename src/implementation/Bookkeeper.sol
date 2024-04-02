pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Bookkeeper
/// @dev Implements transaction bundling and settlement functionality for the Oya network.
/// Allows for the registration and management of bundlers, and the proposal, finalization, and 
/// cancellation of transaction bundles.
contract Bookkeeper is BookkeeperInterface, Ownable {
    /// @notice Mapping of proposal block timestamps to bytes32 pointers to the bundle data.
    mapping(uint256 => bytes32) public bundles;

    /// @notice The proposal timestamp of the most recently finalized bundle.
    uint256 public lastFinalizedBundle;

    /// @notice Addresses of approved bundlers.
    mapping(address => bool) public bundlers;

    /// @notice Mapping of chain IDs to Bookkeeper contract addresses.
    mapping(uint256 => mapping(address => bool)) public bookkeepers;

    /// @dev Restricts function access to only approved bundlers.
    modifier onlyBundler() {
        require(bundlers[msg.sender], "Caller is not a bundler");
        _;
    }

    /// @dev Sets the contract deployer as the initial bundler.
    constructor() {
        bundlers[msg.sender] = true;
    }

    /// @notice Proposes a new bundle of transactions.
    /// @dev Only callable by an approved bundler.
    /// @dev This function will call the optimistic oracle for bundle verification.
    /// @param _bundleData A reference to the offchain bundle data being proposed.
    function propose(bytes32 _bundleData) external override onlyBundler {
        bundles[block.timestamp] = _bundleData;
    }

    /// @notice Marks a bundle as finalized.
    /// @dev This should be implemented as a callback after oracle verification.
    /// @param _bundle The proposal timestamp of the bundle to finalize.
    function finalize(uint256 _bundle) external {
        lastFinalizedBundle = _bundle;
    }

    /// @notice Cancels a proposed bundle.
    /// @dev Only callable by an approved bundler.
    /// @dev They may cancel a bundle if they make an error, to propose a new bundle.
    /// @param _bundle The proposal timestamp of the bundle to cancel.
    function cancel(uint256 _bundle) external override onlyBundler {
        delete bundles[_bundle];
    }

    /// @notice Sweeps funds from an Oya Safe to the Bookkeeper contract.
    /// @dev Aggregating funds in the Bookkeeper is more efficient for settlement.
    /// @dev This function will call the optimistic oracle for sweep verification.
    /// @dev Account holders can withdraw just as easily from the Bookkeeper or Oya Safe.
    /// @param _oyaSafe The Oya Safe to sweep from.
    /// @param _tokenContract Token contract.
    /// @param _amount Amount to sweep.
    function sweep(address _oyaSafe, address _tokenContract, uint256 _amount) external override {
        // Sweep logic to be implemented.
        // This should simply transfer tokens from the Oya Safe to the Bookkeeper.
        // The sweep will be verified by the optimistic oracle, through the Oya Safe module.
    }

    /// @notice Bridges assets to another chain.
    /// @dev Placeholder function for asset bridging logic.
    /// @dev Not required for proof-of-concept, but will be implemented with Across later.
    /// @param _tokenContract The token contract from which assets are to be bridged.
    /// @param _amount The amount of assets to bridge.
    /// @param _chainId The target chain ID for bridging.
    function bridge(address _tokenContract, uint256 _amount, uint256 _chainId) external override onlyBundler {
        // Bridging logic to be implemented.
    }

    /// @notice Withdraws tokens from the Bookkeeper contract.
    /// @dev Placeholder function for withdrawal logic.
    /// @dev This function will call the optimistic oracle for withdrawal verification.
    /// @dev Account holders can withdraw just as easily from the Bookkeeper or Oya Safe.
    /// @param _tokenContract The token contract to withdraw from.
    /// @param _amount The amount to withdraw.
    function withdraw(address _tokenContract, uint256 _amount) external override {
        // Withdrawal logic to be implemented.
    }

    /// @notice Adds a new bundler.
    /// @dev Only callable by the contract owner. Bundlers are added by protocol governance.
    /// @param _bundler The address to grant bundler permissions to.
    function addBundler(address _bundler) external override onlyOwner {
        bundlers[_bundler] = true;
    }

    /// @notice Removes a bundler.
    /// @dev Only callable by the contract owner. Bundlers are removed by protocol governance.
    /// @param _bundler The address to revoke bundler permissions from.
    function removeBundler(address _bundler) external override onlyOwner {
        delete bundlers[_bundler];
    }

    /// @notice Updates the address of a Bookkeeper contract for a specific chain.
    /// @dev Only callable by the contract owner. Bookkeepers are added by protocol governance.
    /// @dev There may be multiple Bookkeepers on one chain temporarily during a migration.
    /// @param _chainId The chain to update.
    /// @param _contractAddress The address of the Bookkeeper contract.
    /// @param _isApproved Set to true to add the Bookkeeper contract, false to remove.
    function updateBookkeeper(uint256 _chainId, address _contractAddress, bool _isApproved) external override onlyOwner {
        bookkeepers[_chainId][_contractAddress] = _isApproved;
    }
}
