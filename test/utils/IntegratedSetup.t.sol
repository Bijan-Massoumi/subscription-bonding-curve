// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../src/KeyFactory.sol";
import "../../src/SubscriptionPool.sol";
import "forge-std/console.sol";

abstract contract IntegratedSetup is Test {
  address withdrawAddr = address(1137);
  SubscriptionPool subPool;
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);
  KeyFactory keyFactory;

  SubscriptionKeys key1;
  SubscriptionKeys key2;

  function setUp() public {
    subPool = new SubscriptionPool();

    vm.startPrank(owner);
    keyFactory = new KeyFactory(address(subPool));
    address key1Addr = keyFactory.createSubKeyContract(addr1);
    key1 = SubscriptionKeys(key1Addr);

    address key2Addr = keyFactory.createSubKeyContract(addr2);
    key2 = SubscriptionKeys(key2Addr);
    vm.stopPrank();
  }
}
