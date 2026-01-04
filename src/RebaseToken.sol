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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*
* @title RebaseToken
* @author Awwal Onivehu Usman (DevUsii)
* @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards
* @notice The interest rate in this smart contract can only decrease
* @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
*/

contract RebaseToken is ERC20 {
  /*//////////////////////////////////////////////////////////////
                               ERRORS
  //////////////////////////////////////////////////////////////*/
  error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);


  /*//////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  event InterestRateSet(uint256 newInterestRate);


  /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
  //////////////////////////////////////////////////////////////*/
  uint256 private constant PRECISION_FACTOR = 1e18;

  uint256 public s_interestRate = 5e10;
  mapping(address => uint256) private s_userInterestRate;
  mapping(address => uint256) private s_userLastUpdatedTimestamp;


  /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  constructor() ERC20("Rebase Token", "RBT") {}


  /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /*
  * @notice Set the interest rate in the contract
  * @param _newInterestRate The new interest rate to set
  * @dev The interest rate can only decrease
  */

  function setInterestRate(uint256 _newInterestRate) external {
    // set the interest rate
    if(_newInterestRate > s_interestRate) {
      revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
    }
    s_interestRate = _newInterestRate;
    emit InterestRateSet(_newInterestRate);
  }

  /*
  * @notice Mint the user token when they deposit into the vault
  * @param _to The user to mint the token to
  * @param _amount The amount of tokens to mint
  */
  function mint(address _to, uint256 _amount) external {
    _mintAccruedInterest(_to);
    s_userInterestRate[_to] = s_interestRate;
    _mint(_to, _amount);
  }


  /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*
  * @notice Calculate the accumulated interest for the user since their last update
  * @param _user The user to calculate the interest for
  * @return The accumulated interest for the user since their last update
  */
  function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns(uint256 linearInterest) {
    // we need to calculate the interest rate that has accumulated since the last update
    // this is going to be a linear growth with time
    // 1. Calculate the time since the last update
    // 2. calculate the amount of linear growth
    // 3. return the amount of linear growth
    uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
    linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
  }

  function _mintAccruedInterest(address _user) internal {
    // (1) find their current balance of rebase tokens thta have been minted to the user -> principle balance
    // (2) calculate their current balance including any interest -> balanceOf
    // calculate the number of tokens that need to be minted to the user -> (2) - (1)
    // call _mint to mint the tokens to the user
    // set the users last updated timestamp
    s_userLastUpdatedTimestamp[_user] = block.timestamp;
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW & PURE FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /*
  * @notice Gets the interest rate for the user
  * @param _user The user to get the interest rate for
  * @return The interest rate for the user
  */
  function getUserInterestRate(address _user) external view returns(uint256) {
    return s_userInterestRate[_user];
  }

  /*
  * @notice Gets the balance of the user including any accrued interest
  * @param _user The user to get the balance for
  * @return The balance of the user including any accrued interest
  */
  function balanceOf(address _user) public view override returns(uint256) {
    // get the current principle balance of the user (The number of tokens that have actually been minted to the user)
    // multiply the principle balance by the interest that has accumulated in the time since the interest was last updated
    return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
  }
}