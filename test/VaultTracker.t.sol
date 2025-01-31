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
    address public controller = address(2);
    address public guardian = address(3);
    address public randomAddress = address(4);

    uint256 public bondAmount = 1000;
    string public rules = "Sample rules";
    string public newRules = "New rules";
    bytes32 public identifier = keccak256("Identifier");
    uint64 public liveness = 100;
    uint256 public createdVaultId;

    function setUp() public {
        mockFinder = new MockFinder();
        mockAddressWhitelist = new MockAddressWhitelist();
        mockIdentifierWhitelist = new MockIdentifierWhitelist();
        mockOptimisticOracleV3 = new MockOptimisticOracleV3();
        mockCollateral = new MockERC20();
        newMockCollateral = new MockERC20();

        mockFinder.changeImplementationAddress(OracleInterfaces.CollateralWhitelist, address(mockAddressWhitelist));
        mockFinder.changeImplementationAddress(OracleInterfaces.IdentifierWhitelist, address(mockIdentifierWhitelist));
        mockFinder.changeImplementationAddress(OracleInterfaces.OptimisticOracleV3, address(mockOptimisticOracleV3));

        mockAddressWhitelist.addToWhitelist(address(mockCollateral));
        mockAddressWhitelist.addToWhitelist(address(newMockCollateral));
        mockIdentifierWhitelist.addIdentifier(identifier);

        vm.prank(owner);
        vaultTracker = new VaultTracker(
            address(mockFinder),
            address(mockCollateral),
            bondAmount,
            rules,
            identifier,
            liveness
        );

        vm.prank(owner);
        createdVaultId = vaultTracker.createVault(controller);
    }

    function testSetController() public {
        vm.prank(randomAddress);
        vm.expectRevert("Not a controller");
        vaultTracker.setController(createdVaultId, controller);

        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);
        assertTrue(vaultTracker.isController(createdVaultId, controller));
    }

    function testSetGuardian() public {
        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);
        vm.prank(controller);
        vaultTracker.setGuardian(createdVaultId, guardian);
        assertTrue(vaultTracker.isGuardian(createdVaultId, guardian));
    }

    function testSetVaultRules() public {
        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);

        vm.prank(controller);
        vm.expectRevert("Rules can not be empty");
        vaultTracker.setVaultRules(createdVaultId, "");

        vm.prank(controller);
        vaultTracker.setVaultRules(createdVaultId, "Vault policy 1");
        assertEq(vaultTracker.vaultRules(createdVaultId), "Vault policy 1");
    }

    function testFreezeVault() public {
        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);
        vm.prank(controller);
        vaultTracker.setGuardian(createdVaultId, guardian);

        vm.prank(randomAddress);
        vm.expectRevert("Not a guardian");
        vaultTracker.freezeVault(createdVaultId);

        vm.prank(guardian);
        vaultTracker.freezeVault(createdVaultId);
        assertTrue(vaultTracker.vaultFrozen(createdVaultId));
    }

    function testUnfreezeVault() public {
        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);
        vm.prank(controller);
        vaultTracker.setGuardian(createdVaultId, guardian);

        vm.prank(guardian);
        vaultTracker.freezeVault(createdVaultId);

        vm.prank(randomAddress);
        vm.expectRevert("Not a guardian");
        vaultTracker.unfreezeVault(createdVaultId);

        vm.prank(guardian);
        vaultTracker.unfreezeVault(createdVaultId);
        assertFalse(vaultTracker.vaultFrozen(createdVaultId));
    }

    function testSetBlockProposer() public {
        vm.prank(address(vaultTracker));
        vaultTracker.setController(createdVaultId, controller);

        vm.warp(1000);
        vm.prank(controller);
        vaultTracker.setBlockProposer(createdVaultId, address(999));
        assertEq(vaultTracker.blockProposers(createdVaultId), address(999));
        assertEq(vaultTracker.proposerChangeLiveTime(createdVaultId), 1900);
    }

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
