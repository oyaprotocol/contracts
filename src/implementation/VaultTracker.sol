pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";

import "./OptimisticProposer.sol";

// Do I need to block setting of escalation manager by the owner?

contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  event VaultTrackerDeployed(string rules);
  event ChainFrozen();
  event ChainUnfrozen();
  event VaultFrozen(address indexed vault);
  event VaultUnfrozen(address indexed vault);
  event SetVaultRules(address indexed vault, string vaultRules);
  event SetBlockProposer(address indexed vault, address indexed blockProposer, uint256 liveTime);
  event SetController(address indexed vault, address indexed controller);
  event SetGuardian(address indexed vault, address indexed guardian);

  address _cat; // Crisis Action Team can trigger Oya chain freeze
  bool public chainFrozen = false;

  mapping(address => string) public vaultRules;
  mapping(address => bool) public vaultFrozen;
  mapping(address => address) public blockProposers;
  mapping(address => mapping(address => bool)) public isController;
  mapping(address => mapping(address => bool)) public isGuardian;

  // Timestamp at which proposer change is active. 15 minute delay to switch.
  mapping(address => uint256) public proposerChangeLiveTime;

  modifier notFrozen(address _vault) {
    require(vaultFrozen[_vault] == false, "Vault is frozen");
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
    require(chainFrozen == false, "Oya chain is currently frozen");

    bytes32 proposalHash = keccak256(abi.encode(transactions));
    bytes32 assertionId = assertionIds[proposalHash];
    
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

  function setCat(address _catAddress) external onlyOwner {
    _cat = _catAddress;
  }

  // Many setter functions should be possible to set through executing a proposal instead of
  // using a controller address
  function setBlockProposer(address _vault, address _blockProposer) external notFrozen(_vault) {
    require(msg.sender == _vault || isController[_vault][msg.sender], "Not a controller");
    uint256 _liveTime = block.timestamp + 15 minutes;
    proposerChangeLiveTime[_vault] = _liveTime;
    blockProposers[_vault] = _blockProposer;
    emit SetBlockProposer(_vault, _blockProposer, _liveTime);
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

  function freezeVault(address _vault) external notFrozen(_vault) {
    // Only a guardian can freeze the vault
    require(isGuardian[_vault][msg.sender], "Not a guardian");
    vaultFrozen[_vault] = true;
    emit VaultFrozen(_vault);
  }

  function unfreezeVault(address _vault) external {
    // Only a guardian can unfreeze the vault
    require(isGuardian[_vault][msg.sender], "Not a guardian");
    vaultFrozen[_vault] = false;
    emit VaultUnfrozen(_vault);
  }

  function freezeChain() external onlyCat {
    chainFrozen = true;
    emit ChainFrozen();
  }

  function unfreezeChain() external onlyCat {
    chainFrozen = false;
    emit ChainUnfrozen();
  }
}
