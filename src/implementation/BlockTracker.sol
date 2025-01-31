pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";

contract BlockTracker is OptimisticProposer {
  event BlockProposed(uint256 indexed timestamp, address indexed blockProposer, string blockData);
  event BlockTrackerDeployed(string rules);

  uint256 public lastFinalizedBlock;

  mapping(bytes32 => uint256) public assertionTimestamps;
  mapping(bytes32 => address) public assertionProposer;

  mapping(uint256 => mapping(address => string)) public blocks; // proposal timestamp => proposer => pointer to the block data

  constructor(
    address _finder,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules, // Oya global rules
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
    (
      address _collateral,
      uint256 _bondAmount,
      string memory _rules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, uint256, string, bytes32, uint64));
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    _sync();

    emit BlockTrackerDeployed(_rules);
  }

  function proposeBlock(string memory _blockData) external {
    blocks[block.timestamp][msg.sender] = _blockData;

    bytes32 _assertionID = optimisticOracleV3.assertTruth(
      bytes(_blockData),
      msg.sender,
      address(this), // callback to the block tracker contract
      address(0), // no escalation manager
      liveness, // these and other oracle values set in OptimisticProposer setup
      collateral,
      bondAmount,
      identifier,
      0
    );

    assertionProposer[_assertionID] = msg.sender;
    assertionTimestamps[_assertionID] = block.timestamp;

    emit BlockProposed(block.timestamp, msg.sender, _blockData);
  }

  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    if (assertedTruthfully) lastFinalizedBlock = assertionTimestamps[assertionId];
  }

}