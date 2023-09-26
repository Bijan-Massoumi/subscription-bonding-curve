// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafUtils.sol";
import "./ISubscriptionPoolTrackerErrors.sol";

struct SubscriptionPoolCheckpoint {
  uint256 subscriptionPoolRemaining;
  uint256 lastModifiedAt;
}

struct ParamChange {
  uint256 timestamp;
  uint256 priceAtTime;
  uint256 rateAtTime;
}

abstract contract SubscriptionPoolTracker is ISubscriptionPoolTrackerErrors {
  event FeeCollected(
    uint256 feeCollected,
    uint256 subscriptionPoolRemaining,
    uint256 liquidationStartedAt
  );

  mapping(address => SubscriptionPoolCheckpoint)
    internal _subscriptionCheckpoints;

  uint256 internal subscriptionRate;
  ParamChange[] paramChanges;
  mapping(address => uint256) internal lastParamChangeIndex;

  // min percentage (10%) of total stated price that
  // must be convered by subscriptionPool
  uint256 internal minimumPoolRatio = 1000;
  // 100% fee rate
  uint256 internal maxSubscriptionRate = 10000;
  // 100% pool percent
  uint256 internal maxMinimumPoolRatio = 10000;

  constructor(uint256 _subscriptionRate) {
    subscriptionRate = _subscriptionRate;
  }

  function _setSubscriptionRate(
    uint256 currentPrice,
    uint256 newSubscriptionRate
  ) internal {
    paramChanges.push(
      ParamChange({
        timestamp: block.timestamp,
        priceAtTime: currentPrice,
        rateAtTime: subscriptionRate
      })
    );
    subscriptionRate = newSubscriptionRate;
  }

  function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
    minimumPoolRatio = newMinimumPoolRatio;
  }

  function _getMinimumPool(
    uint256 currentPrice
  ) internal view returns (uint256) {
    return (currentPrice * minimumPoolRatio) / 10000;
  }

  function _getSubscriptionPoolRemaining(
    address owner,
    uint256 amount,
    uint256 currentPrice
  ) internal view returns (uint256, uint256) {
    SubscriptionPoolCheckpoint memory checkpoint = _subscriptionCheckpoints[
      owner
    ];
    uint256 feesToCollect = _calculateFees(
      owner,
      currentPrice,
      checkpoint.lastModifiedAt,
      checkpoint.subscriptionPoolRemaining,
      amount
    );

    if (feesToCollect >= checkpoint.subscriptionPoolRemaining) {
      return (0, feesToCollect);
    }
    return (
      checkpoint.subscriptionPoolRemaining - feesToCollect,
      feesToCollect
    );
  }

  function _calculateFees(
    address trader,
    uint256 currentPrice,
    uint256 lastModifiedAt,
    uint256 subscriptionPoolRemaining,
    uint256 numOfNfts
  ) internal view returns (uint256) {
    uint256 totalFee;
    uint256 prevIntervalFee;
    uint256 startTime = lastModifiedAt;
    uint256 startIndex = lastParamChangeIndex[trader]; // Start from the last index that affected the trader

    for (uint256 i = startIndex; i < paramChanges.length; i++) {
      ParamChange memory pc = paramChanges[i];
      if (pc.timestamp > startTime) {
        uint256 intervalFee = numOfNfts *
          SafUtils._calculateFeeBetweenTimes(
            pc.priceAtTime,
            startTime,
            pc.timestamp,
            pc.rateAtTime
          );
        totalFee += intervalFee;
        if (totalFee > subscriptionPoolRemaining) {
          return totalFee;
        }
        startTime = pc.timestamp;
        prevIntervalFee += intervalFee;
      }
    }

    totalFee +=
      numOfNfts *
      SafUtils._calculateFeeBetweenTimes(
        currentPrice,
        startTime,
        block.timestamp,
        subscriptionRate
      );

    return totalFee;
  }

  function _updateCheckpoints(
    address trader,
    uint256 currPrice,
    uint256 newSubPool
  ) internal {
    // update pool checkpoint
    _updateTraderPool(trader, newSubPool);

    // update price checkpoint
    paramChanges.push(
      ParamChange({
        timestamp: block.timestamp,
        priceAtTime: currPrice,
        rateAtTime: subscriptionRate
      })
    );
    lastParamChangeIndex[trader] = paramChanges.length > 0
      ? paramChanges.length - 1
      : 0;
  }

  function _updateTraderPool(address trader, uint256 newSubPool) internal {
    SubscriptionPoolCheckpoint storage cp = _subscriptionCheckpoints[trader];
    cp.subscriptionPoolRemaining = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }
}
