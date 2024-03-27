pragma solidity ^0.8.6;

import "../interfaces/BookkeeperInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Bookkeeper is BookkeeperInterface, Ownable {

}