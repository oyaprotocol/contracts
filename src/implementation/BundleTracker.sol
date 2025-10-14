pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Bundle Tracker
 * @notice Extends OptimisticProposer for timestamped bundle data proposals
 * @dev Specialized contract for tracking and validating OyaProtocol 'bundle' data
 *
 * @custom:invariant lastFinalizedTimestamp <= block.timestamp
 * @custom:invariant For any stored assertionId, assertionTimestamps[assertionId] equals the proposal timestamp
 */
contract BundleTracker is OptimisticProposer {
  using SafeERC20 for IERC20;

  /// @notice Emitted when a new bundle is proposed for validation
  /// @param timestamp The timestamp when the bundle was proposed
  /// @param bundleProposer Address that proposed the bundle data
  /// @param bundleData The bundle data being validated
  event BundleProposed(uint256 indexed timestamp, address indexed bundleProposer, string bundleData);

  /// @notice Emitted when the BundleTracker contract is deployed and initialized
  /// @param rules The protocol rules used for bundle validation
  event BundleTrackerDeployed(string rules);

  /// @notice Timestamp of the last bundle that was finalized through optimistic validation
  /// @dev Updated when assertions resolve truthfully
  uint256 public lastFinalizedTimestamp;

  /// @notice Maps assertion IDs to their proposal timestamps
  /// @dev Used to track when bundles were proposed for validation
  mapping(bytes32 => uint256) public assertionTimestamps;

  /// @notice Maps assertion IDs to their proposers
  /// @dev Tracks who proposed each bundle for accountability
  mapping(bytes32 => address) public assertionProposer;

  /// @notice Maps timestamps and proposers to their proposed bundle data
  /// @dev Retrieval requires both the proposal timestamp and proposer address
  mapping(uint256 => mapping(address => string)) public bundles;

  /**
   * @notice Initializes the BundleTracker contract
   * @param _finder Address of the UMA Finder contract
   * @param _collateral Address of the collateral ERC20 token
   * @param _bondAmount Base bond amount for bundle proposals
   * @param _rules Protocol rules for bundle validation
   * @param _identifier UMA identifier for proposal validation
   * @param _liveness Dispute window for bundle proposals
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
   * @custom:events Emits BundleTrackerDeployed event
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

    emit BundleTrackerDeployed(_rules);
  }

  /**
   * @notice Proposes bundle data for optimistic validation
   * @param _bundleData String representation of bundle data to be validated
   * @dev Creates an assertion for bundle data validity at current timestamp. The claim asserted to
   *      the Optimistic Oracle V3 is the raw `_bundleData` bytes (no additional keys/rules encoding).
   *
   * Process:
   * 1. Stores bundle data with timestamp and proposer
   * 2. Creates optimistic assertion for data validity
   * 3. Tracks assertion for later resolution
   *
   * @custom:events Emits BundleProposed with timestamp and proposer details
   * @custom:security Requires the proposer to approve at least `bondAmount` collateral for this contract.
   *                  The oracle enforces a minimum bond; if `bondAmount` is below the minimum, the
   *                  assertion will revert unless configuration is adjusted accordingly.
   */
  function proposeBundle(string memory _bundleData) external {
    address proposer = msg.sender;
    bundles[block.timestamp][proposer] = _bundleData;

    uint256 totalBond = getProposalBond();
    if (totalBond > 0) {
      collateral.safeTransferFrom(proposer, address(this), totalBond);
      collateral.safeIncreaseAllowance(address(optimisticOracleV3), totalBond);
    }

    bytes32 _assertionID = optimisticOracleV3.assertTruth(
      bytes(_bundleData),
      proposer,
      address(this), // callback to the bundle tracker contract
      address(0), // no escalation manager
      liveness, // these and other oracle values set in OptimisticProposer setup
      collateral,
      totalBond,
      identifier,
      0
    );

    assertionProposer[_assertionID] = proposer;
    assertionTimestamps[_assertionID] = block.timestamp;

    emit BundleProposed(block.timestamp, msg.sender, _bundleData);
  }

  /**
   * @notice Callback for resolved bundle data assertions
   * @param assertionId The ID of the resolved assertion
   * @param assertedTruthfully Whether the bundle data was validated as truthful
   * @dev Updates lastFinalizedTimestamp if assertion resolved truthfully
   * @custom:security Only callable by the Optimistic Oracle V3 contract
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    if (assertedTruthfully) lastFinalizedTimestamp = assertionTimestamps[assertionId];
  }

}