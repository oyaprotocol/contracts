pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";

/// @title Bookkeeper
/// @dev Holds assets on behalf of account holders in the Oya network.
contract Bookkeeper is OptimisticProposer, Executor {

  using SafeERC20 for IERC20;

  event BookkeeperDeployed(string rules);

  event BookkeeperUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);

  event SetAccountRules(address indexed account, string accountRules);

  event SetController(address indexed account, address indexed controller);

  event SetGuardian(address indexed account, address indexed guardian);

  event RecoverAccount(address indexed account, address indexed newAccount);

  event ChangeAccountMode(address indexed account, AccountMode mode, uint256 timestamp);

  enum AccountMode { Automatic, Manual, Frozen }

  /// @notice Mapping of Bookkeeper contract address to chain IDs, and whether they are authorized.
  mapping(address => mapping(uint256 => bool)) public bookkeepers;

  mapping(address => string) public accountRules;
  mapping(address => AccountMode) public accountModes;

  // Time at which manual mode is active. 15 minute delay to switch from automatic to manual.
  // If set to 0, the account is not in manual mode.
  mapping(address => uint256) public manualModeLiveTime;

  mapping(address => mapping(address => bool)) public isController;
  mapping(address => mapping(address => bool)) public isGuardian;

  modifier notFrozen(address _account) {
    require(getCurrentMode(_account) != AccountMode.Frozen, "Account is frozen");
    _;
  }

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

  function getCurrentMode(address _account) public view returns (AccountMode) {
    AccountMode mode = accountModes[_account];
    if (mode == AccountMode.Manual && block.timestamp < manualModeLiveTime[_account]) {
      // Manual mode is scheduled but not yet active; treat as Automatic
      return AccountMode.Automatic;
    }
    return mode;
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

    // This will revert if the assertion has not been settled and can not currently be settled.
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

  function setController(address _account, address _controller) external notFrozen(_account) {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    isController[_account][_controller] = true;
    emit SetController(_account, _controller);
  }

  function setGuardian(address _account, address _guardian) external notFrozen(_account) {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    isGuardian[_account][_guardian] = true;
    emit SetGuardian(_account, _guardian);
  }

  /**
   * @notice Sets the rules that will be used to evaluate future proposals from this account.
   * @param _rules string that outlines or references the location where the rules can be found.
   */
  function setAccountRules(address _account, string memory _rules) external notFrozen(_account) {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    // Set reference to the rules for the Oya module
    require(bytes(_rules).length > 0, "Rules can not be empty");
    accountRules[_account] = _rules;
    emit SetAccountRules(_account, _rules);
  }
  
  function setAccountMode(address _account, AccountMode _mode) external {
    AccountMode currentMode = getCurrentMode(_account);

    if (_mode == AccountMode.Manual) {
      // Only the account owner or a controller can set to Manual
      require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
      // Cannot set to Manual if the account is frozen
      require(currentMode != AccountMode.Frozen, "Account is frozen");
      // Set to Manual mode with a 15-minute delay
      accountModes[_account] = AccountMode.Manual;
      manualModeLiveTime[_account] = block.timestamp + 15 minutes;
      emit ChangeAccountMode(_account, AccountMode.Manual, manualModeLiveTime[_account]);
    } else if (_mode == AccountMode.Automatic) {
      if (currentMode == AccountMode.Frozen) {
        // Only a guardian can unfreeze the account
        require(isGuardian[_account][msg.sender], "Not a guardian");
      } else {
        // Only the account owner or a controller can set to Automatic
        require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
      }
      // Set to Automatic mode immediately
      accountModes[_account] = AccountMode.Automatic;
      manualModeLiveTime[_account] = 0; // Cancel any scheduled manual mode activation
      emit ChangeAccountMode(_account, AccountMode.Automatic, block.timestamp);
    } else if (_mode == AccountMode.Frozen) {
      // Only a guardian can freeze the account
      require(isGuardian[_account][msg.sender], "Not a guardian");
      // Set to Frozen mode immediately
      accountModes[_account] = AccountMode.Frozen;
      manualModeLiveTime[_account] = 0; // Cancel any scheduled manual mode activation
      emit ChangeAccountMode(_account, AccountMode.Frozen, block.timestamp);
    } else {
      revert("Invalid mode");
    }
  }

  // Account recovery is done on the virtual chain. A proposed bundle can include account recovery
  // instructions, sweeping all virtual chain assets from a compromised account address to a new 
  // address. If the proposed recovery does not follow the global rules and account rules, the 
  // proposal will be rejected. No need for an additional function here, I think. Any funds deposited
  // from this address in the future will be assigned to the new address on the virtual chain.

}
