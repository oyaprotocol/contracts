// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.6;

// https://github.com/gnosis/zodiac/blob/master/contracts/core/Module.sol
import "@gnosis.pm/zodiac/contracts/core/Module.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./OptimisticProposer.sol";

/**
 * @title Oya Module
 * @notice A contract that allows the Oya protocol to manage transactions for a Safe account.
 */
contract OyaModule is OptimisticProposer, Module {

  using SafeERC20 for IERC20;

  event OyaModuleDeployed(address indexed owner, address indexed controller, address bookkeeper);

  FinderInterface public immutable finder; // Finder used to discover other UMA ecosystem contracts.

  /**
   * @notice Construct Oya module.
   * @param _finder UMA Finder contract address.
   * @param _controller Address of the Oya account controller.
   * @param _recoverer Address of the Oya account recovery address.
   * @param _safe Address of the Oya account Safe.
   * @param _collateral Address of the ERC20 collateral used for bonds.
   * @param _bondAmount Amount of collateral currency to make assertions for proposed transactions
   * @param _rules Reference to the rules for the Oya module.
   * @param _identifier The approved identifier to be used with the contract, compatible with Optimistic Oracle V3.
   * @param _liveness The period, in seconds, in which a proposal can be disputed.
   */
  constructor(
    address _finder,
    address _controller,
    address _recoverer,
    address _safe,
    address _collateral,
    uint256 _bondAmount,
    string memory _rules,
    bytes32 _identifier,
    uint64 _liveness
  ) {
    bytes memory initializeParams =
      abi.encode(_controller, _recoverer, _safe, _collateral, _bondAmount, _rules, _identifier, _liveness);
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
      address _recoverer,
      address _safe,
      address _collateral,
      uint256 _bondAmount,
      string memory _rules,
      bytes32 _identifier,
      uint64 _liveness
    ) = abi.decode(initializeParams, (address, address, address, address, uint256, string, bytes32, uint64));
    setCollateralAndBond(IERC20(_collateral), _bondAmount);
    setRules(_rules);
    setIdentifier(_identifier);
    setLiveness(_liveness);
    setController(_controller);
    setRecoverer(_recoverer);
    setAvatar(_safe);
    setTarget(_safe);
    transferOwnership(_safe);
    _sync();

    emit OyaModuleDeployed(_safe, avatar, target);
  }

  /**
   * @notice Sets the collateral and bond amount for proposals.
   * @param _collateral token that will be used for all bonds for the contract.
   * @param _bondAmount amount of the bond token that will need to be paid for future proposals.
   */
  function setCollateralAndBond(IERC20 _collateral, uint256 _bondAmount) public onlyOwner {
    // ERC20 token to be used as collateral (must be approved by UMA governance).
    require(_getCollateralWhitelist().isOnWhitelist(address(_collateral)), "Bond token not supported");
    collateral = _collateral;

    // Value of the bond posted for asserting the proposed transactions. If the minimum amount required by
    // Optimistic Oracle V3 is higher this contract will attempt to pull the required bond amount.
    bondAmount = _bondAmount;

    emit SetCollateralAndBond(_collateral, _bondAmount);
  }

  /**
   * @notice Sets the identifier for future proposals.
   * @param _identifier identifier to set.
   */
  function setIdentifier(bytes32 _identifier) public onlyOwner {
    // Set identifier which is used along with the rules to determine if transactions are valid.
    require(_getIdentifierWhitelist().isIdentifierSupported(_identifier), "Identifier not supported");
    identifier = _identifier;
    emit SetIdentifier(_identifier);
  }

  function setController(address _controller) public onlyOwner {
    isController[_controller] = true;
    emit SetController(_controller);
  }

  function setRecoverer(address _recoverer) public onlyOwner {
    isRecoverer[_recoverer] = true;
    emit SetRecoverer(_recoverer);
  }

  /**
   * @notice Sets the Escalation Manager for future proposals.
   * @param _escalationManager address of the Escalation Manager, can be zero to disable this functionality.
   * @dev Only the owner can call this method. The provided address must conform to the Escalation Manager interface.
   * FullPolicyEscalationManager can be used, but within the context of this contract it should be used only for
   * whitelisting of proposers and disputers since Oya module is deleting disputed proposals.
   */
  function setEscalationManager(address _escalationManager) external onlyOwner {
    require(_isContract(_escalationManager) || _escalationManager == address(0), "EM is not a contract");
    escalationManager = _escalationManager;
    emit SetEscalationManager(_escalationManager);
  }

  /**
   * @notice This caches the most up-to-date Optimistic Oracle V3.
   * @dev If a new Optimistic Oracle V3 is added and this is run between a proposal's introduction and execution, the
   * proposal will become unexecutable.
   */
  function sync() external nonReentrant {
    _sync();
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

  // Gets the address of Collateral Whitelist from the Finder.
  function _getCollateralWhitelist() internal view returns (AddressWhitelistInterface) {
    return AddressWhitelistInterface(finder.getImplementationAddress(OracleInterfaces.CollateralWhitelist));
  }

  // Gets the address of Identifier Whitelist from the Finder.
  function _getIdentifierWhitelist() internal view returns (IdentifierWhitelistInterface) {
    return IdentifierWhitelistInterface(finder.getImplementationAddress(OracleInterfaces.IdentifierWhitelist));
  }

  // Gets the address of Store contract from the Finder.
  function _getStore() internal view returns (StoreInterface) {
    return StoreInterface(finder.getImplementationAddress(OracleInterfaces.Store));
  }

  // Caches the address of the Optimistic Oracle V3 from the Finder.
  function _sync() internal {
    address newOptimisticOracleV3 = finder.getImplementationAddress(OracleInterfaces.OptimisticOracleV3);
    if (newOptimisticOracleV3 != address(optimisticOracleV3)) {
      optimisticOracleV3 = OptimisticOracleV3Interface(newOptimisticOracleV3);
      emit OptimisticOracleChanged(newOptimisticOracleV3);
    }
  }

}
