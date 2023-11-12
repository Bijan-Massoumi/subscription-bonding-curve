// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/IntegratedSetup.t.sol";
import "forge-std/console.sol";

contract BondingCurveTest is IntegratedSetup {
  // Test buying from a supply of 0 with an amount
  function testBuyFromZeroSupply() public {
    uint256 supply = 0;
    uint256 amount = 10;
    uint256 expectedPrice = subKey.getPrice(supply, amount);
    // Expected price should be more than 0
    assertGt(
      expectedPrice,
      0,
      "Price should be greater than zero when buying from zero supply"
    );
  }

  // Test selling down to a supply of 0
  function testSellDownToZeroSupply() public {
    uint256 supply = 10;
    uint256 amount = 10;
    uint256 priceAfter = subKey.getPrice(supply - amount, 0);
    // Price after selling the entire supply should be 0
    assertEq(
      priceAfter,
      0,
      "Price should be zero after selling down to zero supply"
    );
  }

  // Test buying up the curve with increasing amounts
  function testBuyUpCurve() public {
    uint256 supply = 0;
    uint256 amount = 1;
    uint256 lastPrice = 0;

    for (uint i = 0; i < 5; i++) {
      uint256 currentPrice = subKey.getPrice(supply, amount);
      assertGt(
        currentPrice,
        lastPrice,
        "Price should increase with each additional purchase"
      );
      lastPrice = currentPrice;
      supply += amount;
      amount += 1; // Increase the amount for the next iteration
    }
  }

  // Test selling down the curve with mixed amounts
  function testSellDownCurve() public {
    uint256 supply = 50;
    uint256 amount = 10;
    uint256 lastPrice = subKey.getPrice(supply, supply);

    for (uint i = 0; i < 5; i++) {
      supply -= amount;
      uint256 currentPrice = subKey.getPrice(supply, supply);
      assertLt(currentPrice, lastPrice, "Price should decrease with each sale");
      lastPrice = currentPrice;
    }
    assertEq(subKey.getPrice(supply, supply), 0);
  }

  function testCumulativeCalculation() public {
    assertEq(
      subKey.getPrice(1, 1) + subKey.getPrice(2, 10),
      subKey.getPrice(1, 11)
    );

    uint256 priceForFirst = subKey.getPrice(0, 1);
    uint256 priceForNextTwo = subKey.getPrice(1, 2);
    uint256 priceForNextTen = subKey.getPrice(3, 10); // Starts at 3 because 0->1 and then 1->3
    uint256 cumulativePriceForThirteen = subKey.getPrice(0, 13); // Total price for 13 tokens

    assertEq(
      priceForFirst + priceForNextTwo + priceForNextTen,
      cumulativePriceForThirteen,
      "Cumulative pricing does not match"
    );
  }
}
