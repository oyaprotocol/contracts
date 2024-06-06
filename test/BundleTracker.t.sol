// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../src/implementation/BundleTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BundleTrackerTest is Test {

  BundleTracker public bundleTracker;
  MockFinder public mockFinder;
  MockAddressWhitelist public mockAddressWhitelist;
  MockIdentifierWhitelist public mockIdentifierWhitelist;
  MockOptimisticOracleV3 public mockOptimisticOracleV3;
  MockERC20 public mockERC20;
  address public owner = address(1);
  address public bundler = address(2);
  address public nonBundler = address(3);
  address public newBundler = address(4);
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
    mockERC20 = new MockERC20();

    // Setup the finder to return the mocks
    mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
    mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

    // Add collateral and identifier to the whitelist
    mockAddressWhitelist.addToWhitelist(address(mockERC20));
    mockIdentifierWhitelist.addIdentifier(identifier);

    vm.startPrank(owner);
    bundleTracker =
      new BundleTracker(address(mockFinder), bundler, address(mockERC20), bondAmount, rules, identifier, liveness);
    vm.stopPrank();
  }

  function testProposeBundle() public {
    vm.startPrank(bundler);
    string memory bundleData = "Bundle data";
    bundleTracker.proposeBundle(bundleData);

    assertEq(bundleTracker.bundles(block.timestamp), bundleData);
    vm.stopPrank();
  }

  function testCancelBundle() public {
    vm.startPrank(bundler);
    string memory bundleData = "Bundle data";
    bundleTracker.proposeBundle(bundleData);

    bundleTracker.cancelBundle(block.timestamp);

    assertEq(bundleTracker.bundles(block.timestamp), "");
    vm.stopPrank();
  }

  function testAddBundler() public {
    vm.startPrank(owner);
    bundleTracker.addBundler(newBundler);

    assertTrue(bundleTracker.bundlers(newBundler));
    vm.stopPrank();
  }

  function testRemoveBundler() public {
    vm.startPrank(owner);
    bundleTracker.addBundler(newBundler);
    assertTrue(bundleTracker.bundlers(newBundler));

    bundleTracker.removeBundler(newBundler);
    assertFalse(bundleTracker.bundlers(newBundler));
    vm.stopPrank();
  }

}
