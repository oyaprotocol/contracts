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

    uint256 public bondAmount = 1000;
    string public rules = "Sample rules";
    string public newRules = "New rules";
    bytes32 public identifier = keccak256("Identifier");
    uint64 public liveness = 100;

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
    }

    function testCreateVaultWithController() public {
        vm.startPrank(owner);
        uint256 newVaultId = vaultTracker.createVault(controller);
        vm.stopPrank();
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
