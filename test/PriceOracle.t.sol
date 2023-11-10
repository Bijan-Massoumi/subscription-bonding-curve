// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";

contract PriceOracleTest is HarnessSetup {
  function testPriceOracleWithinPeriod() public {
    uint256 initialPrice = 100;
    harness.exposedUpdatePriceOracle(owner, initialPrice);

    RunningTotal memory rt = harness.exposedGetRunningTotal(owner);
    Common.PriceChange[] memory historicalChanges = harness
      .exposedGetHistoricalPriceChanges(owner);

    assertTrue(rt.lastPrice == 100, "runningtotal should be mutated");

    // Confirm historicalPriceChanges was not appended
    assertTrue(
      historicalChanges.length == 1,
      "historicalPriceChanges should not have been appended"
    );
  }

  function testPriceOracleAfterWarpingTime() public {
    uint256 initialPrice = 100;
    uint256 newPrice = 150;
    uint256 period = harness.exposedGetPeriod() + 1; // 12 hours in seconds

    // Initially update the price oracle
    harness.exposedUpdatePriceOracle(owner, initialPrice);

    // Warp the time by 12 hours
    uint256 newTime = block.timestamp + period;
    vm.warp(newTime);

    // Update the price oracle again
    harness.exposedUpdatePriceOracle(owner, newPrice);

    RunningTotal memory rt = harness.exposedGetRunningTotal(owner);
    Common.PriceChange[] memory historicalChanges = harness
      .exposedGetHistoricalPriceChanges(owner);

    assertTrue(rt.lastPrice == newPrice, "running total should still be 0");
    assertTrue(
      rt.lastUpdateTime == newTime,
      "running total timestamp should be 0"
    );

    // Confirm historicalPriceChanges was appended
    assertTrue(
      historicalChanges.length == 2,
      "historicalPriceChanges should have 2 entry after warping"
    );
    assertEq(
      historicalChanges[1].price,
      initialPrice,
      "Price in historicalPriceChanges should match the initial price after warping"
    );
  }

  function testRunningTotal() public {
    uint256 price1 = 10000;
    uint256 price2 = 11000;
    uint256 price3 = 12000;
    uint256 price4 = 13000;

    uint256 startTime = block.timestamp;

    // Adding the initial price
    vm.warp(startTime + 1 hours);
    harness.exposedUpdatePriceOracle(owner, price1);

    // Add the second price
    vm.warp(startTime + 4 hours);
    harness.exposedUpdatePriceOracle(owner, price2);

    // Add the third price
    vm.warp(startTime + 9 hours);
    harness.exposedUpdatePriceOracle(owner, price3);

    // Add the third price
    vm.warp(startTime + 11 hours);
    harness.exposedUpdatePriceOracle(owner, price4);

    // Warp to exceed the period and trigger the average calculation
    uint256 period = harness.exposedGetPeriod();
    vm.warp(startTime + period + 1);
    harness.exposedUpdatePriceOracle(owner, price4);

    Common.PriceChange[] memory historicalChanges = harness
      .exposedGetHistoricalPriceChanges(owner);
    // Check if the historical change has the TWAP value
    assertTrue(
      historicalChanges.length == 2,
      "historicalPriceChanges should have entries after warping"
    );

    // TWAP calculation
    uint256 weightedPrice1 = price1 * 3 hours * SCALE;
    uint256 weightedPrice2 = price2 * 5 hours * SCALE;
    uint256 weightedPrice3 = price3 * 2 hours * SCALE;

    uint256 totalWeightedPrice = weightedPrice1 +
      weightedPrice2 +
      weightedPrice3;
    uint256 totalDuration = (1 hours + 3 hours + 5 hours + 2 hours) * SCALE;

    uint256 twap = totalWeightedPrice / (totalDuration);
    assertEq(
      historicalChanges[historicalChanges.length - 1].price,
      twap,
      "Price in historicalPriceChanges should match the expected TWAP after warping"
    );

    RunningTotal memory rt = harness.exposedGetRunningTotal(owner);
    assertEq(rt.lastPrice, price4, "lastPrice should match");
    assertEq(
      rt.lastUpdateTime,
      startTime + period + 1,
      "lastUpdateTime should match"
    );
  }

  function testMultipleHistoricalPriceUpdates() public {
    uint256 price1 = 150;
    uint256 price2 = 200;
    uint256 price3 = 250;

    // Warp the time and update the price oracle
    uint256 period = harness.exposedGetPeriod();
    harness.exposedUpdatePriceOracle(owner, price1);
    vm.warp(block.timestamp + period + 1);

    harness.exposedUpdatePriceOracle(owner, price2);
    vm.warp(block.timestamp + 2 * period + 2);

    harness.exposedUpdatePriceOracle(owner, price3);
    vm.warp(block.timestamp + 3 * period + 3);

    // trigger the average calculation
    harness.exposedUpdatePriceOracle(owner, price3);

    Common.PriceChange[] memory historicalChanges = harness
      .exposedGetHistoricalPriceChanges(owner);

    assertTrue(
      historicalChanges.length == 4,
      "historicalPriceChanges should have 4 entries after warping and updating thrice"
    );
    assertEq(historicalChanges[1].price, price1, "Price 1 should match");
    assertEq(historicalChanges[2].price, price2, "Price 2 should match");
    assertEq(historicalChanges[3].price, price3, "Price 3 should match");
  }
}
