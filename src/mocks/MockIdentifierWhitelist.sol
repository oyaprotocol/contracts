// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@uma/core/data-verification-mechanism/interfaces/IdentifierWhitelistInterface.sol";

contract MockIdentifierWhitelist is IdentifierWhitelistInterface {

  mapping(bytes32 => bool) public whitelist;

  function addIdentifier(bytes32 _identifier) external {
    whitelist[_identifier] = true;
  }

  function removeIdentifier(bytes32 _identifier) external {
    whitelist[_identifier] = false;
  }

  function isIdentifierSupported(bytes32 _identifier) external view override returns (bool) {
    return whitelist[_identifier];
  }

  function addSupportedIdentifier(bytes32 identifier) external override {
    whitelist[identifier] = true;
  }

  function removeSupportedIdentifier(bytes32 identifier) external override {
    whitelist[identifier] = false;
  }

}
