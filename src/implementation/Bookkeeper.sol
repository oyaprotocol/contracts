pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";

contract Bookkeeper is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  enum AccountMode { Automatic, Manual, Frozen }

  event AddBundler(address indexed bundler);
  event BookkeeperDeployed(string rules);
  event BookkeeperUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);
  event ChangeAccountMode(address indexed account, AccountMode mode, uint256 timestamp);
  event RemoveBundler(address indexed bundler);
  event SetAccountRules(address indexed account, string accountRules);
  event SetBundler(address indexed account, address indexed bundler);
  event SetController(address indexed account, address indexed controller);
  event SetGuardian(address indexed account, address indexed guardian);

  address[] public bundlerList;
  mapping(address => mapping(uint256 => bool)) public bookkeepers;
  mapping(address => string) public accountRules;
  mapping(address => AccountMode) public accountModes;
  mapping(address => address) public bundlers;
  mapping(address => mapping(address => bool)) public isController;
  mapping(address => mapping(address => bool)) public isGuardian;

  // Timestamp at which manual mode is active. 15 minute delay to switch from automatic to manual.
  // If set to 0, the account is not in manual mode.
  mapping(address => uint256) public manualModeLiveTime;

  modifier notFrozen(address _account) {
    require(getCurrentMode(_account) != AccountMode.Frozen, "Account is frozen");
    _;
  }

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

  function addBundler(address _bundler) external onlyOwner {
    require(bundlers[_bundler] == address(0), "Bundler already exists");
    bundlers[_bundler] = _bundler;
    bundlerList.push(_bundler);
    emit AddBundler(_bundler);
  }

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

  function getCurrentMode(address _account) public view returns (AccountMode) {
    AccountMode mode = accountModes[_account];
    if (mode == AccountMode.Manual && block.timestamp < manualModeLiveTime[_account]) {
      // Manual mode is scheduled but not yet active; treat as Automatic
      return AccountMode.Automatic;
    }
    return mode;
  }

  function RemoveBundler(bundler) external onlyOwner {
    require(bundlers[bundler] != address(0), "Bundler does not exist");
    delete bundlers[bundler];
    emit RemoveBundler(bundler);
  }

  function setBundler(address _account, address _bundler) external notFrozen(_account) {
    require(msg.sender == _account || isController[_account][msg.sender], "Not a controller");
    bundlers[_account] = _bundler;
    emit SetBundler(_account, _bundler);
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

  function updateBookkeeper(address _contractAddress, uint256 _chainId, bool _isApproved) external onlyOwner {
    bookkeepers[_contractAddress][_chainId] = _isApproved;
    emit BookkeeperUpdated(_contractAddress, _chainId, _isApproved);
  }
}
