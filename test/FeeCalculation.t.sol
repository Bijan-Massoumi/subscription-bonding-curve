// SPDX-License-Identifier: MITs
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";
import "../src/ComputeUtils.sol";

uint256 constant ONE_MONTH = 30 days;

contract FeeCalculationTest is HarnessSetup {
  function _createPriceChanges(
    uint256 t0,
    KeyHarness h
  )
    internal
    returns (
      Common.PriceChange[] memory pcs,
      uint256 t1,
      uint256 t2,
      uint256 t3,
      uint256 endTime
    )
  {
    t1 = t0 + 2 * ONE_MONTH;
    t2 = t0 + 4 * ONE_MONTH;
    t3 = t0 + 6 * ONE_MONTH;
    endTime = block.timestamp + 12 * ONE_MONTH;

    h.exposedAddHistoricalPriceChange(1 ether, t1);
    h.exposedAddHistoricalPriceChange(2 ether, t2);
    h.exposedAddHistoricalPriceChange(1 ether / 2, t3);

    pcs = new Common.PriceChange[](3);
    pcs[0] = Common.PriceChange({
      price: 1 ether,
      rate: uint128(1000),
      startTimestamp: uint112(t1),
      index: 1
    });
    pcs[1] = Common.PriceChange({
      price: 2 ether,
      rate: uint128(1000),
      startTimestamp: uint112(t2),
      index: 2
    });
    pcs[2] = Common.PriceChange({
      price: 1 ether / 2,
      rate: uint128(1000),
      startTimestamp: uint112(t3),
      index: 3
    });

    h.exposedSetPeriodLastOccuredAt(endTime);
  }

  function testFeeCalculationOneContract() public {
    // Mock some PriceChange values for the proofs
    vm.prank(owner);
    subPool.increaseSubscriptionPoolForGroupId{value: 10 ether}(
      keyFactory.getGroupId()
    );

    _buy(harness, owner);

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    (
      Common.PriceChange[] memory pcs,
      uint256 t1,
      uint256 t2,
      uint256 t3,
      uint256 endTime
    ) = _createPriceChanges(t0, harness);
    Proof[] memory proof = new Proof[](1);
    proof[0] = harness.getPriceProof(owner);
    // confirm that proof[0] == pcs
    assertEqUint(proof[0].pcs[0].price, 0);
    assertEqUint(proof[0].pcs[1].price, pcs[0].price);
    assertEqUint(proof[0].pcs[2].price, pcs[1].price);
    assertEqUint(proof[0].pcs[3].price, pcs[2].price);
    vm.warp(endTime);

    Common.ContractInfo[] memory traderContracts = subPool.getTraderContracts(
      owner,
      keyFactory.getGroupId()
    );
    assertEqUint(traderContracts.length, 1);
    assertEq(traderContracts[0].keyContract, address(harness));

    uint256 fee = harness.exposedVerifyAndCollectFees(
      traderContracts,
      owner,
      t0,
      proof
    );

    // Validate the calculated fee against the expected fee:
    assertEq(
      fee,
      ComputeUtils._calculateFeeBetweenTimes(0, t0, t1, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(0.5 ether, t3, endTime, 1000),
      "The fee does not match the expected value"
    );

    vm.stopPrank();
  }

  function testFeeCalculationTwoContracts() public {
    vm.prank(owner);
    subPool.increaseSubscriptionPoolForGroupId{value: 10 ether}(
      keyFactory.getGroupId()
    );
    _buy(harness, owner);
    _buy(harness2, owner);

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    (
      ,
      uint256 t1,
      uint256 t2,
      uint256 t3,
      uint256 endTime
    ) = _createPriceChanges(t0, harness);
    _createPriceChanges(t0, harness2);

    Common.ContractInfo[] memory traderContracts = subPool.getTraderContracts(
      owner,
      keyFactory.getGroupId()
    );
    Proof[] memory proof = _getProofForContracts(owner, harness);
    assertEqUint(proof.length, 2);

    vm.warp(endTime);
    uint256 fee = harness.exposedVerifyAndCollectFees(
      traderContracts,
      owner,
      t0,
      proof
    );

    uint256 expectedSingle = ComputeUtils._calculateFeeBetweenTimes(
      0,
      t0,
      t1,
      1000
    ) +
      ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, 1000) +
      ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, 1000) +
      ComputeUtils._calculateFeeBetweenTimes(0.5 ether, t3, endTime, 1000);

    assertEq(
      fee,
      expectedSingle * 2,
      "The fee does not match the expected value"
    );

    vm.warp(endTime);
  }

  function testFeeCalculationThreeContractsWithOffset() public {
    vm.prank(owner);
    subPool.increaseSubscriptionPoolForGroupId{value: 10 ether}(
      keyFactory.getGroupId()
    );
    _buy(harness, owner);
    _buy(harness2, owner);
    _buy(harness3, owner);

    vm.startPrank(owner);

    uint256 t0 = block.timestamp;
    uint256 endTimeFinal;
    uint256 expected;
    {
      (
        ,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 endTime
      ) = _createPriceChanges(t0, harness);
      _createPriceChanges(t0, harness2);

      uint256 expectedSingle = ComputeUtils._calculateFeeBetweenTimes(
        0,
        t0,
        t1,
        1000
      ) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(0.5 ether, t3, endTime, 1000);

      expected += expectedSingle * 2;
      endTimeFinal = endTime;
    }

    {
      // Create a third set of price changes that start at t0 + 1 day
      (, uint256 t11, uint256 t22, uint256 t33, ) = _createPriceChanges(
        t0 + 1 days,
        harness3
      );

      uint256 expectedSecond = ComputeUtils._calculateFeeBetweenTimes(
        0,
        t0 + 1 days,
        t11,
        1000
      ) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t11, t22, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t22, t33, 1000) +
        ComputeUtils._calculateFeeBetweenTimes(
          0.5 ether,
          t33,
          endTimeFinal,
          1000
        );

      expected += expectedSecond;
    }

    vm.warp(endTimeFinal);
    Proof[] memory proof = _getProofForContracts(owner, harness);
    assertEqUint(proof.length, 3);
    uint256 fee = harness.exposedVerifyAndCollectFees(
      subPool.getTraderContracts(owner, keyFactory.getGroupId()),
      owner,
      t0,
      proof
    );

    assertEq(fee, expected, "The fee does not match the expected value");
  }
}
