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
    uint256 tokenId,
    uint256 feeCollected,
    uint256 subscriptionPoolRemaining,
    uint256 liquidationStartedAt
  );

  mapping(address => SubscriptionPoolCheckpoint)
    internal _subscriptionCheckpoints;

  uint256 internal subscriptionRate;
  ParamChange[] paramChanges;

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

  function _updatePriceParam(uint256 oldPrice) internal {
    paramChanges.push(
      ParamChange({
        timestamp: block.timestamp,
        priceAtTime: oldPrice,
        rateAtTime: subscriptionRate
      })
    );
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
    uint256 currentPrice,
    uint256 lastModifiedAt,
    uint256 subscriptionPoolRemaining,
    uint256 numOfNfts
  ) internal view returns (uint256) {
    uint256 totalFee;
    uint256 prevIntervalFee;
    uint256 startTime = lastModifiedAt;
    // iterate through all fee changes that have happened since the last checkpoint
    for (uint256 i = 0; i < paramChanges.length; i++) {
      ParamChange memory pc = paramChanges[i];

      if (pc.timestamp > startTime) {
        uint256 intervalFee = numOfNfts *
          SafUtils._calculateSafBetweenTimes(
            pc.priceAtTime,
            startTime,
            pc.timestamp,
            pc.rateAtTime
          );
        totalFee += intervalFee;
        // if the total fee is greater than the subscriptionPool remaining, we know that the subscriptionPool ran out
        if (totalFee > subscriptionPoolRemaining) {
          return totalFee;
        }
        startTime = pc.timestamp;
        prevIntervalFee += intervalFee;
      }
    }

    // calculate the fee for the current interval (i.e. since the last fee change)
    totalFee +=
      numOfNfts *
      SafUtils._calculateSafBetweenTimes(
        currentPrice,
        startTime,
        block.timestamp,
        subscriptionRate
      );

    return totalFee;
  }

  function _updateCheckpoint(address trader, uint256 newSubPool) internal {
    SubscriptionPoolCheckpoint storage cp = _subscriptionCheckpoints[trader];
    cp.subscriptionPoolRemaining = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }
}
