// SPDX-License-Identifier: MITs
pragma solidity ^0.8.18;

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
}
