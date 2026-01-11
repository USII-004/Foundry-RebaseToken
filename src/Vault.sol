// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
  // we need to pass the token address to the constructor
  // create a deposit function that mints tokens to the user equivalent to the amount of ETH sent
  // create a redeem function that burns tokens from the user and sends the user ETH
  // create a way to add reawards to the vault

  /*//////////////////////////////////////////////////////////////
                               ERRORS
  //////////////////////////////////////////////////////////////*/
  error Vault__RedeemFailed();


  /*//////////////////////////////////////////////////////////////
                        IMMUTABLE/STATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  IRebaseToken private immutable i_rebaseToken;


  /*//////////////////////////////////////////////////////////////
                               EVENTS
  //////////////////////////////////////////////////////////////*/
  event Deposited(address indexed user, uint256 amount);
  event Redeemed(address indexed user, uint256 amount);


  /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  constructor(IRebaseToken _rebaseToken) {
    i_rebaseToken = _rebaseToken; 
  }


  /*//////////////////////////////////////////////////////////////
                        FALL BACK FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  // fall back function
  receive() external payable {}

  /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
  * @notice Allows users to deposit ETH into the vault and mint rebase tokens in return
  */
  function deposit() external payable {
    // 1. we need to use the amount of ETH the user has sent to mint token to the user
    i_rebaseToken.mint(msg.sender, msg.value);
    emit Deposited(msg.sender, msg.value);
  }

  /**
  * @notice Allows users to redeem their rebase tokens for ETH
  * @param _amount The amount of rebase tokens to redeem 
  */
  function redeem(uint256 _amount) external {
    // 1. we need to burn the user's tokens
    i_rebaseToken.burn(msg.sender, _amount);
    // 2. we need to send the user ETH equivalent to the amount of tokens burned
    (bool success, ) = msg.sender.call{value: _amount}("");
    if(!success) {
      revert Vault__RedeemFailed();
    }
    emit Redeemed(msg.sender, _amount);
  }


  /*//////////////////////////////////////////////////////////////
                        VIEW & PURE FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
  * @notice Get the address of the rebase token
  * @return The address of the rebase token
  */
  function getRebaseTokenAddress() external view returns(address) {
    return address(i_rebaseToken);
  }
}