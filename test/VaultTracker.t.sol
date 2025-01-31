// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "../src/implementation/VaultTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";

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
    address public vault = address(2); // We'll treat this as "the vault"
    address public controller = address(3);
    address public guardian = address(4);
    address public randomAddress = address(5);

    uint256 public bondAmount = 1000;
    string public rules = "Sample rules";
    string public newRules = "New rules";
    bytes32 public identifier = keccak256("Identifier");
    uint64 public liveness = 100;

    function setUp() public {
        // Set up the mock contracts
        mockFinder = new MockFinder();
        mockAddressWhitelist = new MockAddressWhitelist();
        mockIdentifierWhitelist = new MockIdentifierWhitelist();
        mockOptimisticOracleV3 = new MockOptimisticOracleV3();
        mockCollateral = new MockERC20();
        newMockCollateral = new MockERC20();

        // Setup the finder to return the mocks
        mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
        mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
        mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

        // Whitelist the tokens/identifier
        mockAddressWhitelist.addToWhitelist(address(mockCollateral));
        mockAddressWhitelist.addToWhitelist(address(newMockCollateral));
        mockIdentifierWhitelist.addIdentifier(identifier);

        // Deploy & initialize from "owner" address
        vm.prank(owner);
        vaultTracker = new VaultTracker(
            address(mockFinder),
            address(mockCollateral),
            bondAmount,
            rules,
            identifier,
            liveness
        );
    }

    // ---------------------------
    // VaultTracker-specific tests
    // ---------------------------

    function testSetController() public {
        // By default, only the contract itself or an existing controller can call setController.
        // So let's pretend "vaultTracker" is calling on behalf of a proposal, or we can set up
        // an existing controller for `vault`.

        // 1) Attempt with random user -> should revert
        vm.prank(randomAddress);
        vm.expectRevert("Not a controller");
        vaultTracker.setController(vault, controller);

        // 2) Let's cheat and call from the contract address itself
        // Usually you'd do this via `executeProposal`, but in a unit test, we can do:
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);
        assertTrue(vaultTracker.isController(vault, controller), "Controller not set");
    }

    function testSetGuardian() public {
        // We first make "controller" a valid controller for "vault"
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);
        assertTrue(vaultTracker.isController(vault, controller));

        // Now, "controller" can set guardian
        vm.prank(controller);
        vaultTracker.setGuardian(vault, guardian);
        assertTrue(vaultTracker.isGuardian(vault, guardian));
    }

    function testSetVaultRules() public {
        // Similarly, only the contract or an existing controller can set
        // "vault rules"
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);

        // Attempt empty rules => revert
        vm.prank(controller);
        vm.expectRevert("Rules can not be empty");
        vaultTracker.setVaultRules(vault, "");

        // Valid set
        vm.prank(controller);
        vaultTracker.setVaultRules(vault, "Vault policy 1");
        assertEq(vaultTracker.vaultRules(vault), "Vault policy 1");
    }

    function testFreezeVault() public {
        // freezeVault requires the caller to be a Guardian
        // Let's set up a Guardian
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);
        vm.prank(controller);
        vaultTracker.setGuardian(vault, guardian);

        // random user => revert
        vm.prank(randomAddress);
        vm.expectRevert("Not a guardian");
        vaultTracker.freezeVault(vault);

        // Guardian can freeze
        vm.prank(guardian);
        vaultTracker.freezeVault(vault);
        assertTrue(vaultTracker.vaultFrozen(vault));
    }

    function testUnfreezeVault() public {
        // Must already be frozen and require a guardian call
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);
        vm.prank(controller);
        vaultTracker.setGuardian(vault, guardian);

        // Freeze first
        vm.prank(guardian);
        vaultTracker.freezeVault(vault);
        assertTrue(vaultTracker.vaultFrozen(vault));

        // Attempt unfreeze from random => revert
        vm.prank(randomAddress);
        vm.expectRevert("Not a guardian");
        vaultTracker.unfreezeVault(vault);

        // Unfreeze by guardian
        vm.prank(guardian);
        vaultTracker.unfreezeVault(vault);
        assertFalse(vaultTracker.vaultFrozen(vault));
    }

    function testSetBlockProposer() public {
        // Must be "this contract" or an existing controller
        vm.prank(address(vaultTracker));
        vaultTracker.setController(vault, controller);

        vm.warp(1000);
        vm.prank(controller);
        vaultTracker.setBlockProposer(vault, address(999));

        assertEq(vaultTracker.blockProposers(vault), address(999));
        // and the live time is block.timestamp + 15 min => 1000 + 900 => 1900
        assertEq(vaultTracker.proposerChangeLiveTime(vault), 1900);
    }

    // ---------------------------
    // Inherited: Test basic OO ops
    // ---------------------------

    function testSetRules() public {
        vm.startPrank(owner);
        vaultTracker.setRules(newRules);
        vm.stopPrank();

        assertEq(vaultTracker.rules(), newRules);
    }

    function testSetCollateralAndBond() public {
        vm.startPrank(owner);
        vaultTracker.setCollateralAndBond(IERC20(address(newMockCollateral)), bondAmount);
        vm.stopPrank();

        assertEq(address(vaultTracker.collateral()), address(newMockCollateral));
        assertEq(vaultTracker.bondAmount(), bondAmount);
    }
}
