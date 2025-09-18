pragma solidity ^0.8.6;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uma/core/common/implementation/Lockable.sol";
import "@uma/core/common/interfaces/AddressWhitelistInterface.sol";
import "@uma/core/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/data-verification-mechanism/interfaces/FinderInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/StoreInterface.sol";
import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@uma/core/optimistic-oracle-v3/implementation/ClaimData.sol";

/**
 * @title Optimistic Proposer
 * @notice Core contract for optimistic proposal system using UMA's Optimistic Oracle V3
 * @dev Implements optimistic governance where proposals are assumed valid unless disputed
 *
 * Architecture:
 * - Uses UMA's Optimistic Oracle V3 for truth verification
 * - Supports batched transaction proposals with collateral bonding
 * - Implements callback system for automated proposal lifecycle management
 *
 * Security Model:
 * - Proposals are bonded with collateral tokens
 * - Liveness period allows for disputes before execution
 * - Automatic proposal deletion on disputes
 * - Reentrancy protection on critical functions
 *
 * @custom:invariant If assertionIds[proposalHash] != bytes32(0) then proposalHashes[assertionIds[proposalHash]] == proposalHash
 * @custom:invariant Collateral token must be whitelisted by UMA governance
 */
contract OptimisticProposer is OptimisticOracleV3CallbackRecipientInterface, Lockable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

  /// @notice Key used in claim data to identify the explanation field
  bytes public constant EXPLANATION_KEY = "explanation";

  /// @notice Key used in claim data to identify the proposal hash field
  bytes public constant PROPOSAL_HASH_KEY = "proposalHash";

  /// @notice Key used in claim data to identify the rules field
  bytes public constant RULES_KEY = "rules";

  /// @notice Emitted when the Optimistic Oracle V3 contract address is updated
  /// @param newOptimisticOracleV3 The new Optimistic Oracle V3 contract address
  event OptimisticOracleChanged(address indexed newOptimisticOracleV3);

  /// @notice Emitted when a proposal is deleted due to dispute or upgrade
  /// @param proposalHash The hash of the deleted proposal
  /// @param assertionId The assertion ID associated with the deleted proposal
  event ProposalDeleted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  /// @notice Emitted when a proposal is successfully executed
  /// @param proposalHash The hash of the executed proposal
  /// @param assertionId The assertion ID associated with the executed proposal
  event ProposalExecuted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  /// @notice Emitted when collateral token and bond amount are updated
  /// @param collateral The new collateral ERC20 token address
  /// @param bondAmount The new bond amount required for proposals
  event SetCollateralAndBond(IERC20 indexed collateral, uint256 indexed bondAmount);

  /// @notice Emitted when the protocol rules are updated
  /// @param rules The new protocol rules string
  event SetRules(string rules);

  /// @notice Emitted when the liveness period is updated
  /// @param liveness The new liveness period in seconds
  event SetLiveness(uint64 indexed liveness);

  /// @notice Emitted when the identifier is updated
  /// @param identifier The new identifier for proposal validation
  event SetIdentifier(bytes32 indexed identifier);

  /// @notice Emitted when the escalation manager is updated
  /// @param escalationManager The new escalation manager address
  event SetEscalationManager(address indexed escalationManager);

  /// @notice Emitted when the vault tracker is updated
  /// @param vaultTracker The new vault tracker address
  event SetVaultTracker(address indexed vaultTracker);

  /// @notice Emitted when a new proposal is created and asserted
  /// @param proposer Address that created the proposal
  /// @param proposalTime Timestamp when the proposal was created
  /// @param assertionId The assertion ID from the Optimistic Oracle
  /// @param proposal The complete proposal struct containing transactions
  /// @param proposalHash Hash of the proposal for tracking
  /// @param explanation Optional explanation of the proposal
  /// @param rules Protocol rules applied to this proposal
  /// @param challengeWindowEnds Timestamp when the challenge window ends
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

  /// @notice Emitted when an individual transaction within a proposal is executed
  /// @param proposalHash Hash of the proposal containing this transaction
  /// @param assertionId The assertion ID associated with the proposal
  /// @param transactionIndex Index of the transaction within the proposal
  event TransactionExecuted(
    bytes32 indexed proposalHash, bytes32 indexed assertionId, uint256 indexed transactionIndex
  );

  /// @notice Represents a proposal containing multiple transactions
  /// @dev Used to batch multiple transactions into a single optimistic proposal
  struct Proposal {
    Transaction[] transactions; /// @notice Array of transactions to be executed if proposal succeeds
    uint256 requestTime; /// @notice Timestamp when the proposal was created
  }

  /// @notice Represents an individual transaction within a proposal
  /// @dev Compatible with Gnosis Safe transaction structure
  struct Transaction {
    address to; /// @notice Target address for the transaction
    Enum.Operation operation; /// @notice Operation type (Call, DelegateCall, etc.)
    uint256 value; /// @notice ETH value to send with the transaction
    bytes data; /// @notice Calldata for the transaction
  }

  /// @notice UMA Finder contract for locating protocol implementations
  FinderInterface public finder;

  /// @notice UMA Optimistic Oracle V3 contract for truth assertions
  OptimisticOracleV3Interface public optimisticOracleV3;

  /// @notice Base bond amount required for proposals (may be increased by oracle minimum)
  uint256 public bondAmount;

  /// @notice ERC20 token used as collateral for bonding proposals
  IERC20 public collateral;

  /// @notice Address authorized to escalate disputes (optional whitelist manager)
  address public escalationManager;

  /// @notice Identifier used by DVM to validate proposal claims
  bytes32 public identifier;

  /// @notice Time window for disputing proposals in seconds
  uint64 public liveness;

  /// @notice Protocol rules string used in proposal validation
  string public rules;

  /// @notice Maps proposal hashes to their corresponding assertion IDs
  /// @dev Used to track active proposals and prevent duplicates
  mapping(bytes32 => bytes32) public assertionIds;

  /// @notice Maps assertion IDs to their corresponding proposal hashes
  /// @dev Used in callback functions to identify proposals
  mapping(bytes32 => bytes32) public proposalHashes;

  /**
   * @notice Callback function invoked when an assertion is disputed
   * @dev If called by Optimistic Oracle V3, the disputed proposal is auto-deleted. If called by any
   *      other address, this attempts upgrade-safe cleanup via deleteProposalOnUpgrade and will revert
   *      unless an Optimistic Oracle V3 upgrade has been detected.
   * @param assertionId The ID of the disputed assertion
   * @custom:security Automatic deletion only occurs when msg.sender is the Optimistic Oracle V3
   * @custom:events Emits ProposalDeleted event
   */
  function assertionDisputedCallback(bytes32 assertionId) external virtual {
    // Callback to automatically delete a proposal that was disputed.
    bytes32 proposalHash = proposalHashes[assertionId];

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
   * @notice Callback function invoked when an assertion is resolved
   * @dev Interface requirement - implementation handled by child contracts
   * @param assertionId The ID of the resolved assertion
   * @param assertedTruthfully Whether the assertion was resolved as truthful
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external virtual {}

  /**
   * @notice Deletes a proposal during Optimistic Oracle V3 contract upgrades
   * @dev Detects oracle upgrades and removes proposals to allow re-proposal
   * @param proposalHash The hash of the proposal to delete
   * @custom:security Reentrancy protected, validates oracle upgrade detection
   * @custom:events Emits ProposalDeleted event
   */
  function deleteProposalOnUpgrade(bytes32 proposalHash) public nonReentrant {
    // Function to delete a proposal on an Optimistic Oracle V3 upgrade.
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
   * @notice Gets the current block timestamp
   * @dev Virtual function to allow overriding in tests
   * @return The current block timestamp
   * @custom:testing Can be overridden for testing different time scenarios
   */
  function getCurrentTime() public view virtual returns (uint256) {
    return block.timestamp;
  }

  /**
   * @notice Calculates the required bond amount for a new proposal
   * @dev Returns the maximum of configured bondAmount and oracle minimum bond
   * @return The required bond amount in collateral token units
   */
  function getProposalBond() public view returns (uint256) {
    uint256 minimumBond = optimisticOracleV3.getMinimumBond(address(collateral));
    return minimumBond > bondAmount ? minimumBond : bondAmount;
  }

  /**
   * @notice Proposes a batch of transactions for optimistic execution
   * @param transactions Array of transactions to be executed if proposal succeeds
   * @param explanation Optional explanation of the proposal's intent and rationale
   * @dev Creates an assertion at the Optimistic Oracle V3 with bonded collateral
   *
   * Requirements:
   * - Transactions must target valid addresses (not zero address)
   * - If a transaction includes calldata, the `to` address must be a contract
   * - Proposer must have approved sufficient collateral
   * - Proposal must not be a duplicate
   *
   * Security considerations:
   * - Validates transaction targets to prevent invalid proposals
   * - Bonds collateral to ensure proposer commitment
   * - Stores proposal hash for later execution verification
   *
   * @custom:events Emits TransactionsProposed with full proposal details
   * @custom:security Reentrancy protected, validates all transaction parameters
   */
  function proposeTransactions(Transaction[] memory transactions, bytes memory explanation) external virtual nonReentrant {
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
   * @notice Sets the collateral token and bond amount for proposals
   * @param _collateral The ERC20 token to use as collateral
   * @param _bondAmount The base bond amount required for proposals
   * @dev Collateral token must be whitelisted by UMA governance
   * @custom:security Only callable by contract owner
   * @custom:events Emits SetCollateralAndBond event
   */
  function setCollateralAndBond(IERC20 _collateral, uint256 _bondAmount) public onlyOwner {
    // ERC20 token to be used as collateral (must be approved by UMA governance).
    AddressWhitelistInterface collateralWhitelist = _getCollateralWhitelist();
    bool isWhitelisted = collateralWhitelist.isOnWhitelist(address(_collateral));
    require(isWhitelisted, "Bond token not supported");
    collateral = _collateral;
    bondAmount = _bondAmount;
    emit SetCollateralAndBond(_collateral, _bondAmount);
  }

  /**
   * @notice Sets the escalation manager for dispute handling
   * @param _escalationManager Address authorized to escalate disputes
   * @dev Can be set to zero address to disable escalation management
   * @custom:security Only callable by contract owner, validates contract existence
   * @custom:events Emits SetEscalationManager event
   */
  function setEscalationManager(address _escalationManager) external onlyOwner {
    require(_isContract(_escalationManager) || _escalationManager == address(0), "EM is not a contract");
    escalationManager = _escalationManager;
    emit SetEscalationManager(_escalationManager);
  }

  /**
   * @notice Sets the identifier used for proposal validation at the DVM
   * @param _identifier The new identifier for validating proposals
   * @dev Identifier must be supported by UMA's identifier whitelist
   * @custom:security Only callable by contract owner
   * @custom:events Emits SetIdentifier event
   */
  function setIdentifier(bytes32 _identifier) public onlyOwner {
    // Set identifier which is used along with the rules to determine if transactions are valid.
    require(_getIdentifierWhitelist().isIdentifierSupported(_identifier), "Identifier not supported");
    identifier = _identifier;
    emit SetIdentifier(_identifier);
  }

  /**
   * @notice Sets the liveness period for disputing proposals
   * @param _liveness The dispute window in seconds
   * @dev Must be greater than 0 and less than 5200 weeks (maximum allowed)
   * @custom:security Only callable by contract owner, validates reasonable bounds
   * @custom:events Emits SetLiveness event
   */
  function setLiveness(uint64 _liveness) public onlyOwner {
    require(_liveness > 0, "Liveness can't be 0");
    require(_liveness < 5200 weeks, "Liveness must be less than 5200 weeks");
    liveness = _liveness;
    emit SetLiveness(_liveness);
  }

  /**
   * @notice Sets the protocol rules for proposal validation
   * @param _rules The new protocol rules string
   * @dev Rules string cannot be empty and is used in claim construction
   * @custom:security Only callable by contract owner
   * @custom:events Emits SetRules event
   */
  function setRules(string memory _rules) public onlyOwner {
    require(bytes(_rules).length > 0, "Rules can not be empty");
    rules = _rules;
    emit SetRules(_rules);
  }

  /**
   * @notice Synchronizes contract state with latest protocol implementations
   * @dev Updates Optimistic Oracle V3 address if it has changed in the Finder
   * @custom:security Reentrancy protected
   * @custom:events Emits OptimisticOracleChanged if address updated
   */
  function sync() external nonReentrant {
    _sync();
  }

  /**
   * @notice Constructs the claim data for Optimistic Oracle V3 assertion
   * @param proposalHash The hash of the proposal being asserted
   * @param explanation Optional explanation of the proposal
   * @return The formatted claim data containing proposal details
   * @dev Internal function that formats data for oracle assertion
   */
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

  /**
   * @notice Gets the UMA collateral whitelist contract
   * @return The AddressWhitelistInterface for collateral validation
   * @dev Internal helper to access UMA protocol contracts
   */
  function _getCollateralWhitelist() internal view returns (AddressWhitelistInterface) {
    return AddressWhitelistInterface(finder.getImplementationAddress(OracleInterfaces.CollateralWhitelist));
  }

  /**
   * @notice Gets the UMA identifier whitelist contract
   * @return The IdentifierWhitelistInterface for identifier validation
   * @dev Internal helper to access UMA protocol contracts
   */
  function _getIdentifierWhitelist() internal view returns (IdentifierWhitelistInterface) {
    return IdentifierWhitelistInterface(finder.getImplementationAddress(OracleInterfaces.IdentifierWhitelist));
  }

  /**
   * @notice Gets the UMA Store contract
   * @return The StoreInterface for protocol fee calculations
   * @dev Internal helper to access UMA protocol contracts
   */
  function _getStore() internal view returns (StoreInterface) {
    return StoreInterface(finder.getImplementationAddress(OracleInterfaces.Store));
  }

  /**
   * @notice Checks if an address is a contract
   * @param addr The address to check
   * @return True if the address is a contract, false if it's an EOA
   * @dev Uses address.code.length (extcodesize) check
   */
  function _isContract(address addr) internal view returns (bool) {
    return addr.code.length > 0;
  }

  /**
   * @notice Internal function to sync with latest Optimistic Oracle V3
   * @dev Updates the oracle address if it has changed in the Finder
   */
  function _sync() internal {
    address newOptimisticOracleV3 = finder.getImplementationAddress(OracleInterfaces.OptimisticOracleV3);
    if (newOptimisticOracleV3 != address(optimisticOracleV3)) {
      optimisticOracleV3 = OptimisticOracleV3Interface(newOptimisticOracleV3);
      emit OptimisticOracleChanged(newOptimisticOracleV3);
    }
  }

}
