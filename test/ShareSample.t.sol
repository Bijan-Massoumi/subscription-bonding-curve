// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/ShareSample.sol";
import "forge-std/console.sol";

contract ShareSampleTest is Test {
  ShareSample shareSample;

  address constant sharesSubject = address(0x123);
  address constant withdrawAddress = address(0x456);
  uint256 constant subscriptionRate = 100;
  uint256 constant oneETH = 1 ether;

  function setUp() public {
    shareSample = new ShareSample(
      withdrawAddress,
      subscriptionRate,
      sharesSubject
    );
  }

  function testBuyAndSellShares() public {
    // Initially, supply should be 0
    assertEq(shareSample.getSupply(), 0);

    uint buyPrice = shareSample.getBuyPrice(1);
    console.log(buyPrice);
    // Only sharesSubject can buy the first share
    vm.deal(sharesSubject, 20 ether);
    vm.prank(sharesSubject);    
    shareSample.buyShares{value: oneETH}(1);

    vm.prank(sharesSubject); 
    uint256 poolRemaining = shareSample.getSubscriptionPoolRemaining();    
    console.log(poolRemaining);
  
    // // After buying, supply should be 1
    assertEq(shareSample.getSupply(), 1);

    // // Test selling shares
    // shareSample.sellShares{value: oneETH}(1);

    // // After selling, supply should be 0 again
    // assertEq(shareSample.getSupply(), 0);
  }
}
