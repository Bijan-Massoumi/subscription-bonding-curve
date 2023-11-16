// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/SubscriptionKeys.sol";
import "forge-std/console.sol";

contract KeyHarness is SubscriptionKeys {
  constructor() SubscriptionKeys() {}

  // get historicalPriceChanges
  function exposedGetHistoricalPriceChanges(
    address subject
  ) external view returns (Common.PriceChange[] memory) {
    return historicalPriceChanges[subject];
  }

  // set periodLastOccuredAt
  function exposedSetPeriodLastOccuredAt(
    address keySubject,
    uint256 timestamp
  ) external {
    periodLastOccuredAt[keySubject] = timestamp;
  }

  function exposedAddHistoricalPriceChange(
    address keySubject,
    uint256 averagePrice,
    uint256 currentTime
  ) external {
    _addHistoricalPriceChange(keySubject, averagePrice, currentTime);
  }

  function exposedGetRunningTotal(
    address keySubject
  ) external view returns (RunningTotal memory) {
    return runningTotals[keySubject];
  }

  // get period
  function exposedGetPeriod() external view returns (uint256) {
    return period;
  }

  // Deploy this contract then call this method to test `myInternalMethod`.
  function exposedUpdatePriceOracle(
    address keySubject,
    uint256 price
  ) external {
    return _updatePriceOracle(keySubject, price);
  }

  // First, we will expose the internal methods we want to test using the Harness.
  function exposedCollectFees(
    address trader,
    Proof[] calldata proofs
  ) public returns (uint256) {
    return collectFees(trader, proofs);
  }

  function exposedGetFeeBreakdown(
    Common.SubjectTraderInfo[] memory subInfos,
    address trader,
    Proof[] calldata proofs
  ) public view returns (FeeBreakdown[] memory _breakdown, uint256 _totalFees) {
    return _getFeeBreakdown(subInfos, trader, proofs);
  }
}

abstract contract HarnessSetup is Test {
  address withdrawAddr = address(1137);
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);
  address destination = address(4);
  KeyHarness harness;
  uint256 feeRate = 100000000000000000;

  function _buy(address trader, address subject) internal {
    Proof[] memory proof = harness.getPriceProof(trader);
    vm.prank(trader);
    harness.buyKeys{value: 5 ether}(subject, 1, proof);
  }

  function setUp() public {
    vm.deal(owner, 100 ether);
    vm.deal(addr1, 100 ether);
    vm.deal(addr2, 100 ether);

    vm.startPrank(owner);
    harness = new KeyHarness();
    harness.setProtocolFeePercent(50000000000000000);
    harness.setSubscriptionRate(feeRate);
    harness.setProtocolFeeDestination(destination);
    harness.setLiquidationPenalty(150000000000000000);

    harness.initializeKeySubject();
    vm.stopPrank();

    vm.prank(addr1);
    harness.initializeKeySubject();

    vm.prank(addr2);
    harness.initializeKeySubject();
  }
}
