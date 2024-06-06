pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "safe-tools/SafeTestTools.sol";

contract SafeModuleDeployTest is Test, SafeTestTools {

  using SafeTestLib for SafeInstance;

  address deployedSafeAddress;

  function setUp() public {
    vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    _initializeSafeTools();

    SafeInstance memory safeInstance = _setupSafe();
    deployedSafeAddress = address(safeInstance.safe);

    address alice = address(0xA11c3);
    safeInstance.execTransaction({to: alice, value: 0.5 ether, data: ""}); // send .5 eth to alice
  }

  function testSafe() public view {
    address alice = address(0xA11c3);
    assertEq(alice.balance, 0.5 ether); // passes ✅
  }

  function testEnableModule() public {
    SafeInstance memory safeInstance = _attachToSafe(deployedSafeAddress);
    // This module address is for the Optimistic Governor mastercopy
    safeInstance.enableModule(0x28CeBFE94a03DbCA9d17143e9d2Bd1155DC26D5d);
    safeInstance.safe.isModuleEnabled(0x28CeBFE94a03DbCA9d17143e9d2Bd1155DC26D5d); // passes ✅
  }

  

}
