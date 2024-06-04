// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

contract MockOptimisticOracleV3 is OptimisticOracleV3Interface {
  mapping(bytes32 => Assertion) public assertions;

  function assertTruth(
    bytes memory claim,
    address asserter,
    address callbackRecipient,
    address escalationManager,
    uint64 liveness,
    IERC20 currency,
    uint256 bondAmount,
    bytes32 identifier,
    bytes32 domainId
  ) external override returns (bytes32) {
    bytes32 assertionId = keccak256(abi.encode(claim, asserter, block.timestamp));
    assertions[assertionId] = Assertion({
      escalationManagerSettings: EscalationManagerSettings({
        arbitrateViaEscalationManager: false,
        discardOracle: false,
        validateDisputers: false,
        assertingCaller: msg.sender,
        escalationManager: escalationManager
      }),
      asserter: asserter,
      assertionTime: uint64(block.timestamp),
      settled: false,
      currency: currency,
      expirationTime: uint64(block.timestamp + liveness),
      settlementResolution: true,
      domainId: domainId,
      identifier: identifier,
      bond: bondAmount,
      callbackRecipient: callbackRecipient,
      disputer: address(0)
    });
    return assertionId;
  }

  function getMinimumBond(address /* currency */) external pure override returns (uint256) {
    return 100;
  }

  function settleAndGetAssertionResult(bytes32 /* assertionId */) external pure override returns (bool) {
    return true;
  }

  function getAssertion(bytes32 assertionId) external view override returns (Assertion memory) {
    return assertions[assertionId];
  }

  function assertTruthWithDefaults(bytes memory claim, address asserter) external view override returns (bytes32) {
    return keccak256(abi.encode(claim, asserter, block.timestamp));
  }

  function defaultIdentifier() external pure override returns (bytes32) {
    return keccak256("default");
  }

  function disputeAssertion(bytes32 /* assertionId */, address /* disputer */) external override {}

  function getAssertionResult(bytes32 /* assertionId */) external pure override returns (bool) {
    return true;
  }

  function settleAssertion(bytes32 /* assertionId */) external override {}

  function syncUmaParams(bytes32 /* identifier */, address /* currency */) external override {}
}
