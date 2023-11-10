// SPDX-License-Identifier: MITs
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";
import {ISubscriptionKeysErrors} from "../src/errors/ISubscriptionKeysErrors.sol";
import "../src/ComputeUtils.sol";

uint256 constant ONE_MONTH = 30 days;

contract FeeCalculationTest is HarnessSetup, ISubscriptionKeysErrors {
  function _createPriceChanges(
    uint256 t0,
    address keySubject
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

    harness.exposedAddHistoricalPriceChange(keySubject, 1 ether, t1);
    harness.exposedAddHistoricalPriceChange(keySubject, 2 ether, t2);
    harness.exposedAddHistoricalPriceChange(keySubject, 1 ether / 2, t3);

    pcs = new Common.PriceChange[](3);
    pcs[0] = Common.PriceChange({
      price: 1 ether,
      rate: uint128(tenPercent),
      startTimestamp: uint112(t1),
      index: 1
    });
    pcs[1] = Common.PriceChange({
      price: 2 ether,
      rate: uint128(tenPercent),
      startTimestamp: uint112(t2),
      index: 2
    });
    pcs[2] = Common.PriceChange({
      price: 1 ether / 2,
      rate: uint128(tenPercent),
      startTimestamp: uint112(t3),
      index: 3
    });

    harness.exposedSetPeriodLastOccuredAt(keySubject, endTime);
  }

  function testFeeCalculationOneContract() public {
    // Mock some PriceChange values for the proofs
    _buy(owner, owner);

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    (
      Common.PriceChange[] memory pcs,
      uint256 t1,
      uint256 t2,
      uint256 t3,
      uint256 endTime
    ) = _createPriceChanges(t0, owner);
    Proof[] memory proof;
    proof = harness.getPriceProof(owner);
    // confirm that proof[0] == pcs
    assertEqUint(proof[0].pcs[0].price, 0);
    assertEqUint(proof[0].pcs[1].price, pcs[0].price);
    assertEqUint(proof[0].pcs[2].price, pcs[1].price);
    assertEqUint(proof[0].pcs[3].price, pcs[2].price);
    vm.warp(endTime);

    Common.SubjectTraderInfo[] memory subInfo = harness.getTraderSubjectInfo(
      owner
    );
    assertEqUint(subInfo.length, 1);
    assertEq(subInfo[0].keySubject, owner);

    (, uint256 fee) = harness.exposedGetFeeBreakdown(subInfo, owner, proof);

    // Validate the calculated fee against the expected fee:
    assertEq(
      fee,
      ComputeUtils._calculateFeeBetweenTimes(0, t0, t1, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(
          0.5 ether,
          t3,
          endTime,
          tenPercent
        ),
      "The fee does not match the expected value"
    );

    vm.stopPrank();
  }

  function testFeeCalculationTwoContracts() public {
    vm.prank(owner);
    _buy(owner, owner);
    _buy(owner, addr1);

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    (
      ,
      uint256 t1,
      uint256 t2,
      uint256 t3,
      uint256 endTime
    ) = _createPriceChanges(t0, owner);
    _createPriceChanges(t0, addr1);

    Common.SubjectTraderInfo[] memory subInfo = harness.getTraderSubjectInfo(
      owner
    );
    Proof[] memory proof = harness.getPriceProof(owner);
    assertEqUint(proof.length, 2);

    vm.warp(endTime);
    (, uint256 fee) = harness.exposedGetFeeBreakdown(subInfo, owner, proof);

    uint256 expectedSingle = ComputeUtils._calculateFeeBetweenTimes(
      0,
      t0,
      t1,
      tenPercent
    ) +
      ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, tenPercent) +
      ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, tenPercent) +
      ComputeUtils._calculateFeeBetweenTimes(
        0.5 ether,
        t3,
        endTime,
        tenPercent
      );

    assertEq(
      fee,
      expectedSingle * 2,
      "The fee does not match the expected value"
    );

    vm.warp(endTime);
  }

  function testFeeCalculationThreeContractsWithOffset() public {
    vm.prank(owner);
    _buy(owner, owner);
    _buy(owner, addr1);
    _buy(owner, addr2);

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
      ) = _createPriceChanges(t0, owner);
      _createPriceChanges(t0, addr1);

      uint256 expectedSingle = ComputeUtils._calculateFeeBetweenTimes(
        0,
        t0,
        t1,
        tenPercent
      ) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t1, t2, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t2, t3, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(
          0.5 ether,
          t3,
          endTime,
          tenPercent
        );

      expected += expectedSingle * 2;
      endTimeFinal = endTime;
    }

    {
      // Create a third set of price changes that start at t0 + 1 day
      (, uint256 t11, uint256 t22, uint256 t33, ) = _createPriceChanges(
        t0 + 1 days,
        addr2
      );

      uint256 expectedSecond = ComputeUtils._calculateFeeBetweenTimes(
        0,
        t0 + 1 days,
        t11,
        tenPercent
      ) +
        ComputeUtils._calculateFeeBetweenTimes(1 ether, t11, t22, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(2 ether, t22, t33, tenPercent) +
        ComputeUtils._calculateFeeBetweenTimes(
          0.5 ether,
          t33,
          endTimeFinal,
          tenPercent
        );

      expected += expectedSecond;
    }

    vm.warp(endTimeFinal);
    Proof[] memory proof = harness.getPriceProof(owner);
    assertEqUint(proof.length, 3);
    (, uint256 fee) = harness.exposedGetFeeBreakdown(
      harness.getTraderSubjectInfo(owner),
      owner,
      proof
    );

    assertEq(fee, expected, "The fee does not match the expected value");
  }

  function testMissingProofs() public {
    vm.prank(owner);
    _buy(owner, owner);
    _buy(owner, addr1);
    _buy(owner, addr2);

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    _createPriceChanges(t0, owner);
    _createPriceChanges(t0, addr1);
    // Create a third set of price changes that start at t0 + 1 day
    (, , , , uint256 endTime) = _createPriceChanges(t0 + 1 days, addr2);

    vm.warp(endTime);
    Proof[] memory proof = harness.getPriceProof(owner);
    assertEqUint(proof.length, 3);

    Proof[] memory invalidProof = removeProof(proof, owner);
    assertEqUint(invalidProof.length, 2);

    vm.expectRevert(abi.encodeWithSelector(InvalidProofsLength.selector));
    harness.exposedCollectFees(owner, invalidProof);

    invalidProof = removeProof(proof, addr1);
    vm.expectRevert(abi.encodeWithSelector(InvalidProofsLength.selector));
    harness.exposedCollectFees(owner, invalidProof);
  }

  function removeProof(
    Proof[] memory proof,
    address keySubject
  ) internal pure returns (Proof[] memory) {
    Proof[] memory newProof = new Proof[](proof.length - 1);
    uint256 j = 0;
    for (uint256 i = 0; i < proof.length; i++) {
      if (proof[i].keySubject != keySubject) {
        newProof[j] = proof[i];
        j++;
      }
    }
    return newProof;
  }
}
