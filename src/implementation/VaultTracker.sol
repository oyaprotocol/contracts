pragma solidity ^0.8.6;

import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import "./OptimisticProposer.sol";

contract VaultTracker is OptimisticProposer, Executor {
  using SafeERC20 for IERC20;

  event VaultTrackerDeployed(string rules);
  event ChainFrozen();
  event ChainUnfrozen();
  event VaultCreated(uint256 indexed vaultId, address indexed controller);
  event VaultFrozen(uint256 indexed vaultId);
  event VaultUnfrozen(uint256 indexed vaultId);
  event SetVaultRules(uint256 indexed vaultId, string vaultRules);
  event SetBlockProposer(uint256 indexed vaultId, address indexed blockProposer, uint256 liveTime);
  event SetController(uint256 indexed vaultId, address indexed controller);
  event SetGuardian(uint256 indexed vaultId, address indexed guardian);

  address _cat;
  bool public chainFrozen = false;
  uint256 public nextVaultId;

  mapping(uint256 => string) public vaultRules;
  mapping(uint256 => bool) public vaultFrozen;
  mapping(uint256 => address) public blockProposers;
  mapping(uint256 => mapping(address => bool)) public isController;
  mapping(uint256 => mapping(address => bool)) public isGuardian;

  modifier notFrozen(uint256 vaultId) {
    require(!vaultFrozen[vaultId], "Vault is frozen");
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

  function createVault(address _controller) external returns (uint256) {
    nextVaultId++;
    _setController(nextVaultId, _controller);
    emit VaultCreated(nextVaultId, _controller);
    return nextVaultId;
  }

  function executeProposal(Transaction[] memory transactions) external nonReentrant {
    require(!chainFrozen, "Oya chain is currently frozen");
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

  function setCat(address _catAddress) external onlyOwner {
    _cat = _catAddress;
  }

  function setBlockProposer(uint256 _vaultId, address _blockProposer) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    uint256 _liveTime = block.timestamp + 3 hours;
    blockProposers[_vaultId] = _blockProposer;
    emit SetBlockProposer(_vaultId, _blockProposer, _liveTime);
  }

  function setController(uint256 _vaultId, address _controller) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    _setController(_vaultId, _controller);
  }

  function setGuardian(uint256 _vaultId, address _guardian) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    isGuardian[_vaultId][_guardian] = true;
    emit SetGuardian(_vaultId, _guardian);
  }

  function removeGuardian(uint256 _vaultId, address _guardian) external {
    require(msg.sender == address(this), "Guardians must be removed by a proposal");
    isGuardian[_vaultId][_guardian] = false;
    emit SetGuardian(_vaultId, _guardian);
  }

  function setVaultRules(uint256 _vaultId, string memory _rules) external notFrozen(_vaultId) {
    require(msg.sender == address(this) || isController[_vaultId][msg.sender], "Not a controller");
    require(bytes(_rules).length > 0, "Rules can not be empty");
    vaultRules[_vaultId] = _rules;
    emit SetVaultRules(_vaultId, _rules);
  }

  function freezeVault(uint256 _vaultId) external notFrozen(_vaultId) {
    require(isGuardian[_vaultId][msg.sender], "Not a guardian");
    vaultFrozen[_vaultId] = true;
    emit VaultFrozen(_vaultId);
  }

  function unfreezeVault(uint256 _vaultId) external {
    require(msg.sender == address(this) || isGuardian[_vaultId][msg.sender], "Not a guardian");
    vaultFrozen[_vaultId] = false;
    emit VaultUnfrozen(_vaultId);
  }

  function freezeChain() external onlyCat {
    chainFrozen = true;
    emit ChainFrozen();
  }

  function unfreezeChain() external onlyCat {
    chainFrozen = false;
    emit ChainUnfrozen();
  }

  function _setController(uint256 _vaultId, address _controller) internal {
    isController[_vaultId][_controller] = true;
    emit SetController(_vaultId, _controller);
  }
}
