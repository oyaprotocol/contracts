// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Oya.sol";

contract OyaTest is Test {
  Oya public oyatoken;

  function setUp() public {
    vm.prank(address(vm.addr(1)));
    oyatoken = new Oya();
  }

  function testName() public {
    assertEq(oyatoken.name(), "Oya");
  }

  function testMint() public {
    // Initial total supply is 1 billion
    assertEq(oyatoken.totalSupply(), 1000000000 * 10 ** 18);

    // Call mint function as owner
    vm.prank(address(vm.addr(1)));
    oyatoken.mint(vm.addr(2), 100);

    // Total supply should increase by 100
    assertEq(oyatoken.totalSupply(), 1000000000 * 10 ** 18 + 100);

    // Balance of the recipient should be 100
    assertEq(oyatoken.balanceOf(vm.addr(2)), 100);
  }
}
