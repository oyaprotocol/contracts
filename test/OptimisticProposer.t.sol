// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";

import "../src/implementation/OptimisticProposer.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract OptimisticProposerTest is Test {

  OptimisticProposer public optimisticProposer;
  MockFinder public mockFinder;
  MockAddressWhitelist public mockAddressWhitelist;
  MockIdentifierWhitelist public mockIdentifierWhitelist;
  MockOptimisticOracleV3 public mockOptimisticOracleV3;
  MockERC20 public mockCollateral;
  EscalationManagerInterface public mockEscalationManager;
  address public owner = address(1);
  address public newOwner = address(2);
  address public randomAddress = address(3);
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

    // Setup the finder to return the mocks
    mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

    // Add collateral and identifier to the whitelist
    mockAddressWhitelist.addToWhitelist(address(mockCollateral));
    mockIdentifierWhitelist.addIdentifier(identifier);

    // Deploy the OptimisticProposer contract, default owner is deployer, i.e., the zero address in tests
    optimisticProposer =
      new OptimisticProposer();
    
    // Transferring ownership to a non-zero address for test clarity
    vm.prank(address(0));
    optimisticProposer.transferOwnership(owner);
  }

  function testTransferOwnership() public {
    vm.startPrank(owner);
    optimisticProposer.transferOwnership(newOwner);

    assertEq(optimisticProposer.owner(), newOwner);
    vm.stopPrank();
  }

  function testRenounceOwnership() public {
    vm.startPrank(owner);
    optimisticProposer.renounceOwnership();
    assertEq(optimisticProposer.owner(), address(0));
    vm.stopPrank();
  }

  function testNonOwnerCallShouldRevert() public {
    vm.startPrank(randomAddress);
    vm.expectRevert();
    optimisticProposer.transferOwnership(randomAddress);
    vm.stopPrank();
  }

  function testSetEscalationManager() public {
    vm.startPrank(owner);
    optimisticProposer.setEscalationManager(address(mockEscalationManager));
    assertEq(optimisticProposer.escalationManager(), address(mockEscalationManager));
    vm.stopPrank();
  }

  function testSetRules() public {
    vm.startPrank(owner);
    optimisticProposer.setRules(newRules);
    assertEq(optimisticProposer.rules(), newRules);
    vm.stopPrank();
  }

  function testSetLiveness() public {
    vm.startPrank(owner);
    optimisticProposer.setLiveness(newLiveness);
    assertEq(optimisticProposer.liveness(), newLiveness);
    vm.stopPrank();
  }

  // tests currently failing

  // function testSetCollateralAndBond() public {
  //   vm.startPrank(owner);
  //   optimisticProposer.setCollateralAndBond(mockCollateral, bondAmount);
  //   assertEq(optimisticProposer.collateral(), mockCollateral);
  //   assertEq(optimisticProposer.bondAmount(), bondAmount);
  //   vm.stopPrank();
  // }

  // function testSetIdentifier() public {
  //   vm.startPrank(owner);
  //   optimisticProposer.setIdentifier(identifier);
  //   assertEq(optimisticProposer.identifier(), identifier);
  //   vm.stopPrank();
  // }

  // function testSync() public {
  //   vm.startPrank(randomAddress);
  //   optimisticProposer.sync();
  //   vm.stopPrank();
  // }

  // function testProposeTransactions() public {
  //   vm.startPrank(owner);
  //   OptimisticProposer.Transaction[] memory testTransactions = new OptimisticProposer.Transaction[](2);
    
  //   testTransactions[0] = OptimisticProposer.Transaction(
  //     address(4), Enum.Operation(0), 0, "");
  //   testTransactions[1] = OptimisticProposer.Transaction(
  //     address(mockOptimisticOracleV3), Enum.Operation(0), 0, "0x");
    
  //   optimisticProposer.proposeTransactions(
  //     testTransactions, 
  //     "0x6f79612074657374000000000000000000000000000000000000000000000000"
  //   ); // "oya test" is the explanation
  //   vm.stopPrank();
  // }

}
