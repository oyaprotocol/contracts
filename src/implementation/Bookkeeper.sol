pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
contract Bookkeeper is OptimisticProposer, Executor, BookkeeperInterface {

  using SafeERC20 for IERC20;

  event BookkeeperDeployed(address indexed bundler, string rules);

  event BundleProposed(uint256 indexed timestamp, string bundleData);

  event BundleCanceled(uint256 indexed timestamp);

  event BundlerAdded(address indexed bundler);

  event BundlerRemoved(address indexed bundler);

  event BookkeeperUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);

  /// @notice Mapping of proposal block timestamps to string pointers to the bundle data.
  mapping(uint256 => string) public bundles;

  /// @notice The proposal timestamp of the most recently finalized bundle.
  uint256 public lastFinalizedBundle;

  /// @notice Addresses of approved bundlers.
  mapping(address => bool) public bundlers;

  /// @notice Mapping of Bookkeeper contract address to chain IDs, and whether they are authorized.
  mapping(address => mapping(uint256 => bool)) public bookkeepers;

  /// @dev Restricts function access to only approved bundlers.
  modifier onlyBundler() {
    require(bundlers[msg.sender], "Caller is not a bundler");
    _;
  }

  /**
   * @notice Construct Oya Bookkeeper contract.
   * @param _finder UMA Finder contract address.
   * @param _bundler Address of the initial bundler for the Bookkeeper contract.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _rules Reference to the rules for the Bookkeeper.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
   */
  constructor(
    address _finder,
    address _bundler,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    bytes memory initializeParams = abi.encode(_bundler, _collateral, _bondAmount, _rules, _identifier, _liveness);
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    setUp(initializeParams);
  }

  /**
   * @notice Sets up the Oya module.
   * @param initializeParams ABI encoded parameters to initialize the module with.
   * @dev This method can be called only either by the constructor or as part of first time initialization when
   * cloning the module.
   */
  function setUp(bytes memory initializeParams) public initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (
      address _bundler,
      address _collateral,
      uint256 _bondAmount,
      string memory _rules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, address, uint256, string, bytes32, uint64));
    addBundler(_bundler);
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();

    emit BookkeeperDeployed(_bundler, _rules);
  }

  /// @notice Proposes a new bundle of transactions.
  /// @dev Only callable by an approved bundler.
  /// @dev This function will call the optimistic oracle for bundle verification.
  /// @param _bundleData A reference to the offchain bundle data being proposed.
  function proposeBundle(string memory _bundleData) external onlyBundler {
    bundles[block.timestamp] = _bundleData;
  }

  /// @notice Cancels a proposed bundle.
  /// @dev Only callable by an approved bundler.
  /// @dev They may cancel a bundle if they make an error, to propose a new bundle.
  /// @param _bundleTimestamp The proposal timestamp of the bundle to cancel.
  function cancelBundle(uint256 _bundleTimestamp) external onlyBundler {
    delete bundles[_bundleTimestamp];
  }

  /// @notice Adds a new bundler.
  /// @dev Only callable by the contract owner. Bundlers are added by protocol governance.
  /// @param _bundler The address to grant bundler permissions to.
  function addBundler(address _bundler) public onlyOwner {
    bundlers[_bundler] = true;
    emit BundlerAdded(_bundler);
  }

  /// @notice Removes a bundler.
  /// @dev Only callable by the contract owner. Bundlers are removed by protocol governance.
  /// @param _bundler The address to revoke bundler permissions from.
  function removeBundler(address _bundler) external onlyOwner {
    delete bundlers[_bundler];
    emit BundlerRemoved(_bundler);
  }

  /// @notice Updates the address of a Bookkeeper contract for a specific chain.
  /// @dev Only callable by the contract owner. Bookkeepers are added by protocol governance.
  /// @dev There may be multiple Bookkeepers on one chain temporarily during a migration.
  /// @param _contractAddress The address of the Bookkeeper contract.
  /// @param _chainId The chain to update.
  /// @param _isApproved Set to true to add the Bookkeeper contract, false to remove.
  function updateBookkeeper(address _contractAddress, uint256 _chainId, bool _isApproved) external onlyOwner {
    bookkeepers[_contractAddress][_chainId] = _isApproved;
    emit BookkeeperUpdated(_contractAddress, _chainId, _isApproved);
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

  /// @notice Marks a bundle as finalized.
  /// @dev This should be implemented as a callback after oracle verification.
  /// @param _bundle The proposal timestamp of the bundle to finalize.
  function _finalizeBundle(uint256 _bundle) internal {
    lastFinalizedBundle = _bundle;
  }

}
