pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import "./OptimisticProposer.sol";

/**
 * @title Vault Tracker
 * @notice Multi-vault management system with optimistic governance
 * @dev Extends OptimisticProposer with vault-specific access controls and freezing mechanisms
 *
 * Architecture:
 * - Individual vaults with separate controllers and guardians
 * - Emergency freezing mechanisms (vault-level and protocol-level)
 * - Role-based access control for vault operations
 *
 * Security Features:
 * - Vault-level freezing for compromised vaults
 * - Protocol-wide emergency shutdown via CAT (Circuit Breaker)
 * - Guardian system for rapid response to threats
 *
 * @custom:invariant protocolFrozen implies proposals cannot be executed via executeProposal
 * @custom:invariant vaultFrozen[vaultId] implies functions guarded by notFrozen(vaultId) revert
 */
contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  /// @notice Emitted when the VaultTracker contract is deployed and initialized
  /// @param rules The protocol rules used for vault operations
  event VaultTrackerDeployed(string rules);

  /// @notice Emitted when the entire protocol is frozen by the CAT
  event ProtocolFrozen();

  /// @notice Emitted when the protocol is unfrozen
  event ChainUnfrozen();

  /// @notice Emitted when a new vault is created
  /// @param vaultId The unique identifier of the created vault
  /// @param controller The address assigned as the vault controller
  event VaultCreated(uint256 indexed vaultId, address indexed controller);

  /// @notice Emitted when a specific vault is frozen
  /// @param vaultId The identifier of the frozen vault
  event VaultFrozen(uint256 indexed vaultId);

  /// @notice Emitted when a specific vault is unfrozen
  /// @param vaultId The identifier of the unfrozen vault
  event VaultUnfrozen(uint256 indexed vaultId);

  /// @notice Emitted when vault-specific rules are updated
  /// @param vaultId The identifier of the vault
  /// @param vaultRules The new rules for the vault
  event SetVaultRules(uint256 indexed vaultId, string vaultRules);

  /// @notice Emitted when a proposer is assigned to a vault
  /// @param vaultId The identifier of the vault
  /// @param proposer The address assigned as proposer
  /// @param liveTime The timestamp when proposer assignment expires
  event SetProposer(uint256 indexed vaultId, address indexed proposer, uint256 liveTime);

  /// @notice Emitted when a controller is assigned to a vault
  /// @param vaultId The identifier of the vault
  /// @param controller The address assigned as controller
  event SetController(uint256 indexed vaultId, address indexed controller);

  /// @notice Emitted when a guardian is added or removed from a vault
  /// @param vaultId The identifier of the vault
  /// @param guardian The guardian address
  event SetGuardian(uint256 indexed vaultId, address indexed guardian);

  /// @notice Address authorized to trigger protocol-wide emergency freeze
  address private _cat;

  /// @notice Global protocol freeze state - when true, all proposals blocked
  /// @custom:security Only modifiable by designated CAT address
  bool public protocolFrozen = false;

  /// @notice Counter for generating unique vault IDs
  uint256 public nextVaultId;

  /// @notice Mapping of vault ID to custom rules string
  /// @dev Rules define vault-specific operational constraints
  mapping(uint256 => string) public vaultRules;

  /// @notice Mapping of vault ID to freeze status
  /// @dev When true, most vault operations are blocked
  mapping(uint256 => bool) public vaultFrozen;

  /// @notice Mapping of vault ID to authorized proposer address
  /// @dev Proposers can create proposals for specific vaults
  mapping(uint256 => address) public proposers;

  /// @notice Mapping of vault ID and address to controller status
  /// @dev Controllers have administrative rights over vaults
  mapping(uint256 => mapping(address => bool)) public isController;

  /// @notice Mapping of vault ID and address to guardian status
  /// @dev Guardians can freeze vaults in emergency situations
  mapping(uint256 => mapping(address => bool)) public isGuardian;

  /// @notice Modifier to ensure vault is not frozen before operations
  /// @param vaultId The vault identifier to check
  modifier notFrozen(uint256 vaultId) {
    require(!vaultFrozen[vaultId], "Vault is frozen");
    _;
  }

  /// @notice Modifier to restrict functions to the designated CAT address
  /// @dev Used for emergency protocol freezing/unfreezing
  modifier onlyCat() {
    require(msg.sender == _cat, "Only the CAT can trigger Oya shutdown");
    _;
  }

  /**
   * @notice Initializes the VaultTracker contract
   * @param _finder Address of the UMA Finder contract
   * @param _collateral Address of the collateral ERC20 token
   * @param _bondAmount Base bond amount for proposals
   * @param _rules Protocol rules for vault operations
   * @param _identifier UMA identifier for proposal validation
   * @param _liveness Dispute window for proposals
   * @dev Calls setUp with encoded parameters for proxy compatibility
   */
  constructor(
    address _finder,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    bytes memory initializeParams = abi.encode(_collateral, _bondAmount, _rules, _identifier, _liveness);
    setUp(initializeParams);
  }

  /**
   * @notice Initializes the contract state with provided parameters
   * @param initializeParams Encoded initialization parameters
   * @dev Decodes and sets up collateral, rules, identifier, and liveness
   * @custom:events Emits VaultTrackerDeployed event
   */
  function setUp(bytes memory initializeParams) public initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (address _collateral, uint256 _bondAmount, string memory _rules, bytes32 _identifier, uint64 _liveness) =
      abi.decode(initializeParams, (address, uint256, string, bytes32, uint64));
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();
    emit VaultTrackerDeployed(_rules);
  }

  /**
   * @notice Creates a new vault with the specified controller
   * @param _controller Address to be assigned as the vault controller
   * @return The unique identifier of the newly created vault
   * @dev Automatically assigns the next available vault ID
   * @custom:events Emits VaultCreated event
   */
  function createVault(address _controller) external returns (uint256) {
    nextVaultId++;
    _setController(nextVaultId, _controller);
    emit VaultCreated(nextVaultId, _controller);
    return nextVaultId;
  }

  /**
   * @notice Executes a proposal whose assertion is eligible for settlement
   * @param transactions Array of transactions to execute
   * @dev Prevents execution when protocol is frozen, then settles the oracle assertion and executes
   *      each transaction via the `Executor` base. Settlement reverts if the assertion is untruthful
   *      or still within liveness.
   *
   * Execution flow:
   * 1. Ensure protocol is not frozen
   * 2. Lookup `assertionId` for the `transactions` hash, then delete mappings to prevent re-use
   * 3. Settle at Optimistic Oracle V3; this reverts if not truthful or not resolvable
   * 4. Execute each transaction via `execute`
   *
   * @custom:events Emits `TransactionExecuted` for each transaction and `ProposalExecuted`
   * @custom:security Reentrancy protected
   */
  function executeProposal(Transaction[] memory transactions) external nonReentrant {
    require(!protocolFrozen, "Oya protocol is currently frozen");
    bytes32 proposalHash = keccak256(abi.encode(transactions));
    bytes32 assertionId = assertionIds[proposalHash];
    require(assertionId != bytes32(0), "Proposal hash does not exist");
    delete assertionIds[proposalHash];
    delete proposalHashes[assertionId];
    optimisticOracleV3.settleAndGetAssertionResult(assertionId);
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

  /**
   * @notice Sets the Circuit Breaker (CAT) address for emergency freezing
   * @param _catAddress Address authorized to freeze/unfreeze the protocol
   * @dev Only callable by contract owner. Set to zero address to disable CAT controls.
   * @custom:security Critical for emergency response capabilities
   */
  function setCat(address _catAddress) external onlyOwner {
    _cat = _catAddress;
  }

  /**
   * @notice Assigns a proposer to a specific vault
   * @param _vaultId The identifier of the vault
   * @param _proposer Address to be assigned as the vault proposer
   * @dev Proposers can create proposals for the specified vault. The `liveTime` emitted is
   *      informational and not enforced on-chain by this contract.
   * @custom:events Emits SetProposer event with expiration time
   */
  function setProposer(uint256 _vaultId, address _proposer) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    uint256 _liveTime = block.timestamp + 30 minutes;
    proposers[_vaultId] = _proposer;
    emit SetProposer(_vaultId, _proposer, _liveTime);
  }

  /**
   * @notice Assigns a controller to a specific vault
   * @param _vaultId The identifier of the vault
   * @param _controller Address to be assigned as the vault controller
   * @dev Controllers have administrative rights over vault operations
   * @custom:events Emits SetController event
   */
  function setController(uint256 _vaultId, address _controller) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    _setController(_vaultId, _controller);
  }

  /**
   * @notice Adds a guardian to a specific vault
   * @param _vaultId The identifier of the vault
   * @param _guardian Address to be assigned as a vault guardian
   * @dev Guardians can freeze the vault in emergency situations
   * @custom:events Emits SetGuardian event
   */
  function setGuardian(uint256 _vaultId, address _guardian) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    isGuardian[_vaultId][_guardian] = true;
    emit SetGuardian(_vaultId, _guardian);
  }

  /**
   * @notice Removes a guardian from a specific vault
   * @param _vaultId The identifier of the vault
   * @param _guardian Address to be removed from vault guardians
   * @dev Only proposals (calls from this contract) can remove guardians for security
   * @custom:events Emits SetGuardian event
   */
  function removeGuardian(uint256 _vaultId, address _guardian) external {
    require(msg.sender == address(this), "Guardians must be removed by a proposal");
    isGuardian[_vaultId][_guardian] = false;
    emit SetGuardian(_vaultId, _guardian);
  }

  /**
   * @notice Sets custom rules for a specific vault
   * @param _vaultId The identifier of the vault
   * @param _rules The rules string defining vault behavior
   * @dev Rules cannot be empty and define vault-specific constraints
   * @custom:events Emits SetVaultRules event
   */
  function setVaultRules(uint256 _vaultId, string memory _rules) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    require(bytes(_rules).length > 0, "Rules can not be empty");
    vaultRules[_vaultId] = _rules;
    emit SetVaultRules(_vaultId, _rules);
  }

  /**
   * @notice Freezes a specific vault to prevent operations
   * @param _vaultId The identifier of the vault to freeze
   * @dev Only guardians can freeze vaults, used for emergency response. Functions marked with
   *      `notFrozen(_vaultId)` will revert while frozen.
   * @custom:events Emits VaultFrozen event
   * @custom:security Emergency mechanism to halt compromised vaults
   */
  function freezeVault(uint256 _vaultId) external notFrozen(_vaultId) {
    require(isGuardian[_vaultId][msg.sender], "Not a guardian");
    vaultFrozen[_vaultId] = true;
    emit VaultFrozen(_vaultId);
  }

  /**
   * @notice Unfreezes a specific vault to resume operations
   * @param _vaultId The identifier of the vault to unfreeze
   * @dev Both guardians and proposals can unfreeze vaults
   * @custom:events Emits VaultUnfrozen event
   */
  function unfreezeVault(uint256 _vaultId) external {
    require(msg.sender == address(this) || isGuardian[_vaultId][msg.sender], "Not a guardian");
    vaultFrozen[_vaultId] = false;
    emit VaultUnfrozen(_vaultId);
  }

  /**
   * @notice Freezes the entire protocol to halt all operations
   * @dev Emergency circuit breaker activated by the CAT address
   * @custom:events Emits ProtocolFrozen event
   * @custom:security Only callable by designated CAT address
   */
  function freezeProtocol() external onlyCat {
    protocolFrozen = true;
    emit ProtocolFrozen();
  }

  /**
   * @notice Unfreezes the protocol to resume normal operations
   * @dev Emergency circuit breaker deactivated by the CAT address
   * @custom:events Emits ChainUnfrozen event
   * @custom:security Only callable by designated CAT address
   */
  function unfreezeProtocol() external onlyCat {
    protocolFrozen = false;
    emit ChainUnfrozen();
  }

  /**
   * @notice Internal function to set a vault controller
   * @param _vaultId The identifier of the vault
   * @param _controller Address to be assigned as controller
   * @dev Internal helper used by createVault and setController
   * @custom:events Emits SetController event
   */
  function _setController(uint256 _vaultId, address _controller) internal {
    isController[_vaultId][_controller] = true;
    emit SetController(_vaultId, _controller);
  }
}
