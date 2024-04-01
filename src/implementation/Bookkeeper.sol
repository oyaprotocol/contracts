pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Bookkeeper is BookkeeperInterface, Ownable {
  // Mapping for bundle data
  // uint256 is block timestamp
  // bytes32 tells you where to find the bundle data
  mapping(uint256 => bytes32) public bundles;
  uint256 public currentFinalizedBundle;

  // Mapping for bundler permissions
  mapping(address => bool) public bundlers;

  // Modifier to restrict function access to only bundlers
  modifier onlyBundler() {
    require(bundlers[msg.sender], "Caller is not a bundler");
    _;
  }

  constructor() {
    // Contract initializer can be a default bundler
    bundlers[msg.sender] = true;
  }

  function propose(bytes32 _bundleData) external override onlyBundler {
    bundles[block.timestamp] = _bundleData;
    // In practice, call UMA or another system to validate the bundle here
    // Also need to store some data to find the 
  }

  function finalize(uint256 _bundle) external {
    // This should be a callback function from the optimistic oracle
    currentFinalizedBundle = _bundle;
  }

  function cancel(uint256 _bundle) external override onlyBundler {
    delete bundles[_bundle];
  }

  function settle(address _oyaAccount, address _tokenContract, uint256 _amount) external override {
    // Transfer tokens from the caller to this contract
  }

  function bridge(address _tokenContract, uint256 _amount, uint256 _chainId) external override onlyBundler {
    // In practice, call a bridging service like Across
    // This is a placeholder for asset bridging logic
  }

  function withdraw(address _tokenContract, uint256 _amount) external override {
    // Withdraw tokens from the bookkeeper contract
    // This may be called by the bundler, or any address that is owed funds
  }

  function addBundler(address _bundler) external override onlyOwner {
    bundlers[_bundler] = true;
  }

  function removeBundler(address _bundler) external override onlyOwner {
    delete bundlers[_bundler];
  }

  function addBookkeeper(address, uint256) external override onlyOwner {
    // Implement addition logic, possibly with timelocks or synchronization across chains
  }

  function removeBookkeeper(address, uint256) external override onlyOwner {
    // Implement removal logic, possibly with timelocks or synchronization across chains
  }
}
