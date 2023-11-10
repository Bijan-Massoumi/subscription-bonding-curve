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
  address destination = address(4);

  uint256 tenPercent = 100000000000000000;

  SubscriptionKeys subKey;

  function setUp() public {
    vm.startPrank(owner);
    subKey = new SubscriptionKeys();

    subKey.setProtocolFeePercent(50000000000000000);
    subKey.setProtocolFeeDestination(destination);

    subKey.initializeKeySubject(tenPercent);
    vm.stopPrank();

    vm.prank(addr1);
    subKey.initializeKeySubject(tenPercent);

    vm.prank(addr2);
    subKey.initializeKeySubject(tenPercent);
  }
}
