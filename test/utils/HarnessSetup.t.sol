// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/KeyFactory.sol";
import "../../src/SubscriptionPool.sol";
import "forge-std/console.sol";

contract KeyHarness is SubscriptionKeys {
  constructor(
    address factory,
    address keyOwner,
    address subPoolContract
  ) SubscriptionKeys(1000, keyOwner, subPoolContract, factory) {}

  // get historicalPriceChanges
  function exposedGetHistoricalPriceChanges()
    external
    view
    returns (Common.PriceChange[] memory)
  {
    return historicalPriceChanges;
  }

  // set periodLastOccuredAt
  function exposedSetPeriodLastOccuredAt(uint256 timestamp) external {
    periodLastOccuredAt = timestamp;
  }

  function exposedAddHistoricalPriceChange(
    uint256 averagePrice,
    uint256 currentTime
  ) external {
    _addHistoricalPriceChange(averagePrice, currentTime);
  }

  // set _lastHistoricalPriceByTrader
  function exposedSetTraderPriceIndex(
    uint256 newIndex,
    address trader
  ) external {
    _lastHistoricalPriceByTrader[trader] = newIndex;
  }

  // get recentPriceChanges
  function exposedGetRecentPriceChanges()
    external
    view
    returns (Common.PriceChange[] memory)
  {
    return recentPriceChanges;
  }

  // get period
  function exposedGetPeriod() external view returns (uint256) {
    return period;
  }

  // Deploy this contract then call this method to test `myInternalMethod`.
  function exposedUpdatePriceOracle(uint256 newPrice) external {
    return _updatePriceOracle(newPrice);
  }

  // First, we will expose the internal methods we want to test using the Harness.
  function exposedVerifyAndCollectFees(
    Common.ContractInfo[] memory traderContracts,
    address trader,
    uint256 lastDepositTime,
    Proof[] calldata proofs
  ) public returns (uint256) {
    return
      _verifyAndCollectFees(traderContracts, trader, lastDepositTime, proofs);
  }
}

// KEYFACTORY HARNESS
contract KeyFactoryHarness is KeyFactory {
  constructor(address pool) KeyFactory(pool) {}

  function exposedAddNewSubKeyContract(
    address subject,
    address subPool
  ) external {
    _AddNewSubKeyContract(subject, subPool);
  }
}

abstract contract HarnessSetup is Test {
  address withdrawAddr = address(1137);
  SubscriptionPool subPool;
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);

  uint256 groupId;
  KeyHarness harness;
  KeyFactoryHarness keyFactory;

  KeyHarness harness2;
  KeyHarness harness3;

  function _buy(KeyHarness h, address trader) internal {
    Proof[] memory proof = _getProofForContracts(trader, h);
    vm.prank(owner);
    h.buyKeys{value: 2 ether}(1, proof);
  }

  function _getProofForContracts(
    address trader,
    KeyHarness h
  ) internal view returns (Proof[] memory) {
    Common.ContractInfo[] memory ci = subPool.getTraderContracts(
      trader,
      keyFactory.getGroupId()
    );

    // 1. Check if h address is in ci
    bool isHInCi = false;
    for (uint256 j = 0; j < ci.length; j++) {
      if (address(ci[j].keyContract) == address(h)) {
        isHInCi = true;
        break;
      }
    }

    // 2. Adjust the size of proof array based on the presence of h in ci
    uint256 proofLength = isHInCi ? ci.length : ci.length + 1;
    Proof[] memory proof = new Proof[](proofLength);

    // 3. Populate the proof array
    for (uint256 i = 0; i < ci.length; i++) {
      proof[i] = KeyHarness(ci[i].keyContract).getPriceProof(trader);
    }

    // If h was not in ci, get its getPriceProof and assign it to the last position in proof
    if (!isHInCi) {
      proof[ci.length] = h.getPriceProof(trader);
    }

    return proof;
  }

  function setUp() public {
    subPool = new SubscriptionPool();

    vm.deal(owner, 100 ether);
    vm.deal(addr1, 100 ether);
    vm.deal(addr2, 100 ether);

    vm.startPrank(owner);
    keyFactory = new KeyFactoryHarness(address(subPool));
    harness = new KeyHarness(address(keyFactory), owner, address(subPool));
    keyFactory.exposedAddNewSubKeyContract(owner, address(harness));

    harness2 = new KeyHarness(address(keyFactory), owner, address(subPool));
    keyFactory.exposedAddNewSubKeyContract(owner, address(harness2));

    harness3 = new KeyHarness(address(keyFactory), owner, address(subPool));
    keyFactory.exposedAddNewSubKeyContract(owner, address(harness3));

    vm.stopPrank();
  }
}
