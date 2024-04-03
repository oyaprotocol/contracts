// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.6;

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

}
