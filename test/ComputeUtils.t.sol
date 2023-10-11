// SPDX-License-Identifier: MITs
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ComputeUtils.sol";
import "forge-std/console.sol";

contract ComputeUtilsTest is Test {
  function testSinglePriceChange() public {
    uint256 currentTime = block.timestamp;

    Common.PriceChange[] memory recentPriceChanges = new Common.PriceChange[](
      1
    );

    recentPriceChanges[0] = Common.PriceChange({
      price: 100,
      rate: 0,
      startTimestamp: uint112(currentTime + 2 hours),
      index: 0
    });

    uint256 averagePrice = ComputeUtils.calculateTimeWeightedAveragePrice(
      recentPriceChanges,
      currentTime + 12 hours
    );
    assertEq(
      averagePrice,
      100,
      "Average price should match single price change value"
    );
  }

  function testTimeWeightedAveragePrice3() public {
    uint256 startTime = block.timestamp;

    Common.PriceChange[] memory recentPriceChanges = new Common.PriceChange[](
      3
    );

    recentPriceChanges[0] = Common.PriceChange({
      price: 100,
      rate: 0,
      startTimestamp: uint112(startTime),
      index: 0
    });
    recentPriceChanges[1] = Common.PriceChange({
      price: 150,
      rate: 0,
      startTimestamp: uint112(startTime + 4 hours),
      index: 1
    });
    recentPriceChanges[2] = Common.PriceChange({
      price: 175,
      rate: 0,
      startTimestamp: uint112(startTime + 10 hours),
      index: 2
    });

    uint256 twap = ComputeUtils.calculateTimeWeightedAveragePrice(
      recentPriceChanges,
      startTime + 15 hours
    );

    assertEq(twap, 145, "Incorrect TWAP");
  }

  function testCalculateFeeForOneDay() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      100 ether, // totalStatedPrice
      0, // startTime
      1 days, // endTime
      10
    );
    uint256 expectedFeeNumerator = 100 ether * 1 days * 10;
    uint256 expectedFee = expectedFeeNumerator / 365 days / 10000; // As feeRate is in thousandths
    assertEq(fee, expectedFee, "Fee does not match expected for one day");
  }

  function testCalculateFeeForHalfYear() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      200 ether, // totalStatedPrice
      0, // startTime
      182 days, // endTime (half year)
      5
    );
    uint256 expectedFeeNumerator = 200 ether * 182 days * 5;
    uint256 expectedFee = expectedFeeNumerator / 365 days / 10000; // As feeRate is in thousandths
    assertEq(fee, expectedFee, "Fee does not match expected for half year");
  }

  function testCalculateFeeWithNoTimeElapsed() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      150 ether, // totalStatedPrice
      50, // startTime
      50, // endTime (no time elapsed)
      20
    );
    assertEq(fee, 0, "Fee should be zero when no time has elapsed");
  }

  function testCalculateFeeWithNoRate() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      150 ether, // totalStatedPrice
      0, // startTime
      100 days, // endTime
      0 // feeRate (0%)
    );
    assertEq(fee, 0, "Fee should be zero when rate is zero");
  }
}
