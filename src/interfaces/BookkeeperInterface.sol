pragma solidity ^0.8.6;

interface BookkeeperInterface {
  /*
    What functions are necessary for the bookkeeper to be able to hold ERC20, ERC721, and ERC1155
    tokens? 
  */

  /*
    Only bundler can propose a bundle

    The bundle will be mapped to an incrementing id

    This will call UMA to validate the bundle

    We need to look into data availability solutions for the bundle data

    Maybe we can store the data in blobs?

    bytes32 - where to find the bundle data
  */
  function propose(bytes32) external;

  /*
    Only bundler can finalize a bundle
  
    Calls internal sync function to update bookkeeper contracts on all chains with the latest
    bundle information

    uint256 - bundle id to finalize, which must have been validated with UMA already
  */
  function finalize(uint256) external;

  /*
    Only bundler can cancel a bundle

    If they made a mistake in a proposal, canceling a bundle lets them propose a new one with 
    the next nonce

    uint256 - bundle id to cancel
  */
  function cancel(uint256) external;

  /*
    Anyone can settle with an Oya account, but in practice the bundler will do this

    This will transfer funds from the Oya account holder's Safe to the bookkeeper contract

    Holding funds in the bookkeeper is better for efficiency, and necessary when settling 
    transactions between account holders, or between the account holder and the bundler

    address - Oya account to settle
    address - token contract address
    uint256 - amount to settle
  */
  function sweep(address, address, uint256) external;

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

  /*
    Oya governance can add and remove bundlers

    address - bundler to add or remove
  */
  function addBundler(address) external;
  function removeBundler(address) external;

  /*
    Oya governance can add and remove bookkeeper contracts for different chains

    This should be on a timelock, to allow for ragequit if an account holder disapproves of
    a bookkeeper contract upgrade

    The upgrade process would simply allow asset bridging to the new bookkeeper contract

    This function should be called on L1 and sync across all chains

    To remove a bookkeeper, without replacing it, set to the zero address

    uint256 - chain id
    address - bookkeeper contract address to add or remove
    bool - Says whether to add or remove
  */
  function updateBookkeeper(uint256, address, bool) external;
}
