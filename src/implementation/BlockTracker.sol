pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";

contract BlockTracker is OptimisticProposer {
  event BlockCanceled(uint256 indexed timestamp);
  event BlockProposed(uint256 indexed timestamp, address indexed blockr, string blockData);
  event BlockrAdded(address indexed blockr);
  event BlockrRemoved(address indexed blockr);
  event BlockTrackerDeployed(address indexed blockr, string rules);

  uint256 public lastFinalizedBlock;

  mapping(bytes32 => uint256) public assertions; // Mapping of oracle assertion IDs to block timestamps.
  mapping(uint256 => string) public blocks; // Mapping of proposal timestamps to strings pointing to the block data.
  // maybe we only have one blockr after all?
  mapping(address => bool) public blockrs; // Approved blockrs

  modifier onlyBlockProposer() {
    require(blockrs[msg.sender], "Caller is not a blockr");
    _;
  }

  constructor(
    address _finder,
    address _blockr,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules, // Oya global rules
    bytes32 _identifier,
    uint64 _liveness
  ) {
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    bytes memory initializeParams = abi.encode(_blockr, _collateral, _bondAmount, _rules, _identifier, _liveness);
    setUp(initializeParams);
  }

  function setUp(bytes memory initializeParams) public initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (
      address _blockr,
      address _collateral,
      uint256 _bondAmount,
      string memory _rules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, address, uint256, string, bytes32, uint64));
    addBlockr(_blockr);
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();

    emit BlockTrackerDeployed(_blockr, _rules);
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
      delete blocks[assertions[assertionId]];

      emit ProposalDeleted(proposalHash, assertionId);
    } else {
      deleteProposalOnUpgrade(proposalHash);
    }
  }

  function proposeBlock(string memory _blockData) external onlyBlockProposer {
    // _blockData references the offchain block data being proposed.
    blocks[block.timestamp] = _blockData;
    bytes32 _assertionID = optimisticOracleV3.assertTruth(
      bytes(_blockData),
      msg.sender, // blockr is the proposer
      address(this), // callback to the block tracker contract
      address(0), // no escalation manager
      liveness, // these and other oracle values set in OptimisticProposer setup
      collateral,
      bondAmount,
      identifier,
      0 // no domain id
    );
    assertions[_assertionID] = block.timestamp;
    emit BlockProposed(block.timestamp, msg.sender, _blockData);
  }

  function addBlockr(address _blockr) public onlyOwner {
    blockrs[_blockr] = true;
    emit BlockrAdded(_blockr);
  }

  function removeBlockr(address _blockr) external onlyOwner {
    delete blockrs[_blockr];
    emit BlockrRemoved(_blockr);
  }

  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    // If the assertion was true, then the data assertion is resolved.
    if (assertedTruthfully) lastFinalizedBlock = assertions[assertionId];
  }
}