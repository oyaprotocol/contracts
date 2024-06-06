// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

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
  address public newOwner = address(1);
  uint256 public bondAmount = 1000;
  string public rules = "Sample rules";
  bytes32 public identifier = keccak256("Identifier");
  uint64 public liveness = 100;

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

    optimisticProposer =
      new OptimisticProposer();
    console.log(optimisticProposer.owner());
  }

  function testTransferOwnership() public {
    vm.startPrank(address(0)); // Original owner is deployer, i.e., the zero address in tests
    optimisticProposer.transferOwnership(newOwner);

    assertEq(optimisticProposer.owner(), newOwner);
    vm.stopPrank();
  }

}
