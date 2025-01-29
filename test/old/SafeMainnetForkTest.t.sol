pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "safe-tools/SafeTestTools.sol";

contract ExistingSafeTest is Test, SafeTestTools {

  using SafeTestLib for SafeInstance;

  function setUp() public {
    vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    address alice = vm.addr(1337);

    address cow_safe = 0xcA771eda0c70aA7d053aB1B25004559B918FE662;
    SafeInstance memory safeInstance = _attachToSafe(cow_safe);

    safeInstance.execTransaction({to: alice, value: 0.1 ether, data: ""}); // send .1 eth to alice
  }

  function testSafe() public {
    address alice = vm.addr(1337);
    assertEq(alice.balance, 0.1 ether); // passes ✅
  }

}
