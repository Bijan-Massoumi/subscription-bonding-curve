// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/KeyFactory.sol";
import "../../src/SubscriptionPool.sol";
import "forge-std/console.sol";

contract KeyHarness is SubscriptionKeys {
  constructor() SubscriptionKeys(1, address(1), address(1), address(1), 1) {}

  // get historicalPriceChanges
  function exposedGetHistoricalPriceChanges()
    external
    view
    returns (Common.PriceChange[] memory)
  {
    return historicalPriceChanges;
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
}

abstract contract HarnessSetup is Test {
  address withdrawAddr = address(1137);
  SubscriptionPool subPool;
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);
  KeyHarness harnass;

  SubscriptionKeys key1;
  SubscriptionKeys key2;

  function setUp() public {
    subPool = new SubscriptionPool();

    vm.startPrank(owner);
    harnass = new KeyHarness();
  }
}
