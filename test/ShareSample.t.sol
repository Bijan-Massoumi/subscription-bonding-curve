// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/ShareSample.sol";

contract ShareSampleTest is Test {
  ShareSample shareSample;
  ShareSampleFactory shareSampleFactory;

  address constant sharesSubject = address(0x123);
  address constant withdrawAddress = address(0x456);
  uint256 constant subscriptionRate = 100;
  uint256 constant oneETH = 1 ether;

  function setUp() public {
    vm.prank(sharesSubject);
    shareSampleFactory = new ShareSampleFactory();
    vm.prank(sharesSubject);
    shareSampleFactory.createShareSample(sharesSubject);
    shareSample = ShareSample(shareSampleFactory.newShareSample()); // Retrieve the address of the newly created ShareSample
  }

  function testBuyAndSellShares() public {
    // Initially, supply should be 0
    assertEq(shareSample.getSupply(), 0);

    // Only sharesSubject can buy the first share
    vm.deal(sharesSubject, 20 ether);
    vm.prank(sharesSubject);
    shareSample.buyShares{value: oneETH}(1);

    uint256 poolRemaining = shareSample.getSubscriptionPoolRemaining(sharesSubject);
    assertEq(poolRemaining, oneETH);
    // // After buying, supply should be 1
    assertEq(shareSample.getSupply(), 1);

    uint buyPrice = shareSample.getBuyPrice(1);
    // wei
    assertEq(buyPrice, 62500000000000);

    vm.prank(sharesSubject);
    shareSample.buyShares{value: 62500000000000}(1);

    //  Test selling shares
    vm.prank(sharesSubject);
    shareSample.sellShares(1);

    assertEq(shareSample.getSupply(), 1);
    buyPrice = shareSample.getBuyPrice(1);
    // wei
    assertEq(buyPrice, 62500000000000);
  }
}
