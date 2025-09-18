// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^4.9.6
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Oya Token
 * @author Oya Protocol Team
 * @notice ERC20 token implementation for the Oya protocol with minting capabilities
 * @dev Extends OpenZeppelin's ERC20, Ownable, and ERC20Permit contracts
 *
 * This contract provides:
 * - Standard ERC20 functionality with permit support
 * - Owner-controlled minting for protocol token distribution
 *
 * Security considerations:
 * - Only the owner can mint new tokens via `mint`
 * - Transfers follow standard ERC20 semantics; no custom SafeERC20 wrappers are used here
 * - No reentrancy guards are needed for ERC20 state changes in this contract
 */
contract Oya is ERC20, Ownable, ERC20Permit {

    /**
     * @notice Contract constructor that initializes the token
     * @dev Mints initial supply of 1 billion tokens to deployer
     * @custom:supply Initial supply is minted at deployment; additional supply can be minted by owner
     */
  constructor() ERC20("Oya", "OYA") Ownable() ERC20Permit("Oya") {
    _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
  }

    /**
     * @notice Mints new tokens to specified address
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint
     * @dev Only callable by contract owner. Used for protocol token distribution.
     * @custom:security Increases total supply; consider appropriate off-chain governance controls
     * @custom:events Emits ERC20. Transfer event (from zero address)
     */
  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  }

}
