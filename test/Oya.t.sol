// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Oya.sol";

contract OyaTest is Test {
  Oya public instance;

  function setUp() public {
    address initialOwner = vm.addr(1);
    instance = new Oya(initialOwner);
  }

  function testName() public {
    assertEq(instance.name(), "Oya");
  }
}
