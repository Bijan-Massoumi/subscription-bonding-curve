// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./errors/ISubscriptionPoolErrors.sol";
import "forge-std/console.sol";
import "./Common.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

abstract contract SubscriptionPool is ISubscriptionPoolErrors {
  event PoolAdjusted(address keySubject, uint256 newPool);

  mapping(address trader => uint256 checkpoint)
    internal _subscriptionCheckpoints;

  // min percentage (10%) of total stated price that
  // move to groupInfo
  uint256 internal minimumPoolRatio = 100000000000000000;
  // 100% pool percent
  uint256 internal maxMinimumPoolRatio = 1 ether;

  function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
    minimumPoolRatio = newMinimumPoolRatio;
  }

  function getSubscriptionPool(address trader) public view returns (uint256) {
    return _subscriptionCheckpoints[trader];
  }

  function _updateTraderPool(address trader, uint256 newSubPool) internal {
    _subscriptionCheckpoints[trader] = newSubPool;
    emit PoolAdjusted(trader, newSubPool);
  }
}
