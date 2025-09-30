pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import "./OptimisticProposer.sol";

/**
 * @title Vault Tracker
 * @notice Multi-vault management system with optimistic governance
 * @dev Extends OptimisticProposer with vault-specific access controls
 *
 * Architecture:
 * - Individual vaults with separate controllers
 * - Role-based access control for vault operations
 *
 * Security Features:
 * - Role-based access control for vault operations
 *
 * @custom:invariant Proposals must exist before execution
 */
contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  /// @notice Errors for gas-efficient reverts
  error NotController();
  error UnknownProposal();
  error EmptyRules();

  

  /// @notice Emitted when a new vault is created
  /// @param vaultId The unique identifier of the created vault
  /// @param controller The address assigned as the vault controller
  event VaultCreated(uint256 indexed vaultId, address indexed controller);

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

  

  /// @notice Counter for generating unique vault IDs
  uint256 public nextVaultId;

  /// @notice Mapping of vault ID to custom rules string
  /// @dev Rules define vault-specific operational constraints
  mapping(uint256 => string) public vaultRules;

  /// @notice Mapping of vault ID to authorized proposer address
  /// @dev Proposers can create proposals for specific vaults
  mapping(uint256 => address) public proposers;

  /// @notice Mapping of vault ID and address to controller status
  /// @dev Controllers have administrative rights over vaults
  mapping(uint256 => mapping(address => bool)) public isController;

  

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
    bytes32 proposalHash = keccak256(abi.encode(transactions));
    bytes32 assertionId = assertionIds[proposalHash];
    if (assertionId == bytes32(0)) revert UnknownProposal();
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
   * @notice Assigns a proposer to a specific vault
   * @param _vaultId The identifier of the vault
   * @param _proposer Address to be assigned as the vault proposer
   * @dev Proposers can create proposals for the specified vault. The `liveTime` emitted is
   *      informational and not enforced on-chain by this contract.
   * @custom:events Emits SetProposer event with expiration time
   */
  function setProposer(uint256 _vaultId, address _proposer) external {
    if (!(msg.sender == address(this) || isController[_vaultId][msg.sender])) revert NotController();
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
  function setController(uint256 _vaultId, address _controller) external {
    if (!(msg.sender == address(this) || isController[_vaultId][msg.sender])) revert NotController();
    _setController(_vaultId, _controller);
  }

  

  /**
   * @notice Sets custom rules for a specific vault
   * @param _vaultId The identifier of the vault
   * @param _rules The rules string defining vault behavior
   * @dev Rules cannot be empty and define vault-specific constraints
   * @custom:events Emits SetVaultRules event
   */
  function setVaultRules(uint256 _vaultId, string memory _rules) external {
    if (!(msg.sender == address(this) || isController[_vaultId][msg.sender])) revert NotController();
    if (bytes(_rules).length == 0) revert EmptyRules();
    vaultRules[_vaultId] = _rules;
    emit SetVaultRules(_vaultId, _rules);
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
