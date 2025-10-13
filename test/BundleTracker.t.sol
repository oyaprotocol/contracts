// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";
import "../src/implementation/BundleTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";

contract BundleTrackerTest is Test {
    BundleTracker public bundleTracker;
    MockFinder public mockFinder;
    MockAddressWhitelist public mockAddressWhitelist;
    MockIdentifierWhitelist public mockIdentifierWhitelist;
    MockOptimisticOracleV3 public mockOptimisticOracleV3;
    MockERC20 public mockCollateral;
    MockERC20 public newMockCollateral;
    EscalationManagerInterface public mockEscalationManager;

    address public owner         = address(1);
    address public bundleProposer = address(2);
    address public txProposer    = address(3); // For proposeTransactions
    address public randomAddress = address(4);

    uint256 public bondAmount = 1000;
    string  public rules      = "Sample rules";
    string  public newRules   = "New rules";

    bytes32 public identifier = keccak256("Identifier");
    bytes32 public newIdentifier = keccak256("AnotherIdentifier");
    
    uint64 public liveness    = 100;
    uint64 public newLiveness = 200;

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

        // Add collateral and identifier to the whitelist
        mockAddressWhitelist.addToWhitelist(address(mockCollateral));
        mockAddressWhitelist.addToWhitelist(address(newMockCollateral));
        mockIdentifierWhitelist.addIdentifier(identifier);
        mockIdentifierWhitelist.addIdentifier(newIdentifier);

        // Deploy & initialize the BundleTracker contract from "owner" address
        vm.startPrank(owner);
        bundleTracker = new BundleTracker(
            address(mockFinder),
            address(mockCollateral),
            bondAmount,
            rules,
            identifier,
            liveness
        );
        vm.stopPrank();
    }

    // -----------------------------------------
    // Tests for native BundleTracker functions
    // -----------------------------------------

    function testProposeBundle() public {
        // Give bundleProposer some collateral to pay bond
        mockCollateral.transfer(bundleProposer, 2000e18);

        vm.startPrank(bundleProposer);
        // Approve enough collateral for the bond
        mockCollateral.approve(address(bundleTracker), 2000e18);

        string memory bundleData = "Bundle data example";

        // Propose the bundle
        bundleTracker.proposeBundle(bundleData);

        uint256 expectedBond = bundleTracker.getProposalBond();

        // The bond should be pulled into the contract before forwarding to the OO
        assertEq(mockCollateral.balanceOf(address(bundleTracker)), expectedBond, "Bond not collected");
        assertEq(
            mockCollateral.balanceOf(bundleProposer),
            2000e18 - expectedBond,
            "Proposer balance not reduced by bond"
        );

        // The contract stores in: bundles[block.timestamp][msg.sender]
        string memory storedData = bundleTracker.bundles(block.timestamp, bundleProposer);
        assertEq(storedData, bundleData, "Bundle data not stored correctly");

        vm.stopPrank();
    }

    // -----------------------------------------
    // Tests for inherited OptimisticProposer functions
    // -----------------------------------------

    function testSetRules() public {
        vm.startPrank(owner);
        bundleTracker.setRules(newRules);
        vm.stopPrank();

        assertEq(bundleTracker.rules(), newRules, "Rules not updated");
    }

    function testSetIdentifier() public {
        // Initially set to 'identifier'
        assertEq(bundleTracker.identifier(), identifier);

        vm.startPrank(owner);
        bundleTracker.setIdentifier(newIdentifier);
        vm.stopPrank();

        assertEq(bundleTracker.identifier(), newIdentifier, "Identifier not updated");
    }

    function testSetLiveness() public {
        // Initially set to 'liveness'
        assertEq(bundleTracker.liveness(), liveness);

        vm.startPrank(owner);
        bundleTracker.setLiveness(newLiveness);
        vm.stopPrank();

        assertEq(bundleTracker.liveness(), newLiveness, "Liveness not updated");
    }

    function testSetEscalationManager() public {
        vm.startPrank(owner);
        bundleTracker.setEscalationManager(address(mockEscalationManager));
        vm.stopPrank();

        assertEq(bundleTracker.escalationManager(), address(mockEscalationManager), "Escalation manager not updated");
    }

    function testSetCollateralAndBond() public {
        vm.startPrank(owner);
        bundleTracker.setCollateralAndBond(IERC20(address(newMockCollateral)), bondAmount);
        vm.stopPrank();

        assertEq(address(bundleTracker.collateral()), address(newMockCollateral), "Collateral not updated");
        assertEq(bundleTracker.bondAmount(), bondAmount, "Bond amount not updated");
    }

    function testProposeTransactions() public {
        // Give txProposer some collateral to pay bond
        mockCollateral.transfer(txProposer, 3000e18);

        vm.startPrank(txProposer);
        // Approve enough collateral for the bond
        mockCollateral.approve(address(bundleTracker), 3000e18);

        // Build a small set of transactions
        OptimisticProposer.Transaction[] memory txs = new OptimisticProposer.Transaction[](2);

        // transaction #1
        txs[0] = OptimisticProposer.Transaction({
            to: address(0x1234),
            operation: Enum.Operation.Call,
            value: 0,
            data: ""
        });

        // transaction #2
        txs[1] = OptimisticProposer.Transaction({
            to: address(mockOptimisticOracleV3),
            operation: Enum.Operation.Call,
            value: 0,
            data: "0x"
        });

        // propose transactions with some "explanation"
        bundleTracker.proposeTransactions(txs, bytes("Hello world"));

        vm.stopPrank();
    }
}
