pragma solidity ^0.8.6;

import "./OptimisticProposer.sol";

/// @title BundleTracker
/// @dev Allows for adding and removing bundlers, and proposing, finalizing, and canceling bundles.
contract BundleTracker is OptimisticProposer {

  event BundleTrackerDeployed(address indexed bundler, string rules);

  event BundleProposed(uint256 indexed timestamp, string bundleData);

  event BundleCanceled(uint256 indexed timestamp);

  event BundlerAdded(address indexed bundler);

  event BundlerRemoved(address indexed bundler);

  /// @notice The proposal timestamp of the most recently finalized bundle.
  uint256 public lastFinalizedBundle;

  /// @notice Mapping of proposal block timestamps to strings pointing to the bundle data.
  mapping(uint256 => string) public bundles;

  /// @notice Mapping of oracle assertion IDs to bundle timestamps.
  mapping(bytes32 => uint256) public assertions;

  /// @notice Addresses of approved bundlers.
  mapping(address => bool) public bundlers;

  /// @dev Restricts function access to only approved bundlers.
  modifier onlyBundler() {
    require(bundlers[msg.sender], "Caller is not a bundler");
    _;
  }

  /**
   * @notice Construct Oya BundleTracker contract.
   * @param _finder UMA Finder contract address.
   * @param _bundler Address of the initial bundler for the Bookkeeper contract.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _rules Reference to the Oya global rules.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
   */
  constructor(
    address _finder,
    address _bundler,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    bytes memory initializeParams = abi.encode(_bundler, _collateral, _bondAmount, _rules, _identifier, _liveness);
    setUp(initializeParams);
  }

  /**
   * @notice Sets up the Oya BundleTracker contract.
   * @param initializeParams ABI encoded parameters to initialize the module with.
   */
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

  /// @notice Proposes a new bundle of transactions.
  /// @dev Only callable by an approved bundler.
  /// @dev This function will call the optimistic oracle for bundle verification.
  /// @param _bundleData A reference to the offchain bundle data being proposed.
  function proposeBundle(string memory _bundleData) external onlyBundler {
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

  /// @notice Cancels a proposed bundle.
  /// @dev Only callable by an approved bundler.
  /// @dev They may cancel a bundle if they make an error, to propose a new bundle.
  /// @param _bundleTimestamp The proposal timestamp of the bundle to cancel.
  function cancelBundle(uint256 _bundleTimestamp) external onlyBundler {
    delete bundles[_bundleTimestamp];
  }

  /// @notice Adds a new bundler.
  /// @dev Only callable by the contract owner. Bundlers are added by protocol governance.
  /// @param _bundler The address to grant bundler permissions to.
  function addBundler(address _bundler) public onlyOwner {
    bundlers[_bundler] = true;
    emit BundlerAdded(_bundler);
  }

  /// @notice Removes a bundler.
  /// @dev Only callable by the contract owner. Bundlers are removed by protocol governance.
  /// @param _bundler The address to revoke bundler permissions from.
  function removeBundler(address _bundler) external onlyOwner {
    delete bundlers[_bundler];
    emit BundlerRemoved(_bundler);
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved.
   * @dev This is not implemented by the inherited Optimistic Proposer, but we want it here.
   * @param assertionId The identifier of the assertion that was resolved.
   * @param assertedTruthfully Whether the assertion was resolved as truthful or not.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) public override {
    require(msg.sender == address(optimisticOracleV3));
    // If the assertion was true, then the data assertion is resolved.
    if (assertedTruthfully) lastFinalizedBundle = assertions[assertionId];
  }

}
