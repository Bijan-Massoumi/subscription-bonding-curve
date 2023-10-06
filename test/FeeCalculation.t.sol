// SPDX-License-Identifier: MITs
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";
import "../src/ComputeUtils.sol";

uint256 constant ONE_MONTH = 30 days;

contract FeeCalculationTest is HarnessSetup {
  function testFeeCalculationOneContract() public {
    // Mock some PriceChange values for the proofs

    vm.startPrank(owner);
    uint256 t0 = block.timestamp;
    // buy 1 key
    Proof[] memory proof = new Proof[](1);
    proof[0] = harness.getPriceProof(owner);
    harness.buyKeys{value: 2 ether}(1, proof);
    subPool.increaseSubscriptionPoolForGroupId{value: 10 ether}(
      keyFactory.getGroupId()
    );

    uint256 t1 = t0 + 2 * ONE_MONTH;
    uint256 t2 = t0 + 4 * ONE_MONTH;
    uint256 t3 = t0 + 6 * ONE_MONTH;

    harness.exposedAddHistoricalPriceChange(1 ether, t1);
    harness.exposedAddHistoricalPriceChange(2 ether, t2);
    harness.exposedAddHistoricalPriceChange(1 ether / 2, t3);
    Common.PriceChange[] memory pcs = new Common.PriceChange[](3);
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
    proof = new Proof[](1);
    proof[0] = harness.getPriceProof(owner);
    // confirm that proof[0] == pcs
    assertEqUint(proof[0].pcs[0].price, 0);
    assertEqUint(proof[0].pcs[1].price, pcs[0].price);
    assertEqUint(proof[0].pcs[2].price, pcs[1].price);
    assertEqUint(proof[0].pcs[3].price, pcs[2].price);

    uint256 endTime = block.timestamp + 12 * ONE_MONTH;
    harness.exposedSetTraderPriceIndex(0, owner);
    harness.setHistoricalPriceChanges(pcs);
    harness.exposedSetPeriodLastOccuredAt(endTime);
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
}
