pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";

contract BundleTracker is OptimisticProposer {
  event BundleCanceled(uint256 indexed timestamp);
  event BundleProposed(uint256 indexed timestamp, string bundleData);
  event BundlerAdded(address indexed bundler);
  event BundlerRemoved(address indexed bundler);
  event BundleTrackerDeployed(address indexed bundler, string rules);

  uint256 public lastFinalizedBundle;

  mapping(bytes32 => uint256) public assertions; // Mapping of oracle assertion IDs to bundle timestamps.
  mapping(uint256 => string) public bundles; // Mapping of proposal timestamps to strings pointing to the bundle data.
  mapping(address => bool) public bundlers; // Approved bundlers

  modifier onlyBundler() {
    require(bundlers[msg.sender], "Caller is not a bundler");
    _;
  }

  constructor(
    address _finder,
    address _bundler,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules, // Oya global rules
    bytes32 _identifier,
    uint64 _liveness
  ) {
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    bytes memory initializeParams = abi.encode(_bundler, _collateral, _bondAmount, _rules, _identifier, _liveness);
    setUp(initializeParams);
  }

  function setUp(bytes memory initializeParams) public initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (
      address _bundler,
      address _collateral,
      uint256 _bondAmount,
      string memory _rules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, address, uint256, string, bytes32, uint64));
    addBundler(_bundler);
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();

    emit BundleTrackerDeployed(_bundler, _rules);
  }

  function assertionDisputedCallback(bytes32 assertionId) external override {
    // Callback to automatically delete a proposal that was disputed.
    bytes32 proposalHash = proposalHashes[assertionId];

    if (msg.sender == address(optimisticOracleV3)) {
      // Validate the assertionId through existence of non-zero proposalHash. This is the same check as in
      // deleteProposalOnUpgrade method that is called in the else branch.
      require(proposalHash != bytes32(0), "Invalid proposal hash");

      // Delete the disputed proposal and associated assertionId.
      delete assertionIds[proposalHash];
      delete proposalHashes[assertionId];
      delete bundles[assertions[assertionId]];

      emit ProposalDeleted(proposalHash, assertionId);
    } else {
      deleteProposalOnUpgrade(proposalHash);
    }
  }

  function proposeBundle(string memory _bundleData) external onlyBundler {
    // _bundleData references the offchain bundle data being proposed.
    bundles[block.timestamp] = _bundleData;
    bytes32 _assertionID = optimisticOracleV3.assertTruth(
      bytes(_bundleData),
      msg.sender, // bundler is the proposer
      address(this), // callback to the bundle tracker contract
      address(0), // no escalation manager
      liveness, // these and other oracle values set in OptimisticProposer setup
      collateral,
      bondAmount,
      identifier,
      0 // no domain id
    );
    assertions[_assertionID] = block.timestamp;
  }

  function addBundler(address _bundler) public onlyOwner {
    bundlers[_bundler] = true;
    emit BundlerAdded(_bundler);
  }

  function removeBundler(address _bundler) external onlyOwner {
    delete bundlers[_bundler];
    emit BundlerRemoved(_bundler);
  }

  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    // If the assertion was true, then the data assertion is resolved.
    if (assertedTruthfully) lastFinalizedBundle = assertions[assertionId];
  }
}