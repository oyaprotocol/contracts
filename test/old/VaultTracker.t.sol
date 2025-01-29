// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";

import "../src/implementation/VaultTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract VaultTrackerTest is Test {

  VaultTracker public vaultTracker;
  MockFinder public mockFinder;
  MockAddressWhitelist public mockAddressWhitelist;
  MockIdentifierWhitelist public mockIdentifierWhitelist;
  MockOptimisticOracleV3 public mockOptimisticOracleV3;
  MockERC20 public mockCollateral;
  MockERC20 public newMockCollateral;
  EscalationManagerInterface public mockEscalationManager;
  address public owner = address(1);
  address public vaultTrackerAddress = address(2);
  address public newOwner = address(3);
  address public randomAddress = address(4);
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

    vm.prank(owner);
    vaultTracker = new VaultTracker(address(mockFinder), address(mockCollateral), bondAmount, rules, identifier, liveness);
  }

  function testUpdateVaultTracker() public {
    vm.startPrank(owner);
    uint256 chainId = 1;
    vaultTracker.updateVaultTracker(vaultTrackerAddress, chainId, true);

    assertTrue(vaultTracker.vaultTrackers(vaultTrackerAddress, chainId));
    vm.stopPrank();
  }

  // Optimistic Proposer inherited tests
  function testTransferOwnership() public {
    vm.startPrank(owner);
    vaultTracker.transferOwnership(newOwner);

    assertEq(vaultTracker.owner(), newOwner);
    vm.stopPrank();
  }

  function testRenounceOwnership() public {
    vm.startPrank(owner);
    vaultTracker.renounceOwnership();
    assertEq(vaultTracker.owner(), address(0));
    vm.stopPrank();
  }

  function testNonOwnerCallShouldRevert() public {
    vm.startPrank(randomAddress);
    vm.expectRevert();
    vaultTracker.transferOwnership(randomAddress);
    vm.stopPrank();
  }

  function testSetEscalationManager() public {
    vm.startPrank(owner);
    vaultTracker.setEscalationManager(address(mockEscalationManager));
    assertEq(vaultTracker.escalationManager(), address(mockEscalationManager));
    vm.stopPrank();
  }

  function testSetRules() public {
    vm.startPrank(owner);
    vaultTracker.setRules(newRules);
    assertEq(vaultTracker.rules(), newRules);
    vm.stopPrank();
  }

  function testSetLiveness() public {
    vm.startPrank(owner);
    vaultTracker.setLiveness(newLiveness);
    assertEq(vaultTracker.liveness(), newLiveness);
    vm.stopPrank();
  }

  function testSetIdentifier() public {
    vm.startPrank(owner);
    vaultTracker.setIdentifier(identifier);
    assertEq(vaultTracker.identifier(), identifier);
    vm.stopPrank();
  }

  function testSync() public {
    vm.startPrank(randomAddress);
    vaultTracker.sync();
    vm.stopPrank();
  }

  function testSetCollateralAndBond() public {
    vm.startPrank(owner);
    vaultTracker.setCollateralAndBond(newMockCollateral, bondAmount);
    assertEq(address(vaultTracker.collateral()), address(newMockCollateral));
    assertEq(vaultTracker.bondAmount(), bondAmount);
    vm.stopPrank();
  }

  function testProposeTransactions() public {
    vm.startPrank(owner);
    mockCollateral.approve(address(vaultTracker), 1000 * 10 ** 18);
    OptimisticProposer.Transaction[] memory testTransactions = new OptimisticProposer.Transaction[](2);
    
    testTransactions[0] = OptimisticProposer.Transaction(
      address(4), Enum.Operation(0), 0, "");
    testTransactions[1] = OptimisticProposer.Transaction(
      address(mockOptimisticOracleV3), Enum.Operation(0), 0, "0x");
    
    vaultTracker.proposeTransactions(
      testTransactions, 
      "0x6f79612074657374000000000000000000000000000000000000000000000000"
    ); // "oya test" is the explanation
    vm.stopPrank();
  }

  function testSetController() public {
    address account = address(5);
    address controller = address(6);

    // Set controller by account owner
    vm.prank(account);
    vaultTracker.setController(account, controller);
    assertTrue(vaultTracker.isController(account, controller));

    // Set controller by an existing controller
    vm.prank(controller);
    vaultTracker.setController(account, address(7));
    assertTrue(vaultTracker.isController(account, address(7)));

    // Attempt to set controller by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    vaultTracker.setController(account, address(8));
  }

  function testSetGuardian() public {
    address account = address(5);
    address guardian = address(6);

    // Set controller by account owner to ensure the guardian can be set
    vm.prank(account);
    vaultTracker.setController(account, address(this));

    // Set guardian by account owner
    vm.prank(account);
    vaultTracker.setGuardian(account, guardian);
    assertTrue(vaultTracker.isGuardian(account, guardian));

    // Set guardian by an existing controller
    vm.prank(address(this));
    vaultTracker.setGuardian(account, address(7));
    assertTrue(vaultTracker.isGuardian(account, address(7)));

    // Attempt to set guardian by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    vaultTracker.setGuardian(account, address(8));
  }

  function testSetAccountRules() public {
    address account = address(5);
    address controller = address(6);
    string memory accountRules = "Account specific rules";

    // Set controller by account owner to ensure the controller can set rules
    vm.prank(account);
    vaultTracker.setController(account, controller);

    // Set account rules by account owner
    vm.prank(account);
    vaultTracker.setAccountRules(account, accountRules);
    assertEq(vaultTracker.accountRules(account), accountRules);

    // Set account rules by an existing controller
    vm.prank(controller);
    vaultTracker.setAccountRules(account, "Updated rules");
    assertEq(vaultTracker.accountRules(account), "Updated rules");

    // Attempt to set empty account rules
    vm.prank(account);
    vm.expectRevert("Rules can not be empty");
    vaultTracker.setAccountRules(account, "");

    // Attempt to set account rules by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    vaultTracker.setAccountRules(account, "New rules");
  }

  function testGoManual() public {
    address account = address(5);
    address controller = address(6);

    // Set controller by account owner to ensure the controller can set manual mode
    vm.prank(account);
    vaultTracker.setController(account, controller);

    // Go manual by account owner
    vm.prank(account);
    vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Manual);
    assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Manual));
    assertTrue(vaultTracker.manualModeLiveTime(account) > block.timestamp);

    // Go manual by an existing controller
    vm.prank(controller);
    vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Manual);
    assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Manual));
    assertTrue(vaultTracker.manualModeLiveTime(account) > block.timestamp);

    // Attempt to go manual by a non-authorized user
    vm.prank(randomAddress);
    vm.expectRevert("Not a controller");
    vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Manual);
  }

  function testGoAutomatic() public {
    address account = address(5);
      address controller = address(6);

      // Set controller by account owner to ensure the controller can set automatic mode
      vm.prank(account);
      vaultTracker.setController(account, controller);

      // First, go manual
      vm.prank(account);
      vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Manual);
      assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Manual));

      // Go automatic by account owner
      vm.prank(account);
      vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Automatic);
      assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Automatic));
      assertEq(vaultTracker.manualModeLiveTime(account), 0);

      // Go manual again
      vm.prank(account);
      vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Manual);
      assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Manual));

      // Go automatic by an existing controller
      vm.prank(controller);
      vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Automatic);
      assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Automatic));
      assertEq(vaultTracker.manualModeLiveTime(account), 0);

      // Attempt to go automatic by a non-authorized user
      vm.prank(randomAddress);
      vm.expectRevert("Not a controller");
      vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Automatic);
  }

  function testFreeze() public {
    address account = address(5);
    address guardian = address(6);

    // Set controller by account owner to ensure the guardian can be set
    vm.prank(account);
    vaultTracker.setController(account, address(this));

    // Set guardian
    vm.prank(account);
    vaultTracker.setGuardian(account, guardian);

    // Freeze by guardian
    vm.prank(guardian);
    vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Frozen);
    assertEq(uint8(vaultTracker.accountModes(account)), uint8(VaultTracker.AccountMode.Frozen));

    // Attempt to freeze by a non-guardian
    vm.prank(randomAddress);
    vm.expectRevert("Not a guardian");
    vaultTracker.setAccountMode(account, VaultTracker.AccountMode.Frozen);
  }

}
