// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/ShareSample.sol";
import "forge-std/console.sol";


contract ShareSampleTest is Test {
  ShareSample shareSample;
  ShareSampleFactory shareSampleFactory;

  address constant sharesSubject = address(0x123);
  address constant withdrawAddress = address(0x456);
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

    uint256 poolRemaining = shareSample.getSubscriptionPoolRemaining(
      sharesSubject
    );
    assertEq(poolRemaining, oneETH);
    // // After buying, supply should be 1
    assertEq(shareSample.getSupply(), 1);

    uint buyPrice = shareSample.getBuyPrice(1);
    // wei
    assertEq(buyPrice, 62500000000000);

    vm.prank(sharesSubject);
    shareSample.buyShares{value: 62500000000000}(1);

    buyPrice = shareSample.getBuyPrice(1);
    console.log(buyPrice);

    vm.prank(sharesSubject);
    vm.expectRevert("Not enough funds to buy shares");
    shareSample.buyShares{value: 62500000000000}(1);

    //  Test selling shares
    vm.prank(sharesSubject);
    shareSample.sellShares(1);

    assertEq(shareSample.getSupply(), 1);
    buyPrice = shareSample.getBuyPrice(1);
    // wei
    assertEq(buyPrice, 62500000000000);
  }

  function testBuySharesWithZeroAmount() public {
    // Initially, supply should be 0
    assertEq(shareSample.getSupply(), 0);

    // Only sharesSubject can buy the first share
    vm.deal(sharesSubject, 20 ether);
    vm.prank(sharesSubject);

    // Attempt to buy shares with 0 amount
    (bool success, ) = address(shareSample).call{value: 0}(
      abi.encodeWithSignature("buyShares(uint256)", 1)
    );
    assertEq(success, false);

    // Supply should still be 0
    assertEq(shareSample.getSupply(), 0);
  }
}
