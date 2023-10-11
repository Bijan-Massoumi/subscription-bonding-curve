// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "./Common.sol";

uint256 constant SCALE = 1e4;

library ComputeUtils {
  uint256 constant secondsInYear = 365 days;

  function _calculateFeeBetweenTimes(
    uint256 totalStatedPrice,
    uint256 startTime,
    uint256 endTime,
    uint256 feeRate
  ) internal pure returns (uint256 feeToReap) {
    feeToReap =
      (feeRate * totalStatedPrice * (endTime - startTime)) /
      (secondsInYear * SCALE);
  }

  function calculateTimeWeightedAveragePrice(
    Common.PriceChange[] memory recentPriceChanges,
    uint256 currentTime
  ) internal pure returns (uint256 averagePrice) {
    uint256 totalWeightedPrice = 0;
    uint256 totalDuration = 0;

    // If there's at least one price change in the recent changes
    if (recentPriceChanges.length > 0) {
      // Calculate the time-weighted average
      for (uint256 i = 0; i < recentPriceChanges.length; i++) {
        uint256 duration;
        if (i == recentPriceChanges.length - 1) {
          duration = currentTime - recentPriceChanges[i].startTimestamp;
        } else {
          duration =
            recentPriceChanges[i + 1].startTimestamp -
            recentPriceChanges[i].startTimestamp;
        }

        totalWeightedPrice += duration * recentPriceChanges[i].price;
        totalDuration += duration;
      }
    }
    return totalWeightedPrice / totalDuration;
  }
}
