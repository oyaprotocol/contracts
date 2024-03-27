pragma solidity ^0.8.6;

interface BookkeeperInterface {
  /*
    Only bundler can propose a bundle

    The bundle will be mapped to an incrementing id

    This will call UMA to validate the bundle

    We need to look into data availability solutions for the bundle data

    bytes32 - ipfs hash of where to find the bundle offchain
  */
  function propose(bytes32) external;

  /*
    Only bundler can finalize a bundle
    uint256 - bundle id to finalize, which must have been validated with UMA already
  
    Calls internal sync function to update bookkeeper contracts on all chains with the latest
    bundle information
  */
  function finalize(uint256) external;

  /*
    Anyone can settle with an Oya account, but in practice the bundler will do this

    This will transfer funds from the Oya account holder's Safe to the bookkeeper contract

    Holding funds in the bookkeeper is better for efficiency, and necessary when settling 
    transactions between account holders, or between the account holder and the bundler

    address - Oya account to settle
    address - token contract address
    uint256 - amount to settle
  */
  function settle(address, address, uint256) external;

  /*
    Only bundler can bridge assets to a bookkeeper contract on another chain

    They will do this periodically so that there are enough tokens on each chain for withdrawal
    
    Across is implemented under the hood

    Account holders can specify which chains they are willing to hold their assets on, and the 
    bundler can not transfer more than the total amount allowed by account holders to be on a 
    particular chain

    In practice, the bundler may choose to bridge their own assets to different chains, to 
    facilitate fast withdrawals and optimistic execution of new transactions, while the bulk of 
    funds rest on L1

    address - token contract address
    uint256 - amount to bridge
    uint256 - chain id
  */
  function bridge(address, uint256, uint256) external;

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
