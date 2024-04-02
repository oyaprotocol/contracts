pragma solidity ^0.8.6;

interface BookkeeperInterface {

  function propose(bytes32) external;
  function finalize(uint256) external;
  function cancel(uint256) external;
  function bridge(address, uint256, uint256) external;
  function withdraw(address, uint256) external;
  function addBundler(address) external;
  function removeBundler(address) external;
  function updateBookkeeper(uint256, address, bool) external;

}
