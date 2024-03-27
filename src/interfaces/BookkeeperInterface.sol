pragma solidity ^0.8.6;

interface BookkeeperInterface {
  /*
    Only bundler can propose a bundle
    The bundle will be mapped to an incrementing id

    We need to look into data availability solutions for the bundle data

    bytes32 - ipfs hash of where to find the bundle offchain
  */
  function proposeBundle(bytes32) external;

  /*
    Only bundler can update the internal state
    uint256 - bundle id to finalize, which must have been settled with UMA already
  
    Calls internal sync function to update bookkeeper contracts on all chains with the latest
    bundle information
  */
  function update(uint256) external;

  /*
    Only bundler can bridge assets to a bookkeeper contract on another chain
    They will do this periodically so that there are enough tokens on each chain for withdrawal
    Across is implemented under the hood

    address - token contract address
    uint256 - amount to bridge
    uint256 - chain id
  */
  function bridge(address, uint256, uint256) external;

  /*
    Anyone can settle with an Oya account, but in practice the bundler will do this

    address - Oya account to settle
  */
  function settle(address) external;

  /*
    Anyone can withdraw their assets held in the bookkeeper contract

    This is callable by Oya account holders, as well as the bundler

    In practice, Oya account holders withdrawing funds may be withdrawing part of the total 
    amount from their Safe, and part from the bookkeeper contract, depending on balances in
    each

    address - token contract address
    uint256 - amount to withdraw
  */
  function withdraw(address, uint256) external;
}
