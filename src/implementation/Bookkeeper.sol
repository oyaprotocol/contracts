pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@uma/core/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/data-verification-mechanism/interfaces/FinderInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/StoreInterface.sol";

import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

import "@uma/core/common/implementation/Lockable.sol";
import "@uma/core/common/interfaces/AddressWhitelistInterface.sol";

import "./OptimisticProposer.sol";

/// @title Bookkeeper
/// @dev Implements transaction bundling and settlement functionality for the Oya network.
/// Allows for the registration and management of bundlers, and the proposal, finalization, and
/// cancellation of transaction bundles.
contract Bookkeeper is OptimisticProposer, Executor, BookkeeperInterface, Ownable {

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
  function proposeBundle(bytes32 _bundleData) external override onlyBundler {
    bundles[block.timestamp] = _bundleData;
  }

  /// @notice Marks a bundle as finalized.
  /// @dev This should be implemented as a callback after oracle verification.
  /// @param _bundle The proposal timestamp of the bundle to finalize.
  function finalizeBundle(uint256 _bundle) external {
    lastFinalizedBundle = _bundle;
  }

  /// @notice Cancels a proposed bundle.
  /// @dev Only callable by an approved bundler.
  /// @dev They may cancel a bundle if they make an error, to propose a new bundle.
  /// @param _bundle The proposal timestamp of the bundle to cancel.
  function cancelBundle(uint256 _bundle) external override onlyBundler {
    delete bundles[_bundle];
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

  /**
   * @notice Executes an approved proposal.
   * @param transactions the transactions being executed. These must exactly match those that were proposed.
   */
  function executeProposal(Transaction[] memory transactions) external nonReentrant {
    // Recreate the proposal hash from the inputs and check that it matches the stored proposal hash.
    bytes32 proposalHash = keccak256(abi.encode(transactions));

    // Get the original proposal assertionId.
    bytes32 assertionId = assertionIds[proposalHash];

    // This will reject the transaction if the proposal hash generated from the inputs does not have the associated
    // assertionId stored. This is possible when a) the transactions have not been proposed, b) transactions have
    // already been executed, c) the proposal was disputed or d) the proposal was deleted after Optimistic Oracle V3
    // upgrade.
    require(assertionId != bytes32(0), "Proposal hash does not exist");

    // Remove proposal hash and assertionId so transactions can not be executed again.
    delete assertionIds[proposalHash];
    delete proposalHashes[assertionId];

    // There is no need to check the assertion result as this point can be reached only for non-disputed assertions.
    // This will revert if the assertion has not been settled and can not currently be settled.
    optimisticOracleV3.settleAndGetAssertionResult(assertionId);

    // Execute the transactions.
    for (uint256 i = 0; i < transactions.length; i++) {
      Transaction memory transaction = transactions[i];

      require(
        execute(transaction.to, transaction.value, transaction.data, transaction.operation, type(uint256).max),
        "Failed to execute transaction"
      );
      emit TransactionExecuted(proposalHash, assertionId, i);
    }

    emit ProposalExecuted(proposalHash, assertionId);
  }

}
