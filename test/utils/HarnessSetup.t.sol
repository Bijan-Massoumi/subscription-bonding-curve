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

  function setHistoricalPriceChanges(
    Common.PriceChange[] memory changes
  ) external {
    for (uint256 i = 0; i < changes.length; i++) {
      historicalPriceChanges.push(changes[i]);
    }
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

  SubscriptionKeys key1;
  SubscriptionKeys key2;

  function setUp() public {
    subPool = new SubscriptionPool();

    vm.deal(owner, 100 ether);
    vm.deal(addr1, 100 ether);
    vm.deal(addr2, 100 ether);

    vm.startPrank(owner);
    keyFactory = new KeyFactoryHarness(address(subPool));
    harness = new KeyHarness(address(keyFactory), owner, address(subPool));
    keyFactory.exposedAddNewSubKeyContract(owner, address(harness));

    key1 = SubscriptionKeys(keyFactory.createSubKeyContract(addr1));
    key2 = SubscriptionKeys(keyFactory.createSubKeyContract(addr2));
    vm.stopPrank();
  }
}
