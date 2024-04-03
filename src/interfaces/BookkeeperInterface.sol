pragma solidity ^0.8.6;

interface BookkeeperInterface {

  function proposeBundle(bytes32) external;
  function cancelBundle(uint256) external;
  function removeBundler(address) external;
  function updateBookkeeper(uint256, address, bool) external;

}
