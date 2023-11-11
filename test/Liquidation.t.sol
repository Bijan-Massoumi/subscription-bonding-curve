// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/HarnessSetup.t.sol";
import "forge-std/console.sol";

contract LiquidationTest is HarnessSetup, ISubscriptionKeysErrors {
  function testSingleLiquidation() public {
    vm.deal(owner, 100 ether);
    vm.startPrank(owner);

    Proof[] memory proof;
    proof = harness.getPriceProof(owner);
    harness.buyKeys{value: 1 ether}(owner, 10, proof);
    uint256 price = harness.getCurrentPrice(owner);

    uint256 warpTime = block.timestamp + 12 hours;
    vm.warp(warpTime);
    proof = harness.getPriceProof(owner);
    harness.buyKeys{value: 1 ether}(owner, 1, proof);

    Common.PriceChange[] memory pc = harness.exposedGetHistoricalPriceChanges(
      owner
    );
    assertEqUint(pc.length, 2);
    assertEqUint(pc[1].price, price);
    uint256 subPool = harness.getSubscriptionPool(owner);
    uint256 depletionTime = ComputeUtils._getTimeBondDepleted(
      harness.balanceOf(owner, owner) * price,
      warpTime,
      subPool,
      feeRate
    );
    vm.stopPrank();

    vm.startPrank(addr1);
    vm.warp(depletionTime - 1);
    proof = harness.getPriceProof(owner);
    vm.expectRevert(abi.encodeWithSelector(CannotLiquidate.selector));
    harness.liquidateSubscriber(owner, owner, proof, 1);

    vm.warp(depletionTime + 1);
    uint256 initialOwnerBalance = owner.balance;
    uint256 initialAddr1Balance = addr1.balance;
    uint256 initialDestinationBalance = destination.balance;
    uint256 sellPrice = harness.getSellPrice(owner, 11);
    uint256 protocolFee = harness.getProtocalFee(sellPrice);
    uint256 liquidatorPayment = harness.getLiquidationPayment(
      sellPrice - protocolFee
    );

    (, uint256 fees) = harness.exposedGetFeeBreakdown(
      harness.getTraderSubjectInfo(owner),
      owner,
      harness.getPriceProof(owner)
    );
    subPool = harness.getSubscriptionPool(owner);
    harness.liquidateSubscriber(owner, owner, harness.getPriceProof(owner), 11);
    vm.stopPrank();

    assertGt(fees, subPool, "Fees should be > pool");
    // Assert that the balances have increased by the expected amounts
    assertEq(
      initialAddr1Balance + liquidatorPayment,
      addr1.balance,
      "Liquidator payment incorrect"
    );
    assertEq(
      initialDestinationBalance + protocolFee,
      destination.balance,
      "Protocol fee incorrect"
    );
    assertEq(
      initialOwnerBalance +
        subPool +
        (sellPrice - liquidatorPayment - protocolFee),
      owner.balance,
      "Subscriber payment incorrect"
    );
  }
}
