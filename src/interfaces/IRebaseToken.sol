// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

abstract contract IRebaseToken {
  function mint(address _to, uint256 _amount) external virtual;
  function burn(address _from, uint256 _amount) external virtual;
}