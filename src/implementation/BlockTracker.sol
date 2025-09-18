pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";

/**
 * @title Block Tracker
  * @notice Extends OptimisticProposer for timestamped block data proposals
 * @dev Specialized contract for tracking and validating OyaProtocol 'block' data
 *
 * @custom:invariant lastFinalizedTimestamp <= block.timestamp
 * @custom:invariant For any stored assertionId, assertionTimestamps[assertionId] equals the proposal timestamp
 */
contract BlockTracker is OptimisticProposer {
  /// @notice Emitted when a new block is proposed for validation
  /// @param timestamp The timestamp when the block was proposed
  /// @param blockProposer Address that proposed the block data
  /// @param blockData The block data being validated
  event BlockProposed(uint256 indexed timestamp, address indexed blockProposer, string blockData);

  /// @notice Emitted when the BlockTracker contract is deployed and initialized
  /// @param rules The protocol rules used for block validation
  event BlockTrackerDeployed(string rules);

  /// @notice Timestamp of the last block that was finalized through optimistic validation
  /// @dev Updated when assertions resolve truthfully
  uint256 public lastFinalizedTimestamp;

  /// @notice Maps assertion IDs to their proposal timestamps
  /// @dev Used to track when blocks were proposed for validation
  mapping(bytes32 => uint256) public assertionTimestamps;

  /// @notice Maps assertion IDs to their proposers
  /// @dev Tracks who proposed each block for accountability
  mapping(bytes32 => address) public assertionProposer;

  /// @notice Maps timestamps and proposers to their proposed block data
  /// @dev Retrieval requires both the proposal timestamp and proposer address
  mapping(uint256 => mapping(address => string)) public blocks;

  /**
   * @notice Initializes the BlockTracker contract
   * @param _finder Address of the UMA Finder contract
   * @param _collateral Address of the collateral ERC20 token
   * @param _bondAmount Base bond amount for block proposals
   * @param _rules Protocol rules for block validation
   * @param _identifier UMA identifier for proposal validation
   * @param _liveness Dispute window for block proposals
   * @dev Calls setUp with encoded parameters for proxy compatibility
   */
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

  /**
   * @notice Initializes the contract state with provided parameters
   * @param initializeParams Encoded initialization parameters
   * @dev Decodes and sets up collateral, rules, identifier, and liveness
   * @custom:events Emits BlockTrackerDeployed event
   */
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

  /**
   * @notice Proposes block data for optimistic validation
   * @param _blockData String representation of block data to be validated
   * @dev Creates an assertion for block data validity at current timestamp. The claim asserted to
   *      the Optimistic Oracle V3 is the raw `_blockData` bytes (no additional keys/rules encoding).
   *
   * Process:
   * 1. Stores block data with timestamp and proposer
   * 2. Creates optimistic assertion for data validity
   * 3. Tracks assertion for later resolution
   *
   * @custom:events Emits BlockProposed with timestamp and proposer details
   * @custom:security Requires the proposer to approve at least `bondAmount` collateral for this contract.
   *                  The oracle enforces a minimum bond; if `bondAmount` is below the minimum, the
   *                  assertion will revert unless configuration is adjusted accordingly.
   */
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

  /**
   * @notice Callback for resolved block data assertions
   * @param assertionId The ID of the resolved assertion
   * @param assertedTruthfully Whether the block data was validated as truthful
   * @dev Updates lastFinalizedTimestamp if assertion resolved truthfully
   * @custom:security Only callable by the Optimistic Oracle V3 contract
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    if (assertedTruthfully) lastFinalizedTimestamp = assertionTimestamps[assertionId];
  }

}