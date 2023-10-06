// SPDX-License-Identifier: MITs
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./utils/HarnessSetup.t.sol";
import "../src/SubscriptionKeys.sol";

uint256 constant ONE_MONTH = 30 days;

contract FeeCalculationTest is HarnessSetup {
  function testFeeCalculationOneContract() public {
    // Mock some PriceChange values for the proofs
    uint256 rate = 1000;

    vm.prank(owner);
    // buy 1 key
    Proof[] memory proof = new Proof[](1);
    proof[0] = key1.getPriceProof(owner);
    harness.buyKeys(1, proof);

    // TODO subPool harness
    subPool.increaseSubscriptionPoolForGroupId(keyFactory.getGroupId());

    uint256 t1 = block.timestamp + 2 * ONE_MONTH;
    uint256 t2 = block.timestamp + 4 * ONE_MONTH;
    uint256 t3 = block.timestamp + 6 * ONE_MONTH;

    harness.exposedAddHistoricalPriceChange(1 ether, t1);
    harness.exposedAddHistoricalPriceChange(2 ether, t2);
    harness.exposedAddHistoricalPriceChange(1 ether / 2, t3);
    Common.PriceChange[] memory pcs = new Common.PriceChange[](3);
    pcs[0] = Common.PriceChange({
      price: 1 ether,
      rate: uint128(rate),
      startTimestamp: uint112(t1),
      index: 1
    });
    pcs[1] = Common.PriceChange({
      price: 2 ether,
      rate: uint128(rate),
      startTimestamp: uint112(t2),
      index: 2
    });
    pcs[2] = Common.PriceChange({
      price: 1 ether / 2,
      rate: uint128(rate),
      startTimestamp: uint112(t3),
      index: 3
    });
    proof = new Proof[](1);
    proof[0] = key1.getPriceProof(owner);
    // confirm that proof[0] == pcs
    assertEqUint(proof[0].pcs[0].price, pcs[0].price);
    assertEqUint(proof[0].pcs[1].price, pcs[1].price);
    assertEqUint(proof[0].pcs[2].price, pcs[2].price);

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
      endTime,
      proof
    );

    vm.stopPrank();
  }
}
