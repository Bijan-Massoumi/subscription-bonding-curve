// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";

contract PriceOracleTest is HarnessSetup {
  function testPriceOracleWithinPeriod() public {
    uint256 initialPrice = 100;
    harnass.exposedUpdatePriceOracle(initialPrice);

    Common.PriceChange[] memory recentChanges = harnass
      .exposedGetRecentPriceChanges();
    Common.PriceChange[] memory historicalChanges = harnass
      .exposedGetHistoricalPriceChanges();

    // Confirm recentPriceChanges was appended
    assertTrue(
      recentChanges.length == 1,
      "recentPriceChanges should have 1 entry"
    );
    assertEq(
      recentChanges[0].price,
      initialPrice,
      "Price in recentPriceChanges should match the initial price"
    );

    // Confirm historicalPriceChanges was not appended
    assertTrue(
      historicalChanges.length == 1,
      "historicalPriceChanges should not have been appended"
    );
  }

  function testPriceOracleAfterWarpingTime() public {
    uint256 initialPrice = 100;
    uint256 newPrice = 150;
    uint256 period = harnass.exposedGetPeriod() + 1; // 12 hours in seconds

    // Initially update the price oracle
    harnass.exposedUpdatePriceOracle(initialPrice);

    // Warp the time by 12 hours
    vm.warp(block.timestamp + period);

    // Update the price oracle again
    harnass.exposedUpdatePriceOracle(newPrice);

    Common.PriceChange[] memory recentChanges = harnass
      .exposedGetRecentPriceChanges();
    Common.PriceChange[] memory historicalChanges = harnass
      .exposedGetHistoricalPriceChanges();

    // Confirm recentPriceChanges was cleared
    assertTrue(
      recentChanges.length == 1,
      "recentPriceChanges should have 1 entry after warping"
    );
    assertEq(
      recentChanges[0].price,
      150,
      "Price in recentPriceChanges should match the new price after warping"
    );

    // Confirm historicalPriceChanges was appended
    assertTrue(
      historicalChanges.length == 2,
      "historicalPriceChanges should have 1 entry after warping"
    );
    assertEq(
      historicalChanges[1].price,
      initialPrice,
      "Price in historicalPriceChanges should match the initial price after warping"
    );
  }

  function testTimeWeightedAveragePrice() public {
    uint256 price1 = 10000;
    uint256 price2 = 11000;
    uint256 price3 = 12000;
    uint256 price4 = 13000;

    uint256 startTime = block.timestamp;
    Common.PriceChange[] memory recentPriceChanges = new Common.PriceChange[](
      4
    );

    recentPriceChanges[0] = Common.PriceChange({
      price: price1,
      rate: 0,
      startTimestamp: uint112(startTime + 1 hours),
      index: 0
    });
    recentPriceChanges[1] = Common.PriceChange({
      price: price2,
      rate: 0,
      startTimestamp: uint112(startTime + 4 hours),
      index: 1
    });
    recentPriceChanges[2] = Common.PriceChange({
      price: price3,
      rate: 0,
      startTimestamp: uint112(startTime + 9 hours),
      index: 2
    });
    recentPriceChanges[3] = Common.PriceChange({
      price: price4,
      rate: 0,
      startTimestamp: uint112(startTime + 11 hours),
      index: 3
    });

    // Adding the initial price
    vm.warp(startTime + 1 hours);
    harnass.exposedUpdatePriceOracle(price1);

    // Add the second price
    vm.warp(startTime + 4 hours);
    harnass.exposedUpdatePriceOracle(price2);

    // Add the third price
    vm.warp(startTime + 9 hours);
    harnass.exposedUpdatePriceOracle(price3);

    // Add the third price
    vm.warp(startTime + 11 hours);
    harnass.exposedUpdatePriceOracle(price4);

    // Warp to exceed the period and trigger the average calculation
    uint256 period = harnass.exposedGetPeriod();
    vm.warp(startTime + period + 1);
    harnass.exposedUpdatePriceOracle(price4);

    Common.PriceChange[] memory historicalChanges = harnass
      .exposedGetHistoricalPriceChanges();
    // Check if the historical change has the TWAP value
    assertTrue(
      historicalChanges.length == 2,
      "historicalPriceChanges should have entries after warping"
    );
    assertEq(
      historicalChanges[historicalChanges.length - 1].price,
      ComputeUtils.calculateTimeWeightedAveragePrice(
        recentPriceChanges,
        startTime + period + 1
      ),
      "Price in historicalPriceChanges should match the expected TWAP after warping"
    );
  }

  function testMultipleHistoricalPriceUpdates() public {
    uint256 price1 = 150;
    uint256 price2 = 200;
    uint256 price3 = 250;

    // Warp the time and update the price oracle
    uint256 period = harnass.exposedGetPeriod();
    harnass.exposedUpdatePriceOracle(price1);
    vm.warp(block.timestamp + period + 1);

    harnass.exposedUpdatePriceOracle(price2);
    vm.warp(block.timestamp + 2 * period + 2);

    harnass.exposedUpdatePriceOracle(price3);
    vm.warp(block.timestamp + 3 * period + 3);

    // trigger the average calculation
    harnass.exposedUpdatePriceOracle(price3);

    Common.PriceChange[] memory historicalChanges = harnass
      .exposedGetHistoricalPriceChanges();

    assertTrue(
      historicalChanges.length == 4,
      "historicalPriceChanges should have 4 entries after warping and updating thrice"
    );
    assertEq(historicalChanges[1].price, price1, "Price 1 should match");
    assertEq(historicalChanges[2].price, price2, "Price 2 should match");
    assertEq(historicalChanges[3].price, price3, "Price 3 should match");
  }
}
