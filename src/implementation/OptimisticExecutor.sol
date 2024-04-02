pragma solidity ^0.8.6;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OptimisticExecutor {

  using SafeERC20 for IERC20;

  event TransactionsProposed(
    address indexed proposer,
    uint256 indexed proposalTime,
    bytes32 indexed assertionId,
    Proposal proposal,
    bytes32 proposalHash,
    bytes explanation,
    string rules,
    uint256 challengeWindowEnds
  );

  event TransactionExecuted(
    bytes32 indexed proposalHash, bytes32 indexed assertionId, uint256 indexed transactionIndex
  );

  event ProposalExecuted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  event ProposalDeleted(bytes32 indexed proposalHash, bytes32 indexed assertionId);

  event SetCollateralAndBond(IERC20 indexed collateral, uint256 indexed bondAmount);

  event SetRules(string rules);

  event SetLiveness(uint64 indexed liveness);

  event SetIdentifier(bytes32 indexed identifier);

  event SetEscalationManager(address indexed escalationManager);

  event OptimisticOracleChanged(address indexed newOptimisticOracleV3);

  event SetController(address indexed controller);

  event SetBookkeeper(address indexed bookkeeper);

  event SetRecoverer(address indexed recoverer);

  // Keys for assertion claim data.
  bytes public constant PROPOSAL_HASH_KEY = "proposalHash";
  bytes public constant EXPLANATION_KEY = "explanation";
  bytes public constant RULES_KEY = "rules";

  // Struct for a proposed transaction.
  struct Transaction {
    address to; // The address to which the transaction is being sent.
    Enum.Operation operation; // Operation type of transaction: 0 == call, 1 == delegate call.
    uint256 value; // The value, in wei, to be sent with the transaction.
    bytes data; // The data payload to be sent in the transaction.
  }

  // Struct for a proposed set of transactions, used only for off-chain infrastructure.
  struct Proposal {
    Transaction[] transactions;
    uint256 requestTime;
  }

  /**
   * @notice Gets the current time for this contract.
   * @dev This only exists so it can be overridden for testing.
   */
  function getCurrentTime() public view virtual returns (uint256) {
    return block.timestamp;
  }

}
