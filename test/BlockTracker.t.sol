// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";

import "../src/implementation/BlockTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BlockTrackerTest is Test {

  BlockTracker public blockTracker;
  MockFinder public mockFinder;
  MockAddressWhitelist public mockAddressWhitelist;
  MockIdentifierWhitelist public mockIdentifierWhitelist;
  MockOptimisticOracleV3 public mockOptimisticOracleV3;
  MockERC20 public mockCollateral;
  MockERC20 public newMockCollateral;
  EscalationManagerInterface public mockEscalationManager;
  address public owner = address(1);
  address public blockProposer = address(2);
  address public nonBlockProposer = address(3);
  address public newBlockProposer = address(4);
  address public newOwner = address(5);
  address public randomAddress = address(6);
  uint256 public bondAmount = 1000;
  string public rules = "Sample rules";
  string public newRules = "New rules";
  bytes32 public identifier = keccak256("Identifier");
  uint64 public liveness = 100;
  uint64 public newLiveness = 200;

  function setUp() public {
    // Set up the mock contracts
    mockFinder = new MockFinder();
    mockAddressWhitelist = new MockAddressWhitelist();
    mockIdentifierWhitelist = new MockIdentifierWhitelist();
    mockOptimisticOracleV3 = new MockOptimisticOracleV3();
    mockCollateral = new MockERC20();
    newMockCollateral = new MockERC20();

    // Give the "owner" some collateral
    mockCollateral.transfer(owner, 1000 * 10 ** 18);

    // Setup the finder to return the mocks
    mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

    // Add collateral and identifier to the whitelist
    mockAddressWhitelist.addToWhitelist(address(mockCollateral));
    mockAddressWhitelist.addToWhitelist(address(newMockCollateral));
    mockIdentifierWhitelist.addIdentifier(identifier);

    vm.startPrank(owner);
    blockTracker =
      new BlockTracker(address(mockFinder), blockProposer, address(mockCollateral), bondAmount, rules, identifier, liveness);
    vm.stopPrank();
  }

  function testProposeBlock() public {
    vm.startPrank(blockProposer);
    string memory blockData = "Block data";
    blockTracker.proposeBlock(blockData);

    assertEq(blockTracker.blocks(block.timestamp), blockData);
    vm.stopPrank();
  }

  function testAddBlockProposer() public {
    vm.startPrank(owner);
    blockTracker.addBlockProposer(newBlockProposer);

    assertTrue(blockTracker.blockProposers(newBlockProposer));
    vm.stopPrank();
  }

  function testRemoveBlockProposer() public {
    vm.startPrank(owner);
    blockTracker.addBlockProposer(newBlockProposer);
    assertTrue(blockTracker.blockProposers(newBlockProposer));

    blockTracker.removeBlockProposer(newBlockProposer);
    assertFalse(blockTracker.blockProposers(newBlockProposer));
    vm.stopPrank();
  }

  // Optimistic Proposer inherited tests
  function testTransferOwnership() public {
    vm.startPrank(owner);
    blockTracker.transferOwnership(newOwner);

    assertEq(blockTracker.owner(), newOwner);
    vm.stopPrank();
  }

  function testRenounceOwnership() public {
    vm.startPrank(owner);
    blockTracker.renounceOwnership();
    assertEq(blockTracker.owner(), address(0));
    vm.stopPrank();
  }

  function testNonOwnerCallShouldRevert() public {
    vm.startPrank(randomAddress);
    vm.expectRevert();
    blockTracker.transferOwnership(randomAddress);
    vm.stopPrank();
  }

  function testSetEscalationManager() public {
    vm.startPrank(owner);
    blockTracker.setEscalationManager(address(mockEscalationManager));
    assertEq(blockTracker.escalationManager(), address(mockEscalationManager));
    vm.stopPrank();
  }

  function testSetRules() public {
    vm.startPrank(owner);
    blockTracker.setRules(newRules);
    assertEq(blockTracker.rules(), newRules);
    vm.stopPrank();
  }

  function testSetLiveness() public {
    vm.startPrank(owner);
    blockTracker.setLiveness(newLiveness);
    assertEq(blockTracker.liveness(), newLiveness);
    vm.stopPrank();
  }

  function testSetIdentifier() public {
    vm.startPrank(owner);
    blockTracker.setIdentifier(identifier);
    assertEq(blockTracker.identifier(), identifier);
    vm.stopPrank();
  }

  function testSync() public {
    vm.startPrank(randomAddress);
    blockTracker.sync();
    vm.stopPrank();
  }

  function testSetCollateralAndBond() public {
    vm.startPrank(owner);
    blockTracker.setCollateralAndBond(newMockCollateral, bondAmount);
    assertEq(address(blockTracker.collateral()), address(newMockCollateral));
    assertEq(blockTracker.bondAmount(), bondAmount);
    vm.stopPrank();
  }

  function testProposeTransactions() public {
    vm.startPrank(owner);
    mockCollateral.approve(address(blockTracker), 1000 * 10 ** 18);
    OptimisticProposer.Transaction[] memory testTransactions = new OptimisticProposer.Transaction[](2);
    
    testTransactions[0] = OptimisticProposer.Transaction(
      address(4), Enum.Operation(0), 0, "");
    testTransactions[1] = OptimisticProposer.Transaction(
      address(mockOptimisticOracleV3), Enum.Operation(0), 0, "0x");
    
    blockTracker.proposeTransactions(
      testTransactions, 
      "0x6f79612074657374000000000000000000000000000000000000000000000000"
    ); // "oya test" is the explanation
    vm.stopPrank();
  }

}
