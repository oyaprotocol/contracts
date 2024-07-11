// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.6;

import "@gnosis.pm/zodiac/contracts/core/Module.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../OptimisticProposer.sol";

/**
 * @title Oya Module
 * @notice A contract that allows the Oya protocol to manage transactions for a Safe account.
 */
contract OyaModule is OptimisticProposer, Module {

  using SafeERC20 for IERC20;

  event OyaModuleDeployed(address indexed safe, address indexed avatar, address indexed target);

  event SetAccountRules(string accountRules);

  event SetGlobalRules(string globalRules);

  event SetController(address indexed controller);

  event SetRecoverer(address indexed guardian);

  event ChangeAccountMode(string mode, uint256 timestamp);

  string public accountRules;
  string public globalRules;

  // Accounts are in automatic mode by default, with the bundler proposing transactions.
  // Manual mode is active starting at the timestamp, inactive if value is zero.
  uint256 public manualMode = 0;

  bool public frozen = false;

  mapping(address => bool) public isController; // Says if address is a controller of this Oya account.
  mapping(address => bool) public isRecoverer; // Says if address is a guardian of this Oya account.

  /**
   * @notice Construct Oya module.
   * @param _finder UMA Finder contract address.
   * @param _controller Address of the Oya account controller.
   * @param _guardian Address of the Oya account recovery address.
   * @param _safe Address of the Oya account Safe.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _accountRules Reference to the rules for this specific Oya account.
   * @param _globalRules Reference to the global rules for the Oya protocol.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
   */
  constructor(
    address _finder,
    address _controller,
    address _guardian,
    address _safe,
    address _collateral,
    uint256 _bondAmount,
    string memory _accountRules,
    string memory _globalRules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    bytes memory initializeParams = abi.encode(
      _controller, _guardian, _safe, _collateral, _bondAmount, _accountRules, _globalRules, _identifier, _liveness
    );
    require(_finder != address(0), "Finder address can not be empty");
    finder = FinderInterface(_finder);
    setUp(initializeParams);
  }

  /**
   * @notice Sets up the Oya module.
   * @param initializeParams ABI encoded parameters to initialize the module with.
   * @dev This method can be called only either by the constructor or as part of first time initialization when
   * cloning the module.
   */
  function setUp(bytes memory initializeParams) public override initializer {
    _startReentrantGuardDisabled();
    __Ownable_init();
    (
      address _controller,
      address _guardian,
      address _safe,
      address _collateral,
      uint256 _bondAmount,
      string memory _accountRules,
      string memory _globalRules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, address, address, address, uint256, string, string, bytes32, uint64));
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setAccountRules(_accountRules);
    setGlobalRules(_globalRules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    setController(_controller);
    setRecoverer(_guardian);
    setAvatar(_safe);
    setTarget(_safe);
    transferOwnership(_safe);
    _sync();

    emit OyaModuleDeployed(_safe, avatar, target);
  }

  function setController(address _controller) public onlyOwner {
    isController[_controller] = true;
    emit SetController(_controller);
  }

  function setRecoverer(address _guardian) public onlyOwner {
    isRecoverer[_guardian] = true;
    emit SetRecoverer(_guardian);
  }

  /**
   * @notice Sets the rules that will be used to evaluate future proposals from this account.
   * @param _rules string that outlines or references the location where the rules can be found.
   */
  function setAccountRules(string memory _rules) public onlyOwner {
    // Set reference to the rules for the Oya module
    require(bytes(_rules).length > 0, "Rules can not be empty");
    accountRules = _rules;
    emit SetAccountRules(_rules);
  }

  /**
   * @notice Sets the global rules that govern all accounts in this protocol.
   * @param _rules string that outlines or references the location where the rules can be found.
   */
  function setGlobalRules(string memory _rules) public onlyOwner {
    // Set reference to the rules for the Oya module
    require(bytes(_rules).length > 0, "Rules can not be empty");
    globalRules = _rules;
    emit SetGlobalRules(_rules);
  }

  /**
   * @notice Executes an approved proposal.
   * @param transactions the transactions being executed. These must exactly match those that were proposed.
   */
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

    // There is no need to check the assertion result as this point can be reached only for non-disputed assertions.
    // This will revert if the assertion has not been settled and can not currently be settled.
    optimisticOracleV3.settleAndGetAssertionResult(assertionId);

    // Execute the transactions.
    for (uint256 i = 0; i < transactions.length; i++) {
      Transaction memory transaction = transactions[i];

      require(
        exec(transaction.to, transaction.value, transaction.data, transaction.operation),
        "Failed to execute transaction"
      );
      emit TransactionExecuted(proposalHash, assertionId, i);
    }

    emit ProposalExecuted(proposalHash, assertionId);
  }

  // This function goes into manual mode. Only controllers may propose transactions for this
  // account while in manual, and controllers may not use the bundler. This is useful for
  // transactions that the bundler can not serve due to lack or liquidity or other reasons.
  // This is enforced through the global rules related to Oya proposals.
  function goManual() public {
    require(isController[msg.sender], "Not a controller");
    // add a time delay so pending bundler transactions are resolved before going manual
    manualMode = block.timestamp + 15 minutes;
    emit ChangeAccountMode("manual", manualMode);
  }

  // This function takes the account out of manual mode. Controllers may resume using the
  // bundler, and may not propose transactions of their own.
  function goAutomatic() public {
    require(isController[msg.sender], "Not a controller");
    require(manualMode > block.timestamp, "Not in manual mode");
    manualMode = 0;
    emit ChangeAccountMode("automatic", block.timestamp);
  }

  function freeze() public {
    require(isRecoverer[msg.sender], "Not a guardian");
    frozen = true;
  }

}
