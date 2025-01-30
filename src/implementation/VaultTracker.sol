pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";

contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  enum VaultMode { Automatic, Manual, Frozen }

  event VaultTrackerDeployed(string rules);
  event VaultTrackerUpdated(address indexed contractAddress, uint256 indexed chainId, bool isApproved);
  event ChangeVaultMode(address indexed vault, VaultMode mode, uint256 timestamp);
  event OyaShutdown();
  event SetVaultRules(address indexed vault, string vaultRules);
  event SetBlockProposer(address indexed vault, address indexed blockProposer);
  event SetController(address indexed vault, address indexed controller);
  event SetGuardian(address indexed vault, address indexed guardian);

  address _cat; // Crisis Action Team multisig can trigger Oya shutdown
  // emergency shutdown drops Oya virtual chain into being a simpler zk chain, with no natural lang?
  bool public oyaShutdown = false;
  bytes public finalState;

  mapping(address => string) public vaultRules;
  mapping(address => VaultMode) public vaultModes;
  mapping(address => address) public blockProposers;
  mapping(address => mapping(address => bool)) public isController;
  mapping(address => mapping(address => bool)) public isGuardian;

  // Timestamp at which manual mode is active. 15 minute delay to switch from automatic to manual.
  // If set to 0, the vault is not in manual mode.
  mapping(address => uint256) public manualModeLiveTime;

  modifier notFrozen(address _vault) {
    require(getCurrentMode(_vault) != VaultMode.Frozen, "Vault is frozen");
    _;
  }

  modifier onlyCat() {
    require(msg.sender == _cat, "Only the CAT can trigger Oya shutdown");
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

    emit VaultTrackerDeployed(_rules);
  }

  function executeProposal(Transaction[] memory transactions) external nonReentrant {
    require(oyaShutdown == false, "Oya virtual chain is shut down, please withdraw your funds");

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

  function getCurrentMode(address _vault) public view returns (VaultMode) {
    VaultMode mode = vaultModes[_vault];
    if (mode == VaultMode.Manual && block.timestamp < manualModeLiveTime[_vault]) {
      // Manual mode is scheduled but not yet active; treat as Automatic
      return VaultMode.Automatic;
    }
    return mode;
  }

  function setBlockProposer(address _vault, address _blockProposer) external notFrozen(_vault) {
    require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
    authorizedBlockProposers[_blockProposer] = true;
    emit SetBlockProposer(_vault, _blockProposer);
  }

  function setController(address _vault, address _controller) external notFrozen(_vault) {
    require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
    isController[_vault][_controller] = true;
    emit SetController(_vault, _controller);
  }

  function setGuardian(address _vault, address _guardian) external notFrozen(_vault) {
    require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
    isGuardian[_vault][_guardian] = true;
    emit SetGuardian(_vault, _guardian);
  }

  function setVaultRules(address _vault, string memory _rules) external notFrozen(_vault) {
    require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
    // Set reference to the rules for the Oya module
    require(bytes(_rules).length > 0, "Rules can not be empty");
    vaultRules[_vault] = _rules;
    emit SetVaultRules(_vault, _rules);
  }
  
  function setVaultMode(address _vault, VaultMode _mode) external {
    VaultMode currentMode = getCurrentMode(_vault);

    if (_mode == VaultMode.Manual) {
      // Only the vault owner or a controller can set to Manual
      require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
      // Cannot set to Manual if the vault is frozen
      require(currentMode != VaultMode.Frozen, "Vault is frozen");
      // Set to Manual mode with a 15-minute delay
      vaultModes[_vault] = VaultMode.Manual;
      manualModeLiveTime[_vault] = block.timestamp + 15 minutes;
      emit ChangeVaultMode(_vault, VaultMode.Manual, manualModeLiveTime[_vault]);
    } else if (_mode == VaultMode.Automatic) {
      if (currentMode == VaultMode.Frozen) {
        // Only a guardian can unfreeze the vault
        require(isGuardian[_vault][msg.sender], "Not a guardian");
      } else {
        // Only the vault owner or a controller can set to Automatic
        require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
      }
      // Set to Automatic mode immediately
      vaultModes[_vault] = VaultMode.Automatic;
      manualModeLiveTime[_vault] = 0; // Cancel any scheduled manual mode activation
      emit ChangeVaultMode(_vault, VaultMode.Automatic, block.timestamp);
    } else if (_mode == VaultMode.Frozen) {
      // Only a guardian can freeze the vault
      require(isGuardian[_vault][msg.sender], "Not a guardian");
      // Set to Frozen mode immediately
      vaultModes[_vault] = VaultMode.Frozen;
      manualModeLiveTime[_vault] = 0; // Cancel any scheduled manual mode activation
      emit ChangeVaultMode(_vault, VaultMode.Frozen, block.timestamp);
    } else {
      revert("Invalid mode");
    }
  }

  function shutdownOya(bytes _finalState /* pass in merkle root of last good virtual chain state? */) external onlyCat {
    finalState = _finalState;
    // need to check that final state matches merkle root of last good virtual chain state
    oyaShutdown = true;
    emit OyaShutdown();
  }

  function withdrawFungibleTokenAfterShutdown(address _token, address _to) external {
    require(oyaShutdown, "Oya is not shutdown");
    // need to look at a merkle root of the last good virtual chain state to get balance to check
    if (_token == address(0)) {
      payable(_to).transfer(tokenId);
    } else {
      IERC20(_token).safeTransfer(_to, tokenId);
    }
  }

  function withdrawNFTAfterShutdown(address _token, uint256 _tokenId, address _to) external {
    require(oyaShutdown, "Oya is not shutdown");
    // need to look at a merkle root of the last good virtual chain state to get balance to check
    IERC721(_token).safeTransferFrom(address(this), _to, _tokenId);
  }
}
