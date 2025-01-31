// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "forge-std/Test.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import "@uma/core/optimistic-oracle-v3/interfaces/EscalationManagerInterface.sol";
import "../src/implementation/BlockTracker.sol";
import "../src/mocks/MockAddressWhitelist.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockFinder.sol";
import "../src/mocks/MockIdentifierWhitelist.sol";
import "../src/mocks/MockOptimisticOracleV3.sol";

contract BlockTrackerTest is Test {
    BlockTracker public blockTracker;
    MockFinder public mockFinder;
    MockAddressWhitelist public mockAddressWhitelist;
    MockIdentifierWhitelist public mockIdentifierWhitelist;
    MockOptimisticOracleV3 public mockOptimisticOracleV3;
    MockERC20 public mockCollateral;
    MockERC20 public newMockCollateral;
    EscalationManagerInterface public mockEscalationManager;

    address public owner         = address(1);
    address public blockProposer = address(2);
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

        // Deploy & initialize the BlockTracker contract from "owner" address
        vm.startPrank(owner);
        blockTracker = new BlockTracker(
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
    // Tests for native BlockTracker functions
    // -----------------------------------------

    function testProposeBlock() public {
        // Give blockProposer some collateral to pay bond
        mockCollateral.transfer(blockProposer, 2000e18);

        vm.startPrank(blockProposer);
        // Approve enough collateral for the bond
        mockCollateral.approve(address(blockTracker), 2000e18);

        string memory blockData = "Block data example";

        // Propose the block
        blockTracker.proposeBlock(blockData);

        // The contract stores in: blocks[block.timestamp][msg.sender]
        string memory storedData = blockTracker.blocks(block.timestamp, blockProposer);
        assertEq(storedData, blockData, "Block data not stored correctly");

        vm.stopPrank();
    }

    // -----------------------------------------
    // Tests for inherited OptimisticProposer functions
    // -----------------------------------------

    function testSetRules() public {
        vm.startPrank(owner);
        blockTracker.setRules(newRules);
        vm.stopPrank();

        assertEq(blockTracker.rules(), newRules, "Rules not updated");
    }

    function testSetIdentifier() public {
        // Initially set to 'identifier'
        assertEq(blockTracker.identifier(), identifier);

        vm.startPrank(owner);
        blockTracker.setIdentifier(newIdentifier);
        vm.stopPrank();

        assertEq(blockTracker.identifier(), newIdentifier, "Identifier not updated");
    }

    function testSetLiveness() public {
        // Initially set to 'liveness'
        assertEq(blockTracker.liveness(), liveness);

        vm.startPrank(owner);
        blockTracker.setLiveness(newLiveness);
        vm.stopPrank();

        assertEq(blockTracker.liveness(), newLiveness, "Liveness not updated");
    }

    function testSetEscalationManager() public {
        vm.startPrank(owner);
        blockTracker.setEscalationManager(address(mockEscalationManager));
        vm.stopPrank();

        assertEq(blockTracker.escalationManager(), address(mockEscalationManager), "Escalation manager not updated");
    }

    function testSetCollateralAndBond() public {
        vm.startPrank(owner);
        blockTracker.setCollateralAndBond(IERC20(address(newMockCollateral)), bondAmount);
        vm.stopPrank();

        assertEq(address(blockTracker.collateral()), address(newMockCollateral), "Collateral not updated");
        assertEq(blockTracker.bondAmount(), bondAmount, "Bond amount not updated");
    }

    function testProposeTransactions() public {
        // Give txProposer some collateral to pay bond
        mockCollateral.transfer(txProposer, 3000e18);

        vm.startPrank(txProposer);
        // Approve enough collateral for the bond
        mockCollateral.approve(address(blockTracker), 3000e18);

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
        blockTracker.proposeTransactions(txs, bytes("Hello world"));

        vm.stopPrank();
    }
}
