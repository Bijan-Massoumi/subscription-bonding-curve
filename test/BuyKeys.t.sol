// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/IntegratedSetup.t.sol";
import "forge-std/console.sol";

contract BuyKeysTest is IntegratedSetup {
  function testBalanceChangeAfterBuySale() public {
    vm.deal(owner, 100 ether);

    Proof[] memory proof = new Proof[](1);
    proof[0] = subKey.getPriceProof(owner, owner);
    assertEqUint(proof[0].pcs[0].price, 0);

    // Buy 1 key
    vm.startPrank(owner);
    subKey.buyKeys{value: 1 ether}(owner, 1, proof);

    assertEqUint(subKey.balanceOf(owner, owner), 1);
    assertEqUint(subKey.balanceOf(owner, addr1), 0);

    uint256 p = subKey.getBuyPrice(owner, 1);
    subKey.buyKeys{value: p}(owner, 1, proof);
    assertEqUint(subKey.balanceOf(owner, owner), 2);

    // sell
    proof[0] = subKey.getPriceProof(owner, owner);
    subKey.sellKeys(owner, 1, proof);
    assertEqUint(subKey.balanceOf(owner, owner), 1);
    vm.stopPrank();
  }
}
