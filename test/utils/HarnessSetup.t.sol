// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

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

  // get recentPriceChanges
  function exposedGetRecentPriceChanges(
    address keySubject
  ) external view returns (Common.PriceChange[] memory) {
    return recentPriceChanges[keySubject];
  }

  // get period
  function exposedGetPeriod() external view returns (uint256) {
    return period;
  }

  // Deploy this contract then call this method to test `myInternalMethod`.
  function exposedUpdatePriceOracle(
    address keySubject,
    uint256 newPrice
  ) external {
    return _updatePriceOracle(keySubject, newPrice);
  }

  // First, we will expose the internal methods we want to test using the Harness.
  function exposedVerifyAndCollectFees(
    Common.SubjectTraderInfo[] memory subInfo,
    address buySubject,
    address trader,
    Proof[] calldata proofs
  ) public returns (uint256) {
    return _verifyAndCollectFees(subInfo, buySubject, trader, proofs);
  }
}

abstract contract HarnessSetup is Test {
  address withdrawAddr = address(1137);
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);
  KeyHarness harness;

  function _buy(address trader, address subject) internal {
    Proof[] memory proof = _getProofForSubjects(trader, subject);
    vm.prank(trader);
    harness.buyKeys{value: 5 ether}(subject, 1, proof);
  }

  function _getProofForSubjects(
    address trader,
    address subject
  ) internal view returns (Proof[] memory) {
    Common.SubjectTraderInfo[] memory ci = harness.getTraderSubjectInfo(trader);

    // 1. Check if h address is in ci
    bool isHInCi = false;
    for (uint256 j = 0; j < ci.length; j++) {
      if (address(ci[j].keySubject) == subject) {
        isHInCi = true;
        break;
      }
    }

    // 2. Adjust the size of proof array based on the presence of h in ci
    uint256 proofLength = isHInCi ? ci.length : ci.length + 1;
    Proof[] memory proof = new Proof[](proofLength);

    // 3. Populate the proof array
    for (uint256 i = 0; i < ci.length; i++) {
      proof[i] = harness.getPriceProof(ci[i].keySubject, trader);
    }

    // If h was not in ci, get its getPriceProof and assign it to the last position in proof
    if (!isHInCi) {
      proof[ci.length] = harness.getPriceProof(subject, trader);
    }

    return proof;
  }

  function setUp() public {
    vm.deal(owner, 100 ether);
    vm.deal(addr1, 100 ether);
    vm.deal(addr2, 100 ether);

    vm.startPrank(owner);
    harness = new KeyHarness();
    harness.initializeKeySubject(1000);
    vm.stopPrank();

    vm.prank(addr1);
    harness.initializeKeySubject(1000);

    vm.prank(addr2);
    harness.initializeKeySubject(1000);
  }
}
