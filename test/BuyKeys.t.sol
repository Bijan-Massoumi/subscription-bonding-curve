// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./utils/IntegratedSetup.t.sol";
import "forge-std/console.sol";

contract BuyKeysTest is IntegratedSetup {
  function testBalanceChangeAfterBuySale() public {
    vm.deal(owner, 100 ether);

    Proof[] memory proof;
    proof = subKey.getPriceProof(owner);
    assertEqUint(proof.length, 0);

    // Buy 1 key
    vm.startPrank(owner);
    subKey.buyKeys{value: 1 ether}(owner, 1, proof);

    assertEqUint(subKey.balanceOf(owner, owner), 1);
    assertEqUint(subKey.balanceOf(owner, addr1), 0);

    uint256 p = subKey.getBuyPriceAfterFee(owner, 1);
    proof = subKey.getPriceProof(owner);
    assertEqUint(proof.length, 1);
    subKey.buyKeys{value: p}(owner, 1, proof);
    assertEqUint(subKey.balanceOf(owner, owner), 2);

    // sell
    proof = subKey.getPriceProof(owner);
    assertEqUint(proof.length, 1);

    subKey.sellKeys(owner, 1, proof);
    assertEqUint(subKey.balanceOf(owner, owner), 1);
    vm.stopPrank();
  }
}
