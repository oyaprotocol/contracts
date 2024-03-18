pragma solidity ^0.8.20;

import "safe-tools/SafeTestTools.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract SafeTest is Test, SafeTestTools {
    using SafeTestLib for SafeInstance;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        address alice = vm.addr(1337);

        address frax_safe = 0xB1748C79709f4Ba2Dd82834B8c82D4a505003f27;
        SafeInstance memory safeInstance = _attachToSafe(frax_safe);

        safeInstance.execTransaction({
            to: alice,
            value: 0.5 ether,
            data: ""
        }); // send .5 eth to alice
    }

    function testSafe() public {
        address alice = vm.addr(1337);
        assertEq(alice.balance, 0.5 ether); // passes ✅
    }
}