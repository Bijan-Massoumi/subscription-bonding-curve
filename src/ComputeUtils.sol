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
}
