// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/SubscriptionKeys.sol";
import "forge-std/console.sol";

abstract contract IntegratedSetup is Test {
  address withdrawAddr = address(1137);
  address owner = address(1);
  address addr1 = address(2);
  address addr2 = address(3);

  SubscriptionKeys subKey;

  function setUp() public {
    vm.prank(owner);
    subKey = new SubscriptionKeys();
    vm.prank(owner);
    subKey.initializeKeySubject(1000);

    vm.prank(addr1);
    subKey.initializeKeySubject(1000);

    vm.prank(addr2);
    subKey.initializeKeySubject(1000);
  }
}
