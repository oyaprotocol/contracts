// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/common/interfaces/AddressWhitelistInterface.sol";

contract MockAddressWhitelist is AddressWhitelistInterface {
  mapping(address => bool) public whitelist;

  function addToWhitelist(address _address) external {
    whitelist[_address] = true;
  }

  function removeFromWhitelist(address _address) external {
    whitelist[_address] = false;
  }

  function isOnWhitelist(address _address) external view returns (bool) {
    return whitelist[_address];
  }

  function getWhitelist() external pure returns (address[] memory) {
    address[] memory emptyArray = new address[](0);
    return emptyArray;
  }
}
