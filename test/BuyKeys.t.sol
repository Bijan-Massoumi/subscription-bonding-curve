// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/KeyFactory.sol";
import "./Setup.t.sol";
import "forge-std/console.sol";

contract BuyKeys is Setup {
  function testBalanceChangeAfterBuySale() public {
    vm.deal(owner, 100 ether);

    Proof[] memory proof = new Proof[](1);
    proof[0] = key1.getPriceProof(owner);
    assertEqUint(proof[0].pcs[0].price, 0);

    // Buy 1 key
    vm.startPrank(owner);
    key1.buyKeys{value: 1 ether}(1, proof);
    key1.balanceOf(owner); // 1
    key1.balanceOf(addr1); // 0
    assertEqUint(key1.balanceOf(owner), 1);
    assertEqUint(key1.balanceOf(addr1), 0);

    uint256 p = key1.getBuyPrice(1);
    key1.buyKeys{value: p}(1, proof);
    key1.balanceOf(owner); // 1
    assertEqUint(key1.balanceOf(owner), 2);

    // sell
    proof[0] = key1.getPriceProof(owner);
    key1.sellKeys(1, proof);
    assertEqUint(key1.balanceOf(owner), 1);
    vm.stopPrank();
  }
}
