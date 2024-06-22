pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";
import "forge-std/console.sol";

/// @title Bookkeeper
/// @dev Holds assets on behalf of account holders in the Oya network.
contract Bookkeeper is OptimisticProposer, Executor {

  using SafeERC20 for IERC20;

  event BookkeeperDeployed(string rules);

  event BookkeeperUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);

  event SetGlobalRules(string globalRules);

  event SetAccountRules(address indexed account, string accountRules);

  event SetController(address indexed account, address indexed controller);

  event SetRecoverer(address indexed account, address indexed recoverer);

  event ChangeAccountMode(address indexed account, string mode, uint256 timestamp);

  /// @notice Mapping of Bookkeeper contract address to chain IDs, and whether they are authorized.
  mapping(address => mapping(uint256 => bool)) public bookkeepers;

  string public globalRules;

  mapping(address => string) public accountRules;

  // Accounts are in automatic mode by default, with the bundler proposing transactions.
  // Manual mode is active starting at the timestamp, inactive if value is zero.
  mapping(address => uint256) public manualMode;

  mapping(address => bool) public frozen;

  mapping(address => mapping(address => bool)) public isController; // Says if address is a controller of this Oya account.
  mapping(address => mapping(address => bool)) public isRecoverer; // Says if address is a recoverer of this Oya account.

  /**
   * @notice Construct Oya Bookkeeper contract.
   * @param _finder UMA Finder contract address.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _rules Reference to the Oya global rules.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
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
   * @notice Sets up the Oya Bookkeeper contract.
   * @param initializeParams ABI encoded parameters to initialize the contract with.
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

    emit BookkeeperDeployed(_rules);
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

  function setController(address _account, address _controller) public {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    isController[_account][_controller] = true;
    emit SetController(_account, _controller);
  }

  function setRecoverer(address _account, address _recoverer) public {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    isRecoverer[_account][_recoverer] = true;
    emit SetRecoverer(_account, _recoverer);
  }

  /**
   * @notice Sets the rules that will be used to evaluate future proposals from this account.
   * @param _rules string that outlines or references the location where the rules can be found.
   */
  function setAccountRules(address _account, string memory _rules) public {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    // Set reference to the rules for the Oya module
    require(bytes(_rules).length > 0, "Rules can not be empty");
    accountRules[_account] = _rules;
    emit SetAccountRules(_account, _rules);
  }
  
  // This function goes into manual mode. Only controllers may propose transactions for this
  // account while in manual, and controllers may not use the bundler. This is useful for
  // transactions that the bundler can not serve due to lack or liquidity or other reasons.
  // This is enforced through the global rules related to Oya proposals.
  function goManual(address _account) public {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    // add a time delay so pending bundler transactions are resolved before going manual
    manualMode[_account] = block.timestamp + 15 minutes;
    emit ChangeAccountMode(_account, "manual", manualMode[_account]);
  }

  // This function takes the account out of manual mode. Controllers may resume using the
  // bundler, and may not propose transactions of their own.
  function goAutomatic(address _account) public {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    require(manualMode[_account] > block.timestamp, "Not in manual mode");
    manualMode[_account] = 0;
    emit ChangeAccountMode(_account, "automatic", block.timestamp);
  }

  function freeze(address _account) public {
    require(isRecoverer[_account][msg.sender], "Not a recoverer");
    frozen[_account] = true;
  }

}
