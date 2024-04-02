pragma solidity ^0.8.6;

import {Enum} from "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uma/core/common/implementation/Lockable.sol";
import "@uma/core/common/interfaces/AddressWhitelistInterface.sol";

import "@uma/core/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/data-verification-mechanism/interfaces/FinderInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";
import "@uma/core/data-verification-mechanism/interfaces/StoreInterface.sol";

import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";

import "@uma/core/optimistic-oracle-v3/implementation/ClaimData.sol";

contract OptimisticExecutor is OptimisticOracleV3CallbackRecipientInterface, Lockable {

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

  uint64 public liveness; // The amount of time to dispute proposed transactions before they can be executed.
  IERC20 public collateral; // Collateral currency used to assert proposed transactions.
  uint256 public bondAmount; // Configured amount of collateral currency to make assertions for proposed transactions.
  string public rules; // Rules for the Oya module.
  bytes32 public identifier; // Identifier used to request price from the DVM, compatible with Optimistic Oracle V3.
  address public escalationManager; // Optional Escalation Manager contract to whitelist proposers / disputers.

  OptimisticOracleV3Interface public optimisticOracleV3; // Optimistic Oracle V3 contract used to assert proposed
    // transactions.

  mapping(bytes32 => bytes32) public assertionIds; // Maps proposal hashes to assertionIds.
  mapping(bytes32 => bytes32) public proposalHashes; // Maps assertionIds to proposal hashes.
  mapping(address => bool) public isController; // Says if address is a controller of this Oya account.
  mapping(address => bool) public isRecoverer; // Says if address is a recoverer of this Oya account.

  /**
   * @notice Function to delete a proposal on an Optimistic Oracle V3 upgrade.
   * @param proposalHash the hash of the proposal to delete.
   * @dev In case of an Optimistic Oracle V3 upgrade, the proposal execution would be blocked as its related
   * assertionId would not be recognized by the new Optimistic Oracle V3. This function allows the proposal to be
   * deleted if detecting an Optimistic Oracle V3 upgrade so that transactions can be re-proposed if needed.
   */
  function deleteProposalOnUpgrade(bytes32 proposalHash) public nonReentrant {
    require(proposalHash != bytes32(0), "Invalid proposal hash");
    bytes32 assertionId = assertionIds[proposalHash];
    require(assertionId != bytes32(0), "Proposal hash does not exist");

    // Detect Optimistic Oracle V3 upgrade by checking if it has the matching assertionId.
    require(optimisticOracleV3.getAssertion(assertionId).asserter == address(0), "OOv3 upgrade not detected");

    // Remove proposal hash and assertionId so that transactions can be re-proposed if needed.
    delete assertionIds[proposalHash];
    delete proposalHashes[assertionId];

    emit ProposalDeleted(proposalHash, assertionId);
  }

  /**
   * @notice Callback to automatically delete a proposal that was disputed.
   * @param assertionId the identifier of the disputed assertion.
   */
  function assertionDisputedCallback(bytes32 assertionId) external {
    bytes32 proposalHash = proposalHashes[assertionId];

    // Callback should only be called by the Optimistic Oracle V3. Address would not match in case of contract
    // upgrade, thus try deleting the proposal through deleteProposalOnUpgrade function that should revert if
    // address mismatch was not caused by an Optimistic Oracle V3 upgrade.
    if (msg.sender == address(optimisticOracleV3)) {
      // Validate the assertionId through existence of non-zero proposalHash. This is the same check as in
      // deleteProposalOnUpgrade method that is called in the else branch.
      require(proposalHash != bytes32(0), "Invalid proposal hash");

      // Delete the disputed proposal and associated assertionId.
      delete assertionIds[proposalHash];
      delete proposalHashes[assertionId];

      emit ProposalDeleted(proposalHash, assertionId);
    } else {
      deleteProposalOnUpgrade(proposalHash);
    }
  }

  /**
   * @notice Callback function that is called by Optimistic Oracle V3 when an assertion is resolved.
   * @dev This function does nothing and is only here to satisfy the callback recipient interface.
   * @param assertionId The identifier of the assertion that was resolved.
   * @param assertedTruthfully Whether the assertion was resolved as truthful or not.
   */
  function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {}

  /**
   * @notice Gets the current time for this contract.
   * @dev This only exists so it can be overridden for testing.
   */
  function getCurrentTime() public view virtual returns (uint256) {
    return block.timestamp;
  }

}
