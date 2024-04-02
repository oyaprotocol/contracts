pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

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

/// @title Bookkeeper
/// @dev Implements transaction bundling and settlement functionality for the Oya network.
/// Allows for the registration and management of bundlers, and the proposal, finalization, and
/// cancellation of transaction bundles.
contract Bookkeeper is OptimisticOracleV3CallbackRecipientInterface, BookkeeperInterface, Ownable, Lockable {

  event TransactionsProposed(
    address indexed proposer,
    uint256 indexed proposalTime,
    bytes32 indexed assertionId,
    Proposal proposal,
    bytes32 proposalHash,
    bytes explanation,
    string rules,
    uint256 challengeWindowEnds
  );

  event TransactionExecuted(
    bytes32 indexed proposalHash, bytes32 indexed assertionId, uint256 indexed transactionIndex
  );

  event ProposalExecuted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  event ProposalDeleted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  event SetCollateralAndBond(IERC20 indexed collateral, uint256 indexed bondAmount);

  // Struct for a proposed transaction.
  struct Transaction {
    address to; // The address to which the transaction is being sent.
    Enum.Operation operation; // Operation type of transaction: 0 == call, 1 == delegate call.
    uint256 value; // The value, in wei, to be sent with the transaction.
    bytes data; // The data payload to be sent in the transaction.
  }

  // Struct for a proposed set of transactions, used only for off-chain infrastructure.
  struct Proposal {
    Transaction[] transactions;
    uint256 requestTime;
  }

  mapping(bytes32 => bytes32) public assertionIds; // Maps proposal hashes to assertionIds.
  mapping(bytes32 => bytes32) public proposalHashes; // Maps assertionIds to proposal hashes.

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

  /**
   * @notice Makes a new proposal for transactions to be executed with an explanation argument.
   * @param transactions the transactions being proposed.
   * @param explanation Auxillary information that can be referenced to validate the proposal.
   * @dev Proposer must grant the contract collateral allowance at least to the bondAmount or result of getMinimumBond
   * from the Optimistic Oracle V3, whichever is greater.
   */
  function proposeTransactions(
    Transaction[] memory transactions,
    bytes memory explanation
  ) external nonReentrant {
    // note: Optional explanation explains the intent of the transactions to make comprehension easier.
    uint256 time = getCurrentTime();
    address proposer = msg.sender;

    // Create proposal in memory to emit in an event.
    Proposal memory proposal;
    proposal.requestTime = time;

    // Add transactions to proposal in memory.
    for (uint256 i = 0; i < transactions.length; i++) {
      require(transactions[i].to != address(0), "The `to` address cannot be 0x0");
      // If the transaction has any data with it the recipient must be a contract, not an EOA.
      if (transactions[i].data.length > 0) require(_isContract(transactions[i].to), "EOA can't accept tx with data");
    }
    proposal.transactions = transactions;

    // Create the proposal hash.
    bytes32 proposalHash = keccak256(abi.encode(transactions));

    // Add the proposal hash, explanation and rules to ancillary data.
    bytes memory claim = _constructClaim(proposalHash, explanation);

    // Check that the proposal is not already mapped to an assertionId, i.e., is not a duplicate.
    require(assertionIds[proposalHash] == bytes32(0), "Duplicate proposals not allowed");

    // Get the bond from the proposer and approve the required bond to be used by the Optimistic Oracle V3.
    // This will fail if the proposer has not granted the Oya module contract an allowance
    // of the collateral token equal to or greater than the totalBond.
    uint256 totalBond = getProposalBond();
    collateral.safeTransferFrom(proposer, address(this), totalBond);
    collateral.safeIncreaseAllowance(address(optimisticOracleV3), totalBond);

    // Assert that the proposal is correct at the Optimistic Oracle V3.
    bytes32 assertionId = optimisticOracleV3.assertTruth(
      claim, // claim containing proposalHash, explanation and rules.
      proposer, // asserter will receive back bond if the assertion is correct.
      address(this), // callbackRecipient is set to this contract for automated proposal deletion on disputes.
      escalationManager, // escalationManager (if set) used for whitelisting proposers / disputers.
      liveness, // liveness in seconds.
      collateral, // currency in which the bond is denominated.
      totalBond, // bond amount used to assert proposal.
      identifier, // identifier used to determine if the claim is correct at DVM.
      bytes32(0) // domainId is not set.
    );

    // Maps the proposal hash to the returned assertionId and vice versa.
    assertionIds[proposalHash] = assertionId;
    proposalHashes[assertionId] = proposalHash;

    emit TransactionsProposed(proposer, time, assertionId, proposal, proposalHash, explanation, rules, time + liveness);
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
        exec(transaction.to, transaction.value, transaction.data, transaction.operation),
        "Failed to execute transaction"
      );
      emit TransactionExecuted(proposalHash, assertionId, i);
    }

    emit ProposalExecuted(proposalHash, assertionId);
  }

  /**
   * @notice Function to delete a proposal on an Optimistic Oracle V3 upgrade.
   * @param proposalHash the hash of the proposal to delete.
   * @dev In case of an Optimistic Oracle V3 upgrade, the proposal execution would be blocked as its related
   * assertionId would not be recognized by the new Optimistic Oracle V3. This function allows the proposal to be
   * deleted if detecting an Optimistic Oracle V3 upgrade so that transactions can be re-proposed if needed.
   */
  function deleteProposalOnUpgrade(bytes32 proposalHash) public nonReentrant {
    require(proposalHash != bytes32(0), "Invalid proposal hash");
    bytes32 assertionId = assertionIds[proposalHash];
    require(assertionId != bytes32(0), "Proposal hash does not exist");

    // Detect Optimistic Oracle V3 upgrade by checking if it has the matching assertionId.
    require(optimisticOracleV3.getAssertion(assertionId).asserter == address(0), "OOv3 upgrade not detected");

    // Remove proposal hash and assertionId so that transactions can be re-proposed if needed.
    delete assertionIds[proposalHash];
    delete proposalHashes[assertionId];

    emit ProposalDeleted(proposalHash, assertionId);
  }

  /**
   * @notice Callback to automatically delete a proposal that was disputed.
   * @param assertionId the identifier of the disputed assertion.
   */
  function assertionDisputedCallback(bytes32 assertionId) external {
    bytes32 proposalHash = proposalHashes[assertionId];

    // Callback should only be called by the Optimistic Oracle V3. Address would not match in case of contract
    // upgrade, thus try deleting the proposal through deleteProposalOnUpgrade function that should revert if
    // address mismatch was not caused by an Optimistic Oracle V3 upgrade.
    if (msg.sender == address(optimisticOracleV3)) {
      // Validate the assertionId through existence of non-zero proposalHash. This is the same check as in
      // deleteProposalOnUpgrade method that is called in the else branch.
      require(proposalHash != bytes32(0), "Invalid proposal hash");

      // Delete the disputed proposal and associated assertionId.
      delete assertionIds[proposalHash];
      delete proposalHashes[assertionId];

      emit ProposalDeleted(proposalHash, assertionId);
    } else {
      deleteProposalOnUpgrade(proposalHash);
    }
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved.
   * @dev This function does nothing and is only here to satisfy the callback recipient interface.
   * @param assertionId The identifier of the assertion that was resolved.
   * @param assertedTruthfully Whether the assertion was resolved as truthful or not.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {}

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
   * @notice Gets the current time for this contract.
   * @dev This only exists so it can be overridden for testing.
   */
  function getCurrentTime() public view virtual returns (uint256) {
    return block.timestamp;
  }

  /**
   * @notice Getter function to check required collateral currency approval.
   * @return The amount of bond required to propose a transaction.
   */
  function getProposalBond() public view returns (uint256) {
    uint256 minimumBond = optimisticOracleV3.getMinimumBond(address(collateral));
    return minimumBond > bondAmount ? minimumBond : bondAmount;
  }

  // Checks if the address is a contract.
  function _isContract(address addr) internal view returns (bool) {
    return addr.code.length > 0;
  }

  // Constructs the claim that will be asserted at the Optimistic Oracle V3.
  function _constructClaim(bytes32 proposalHash, bytes memory explanation) internal view returns (bytes memory) {
    return abi.encodePacked(
      ClaimData.appendKeyValueBytes32("", PROPOSAL_HASH_KEY, proposalHash),
      ",",
      EXPLANATION_KEY,
      ':"',
      explanation,
      '",',
      RULES_KEY,
      ':"',
      rules,
      '"'
    );
  }

}
