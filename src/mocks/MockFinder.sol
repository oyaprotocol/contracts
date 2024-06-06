// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/data-verification-mechanism/interfaces/FinderInterface.sol";
import "forge-std/console.sol"; // Import console for logging

contract MockFinder is FinderInterface {

  mapping(bytes32 => address) private addresses;

  function changeImplementationAddress(bytes32 interfaceName, address implementation) external {
    addresses[interfaceName] = implementation;
  }

  function getImplementationAddress(bytes32 interfaceName) external view override returns (address) {
    return addresses[interfaceName];
  }

}
