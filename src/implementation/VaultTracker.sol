pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import "./OptimisticProposer.sol";

/**
 * @title Vault Tracker
 * @notice Vault creation and proposal execution system using optimistic verification
 * @dev Extends OptimisticProposer to enable verified proposal execution
 *
 * Architecture:
 * - Generates unique vault IDs with associated controller addresses
 * - Executes transaction batches validated by UMA's Optimistic Oracle
 *
 * Security Features:
 * - Optimistic Oracle validation for all proposals
 * - Reentrancy protection on critical functions
 *
 * @custom:invariant Proposals must exist before execution
 */
contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  /// @notice Errors for gas-efficient reverts
  error UnknownProposal();


  /// @notice Emitted when the VaultTracker contract is deployed and initialized
  /// @param rules The protocol rules used for vault transaction validation
  event VaultTrackerDeployed(string rules);

  /// @notice Emitted when a new vault is created
  /// @param vaultId The unique identifier of the created vault
  /// @param controller The address assigned as the vault controller
  event VaultCreated(uint256 indexed vaultId, address indexed controller);

  /// @notice Counter for generating unique vault IDs
  uint256 public nextVaultId;


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
    emit VaultCreated(nextVaultId, _controller);
    return nextVaultId;
  }

  /**
   * @notice Executes a proposal whose assertion is eligible for settlement
   * @param transactions Array of transactions to execute
   * @dev Settles the oracle assertion and executes each transaction via the `Executor` base.
   *      Settlement reverts if the assertion is untruthful or still within liveness.
   *
   * Execution flow:
   * 1. Lookup `assertionId` for the `transactions` hash, then delete mappings to prevent re-use
   * 2. Settle at Optimistic Oracle V3; this reverts if not truthful or not resolvable
   * 3. Execute each transaction via `execute`
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
}
