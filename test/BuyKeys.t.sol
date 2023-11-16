// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "./utils/IntegratedSetup.t.sol";
import "forge-std/console.sol";
import {ISubscriptionPoolErrors} from "../src/errors/ISubscriptionPoolErrors.sol";

contract BuyKeysTest is IntegratedSetup, ISubscriptionPoolErrors {
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

  function testBuyFiveKeysWithInsufficientBond() public {
    vm.deal(owner, 100 ether);

    uint256 keysToBuy = 5;
    Proof[] memory proof;

    // Calculate the price for 5 keys
    uint256 priceForKeys = subKey.getPrice(0, keysToBuy);
    uint256 protocolFee = subKey.getProtocalFee(priceForKeys);

    // Calculate bond requirement
    uint256 bondRequirement = subKey.getPoolRequirementForBuy(
      owner,
      owner,
      keysToBuy
    );
    // Total payment (1 wei less than required)
    uint256 insufficientPayment = priceForKeys +
      protocolFee +
      bondRequirement -
      1 wei;

    // Expect the transaction to revert due to insufficient bond
    vm.startPrank(owner);
    vm.expectRevert(
      abi.encodeWithSelector(InsufficientSubscriptionPool.selector)
    );
    subKey.buyKeys{value: insufficientPayment}(owner, keysToBuy, proof);
    vm.stopPrank();

    // Now send the correct amount to confirm it doesn't revert
    uint256 sufficientPayment = priceForKeys + protocolFee + bondRequirement;
    vm.startPrank(owner);
    subKey.buyKeys{value: sufficientPayment}(owner, keysToBuy, proof);
    assertEq(subKey.balanceOf(owner, owner), keysToBuy);

    vm.stopPrank();
  }

  function testBondRequirementWithTwoSubjects() public {
    vm.deal(owner, 100 ether);

    uint256 keysToBuy = 5;
    Proof[] memory proof;

    uint256 priceForKeys = subKey.getPrice(0, keysToBuy);
    uint256 protocolFee = subKey.getProtocalFee(priceForKeys);
    uint256 bondRequirement = subKey.getPoolRequirementForBuy(
      owner,
      owner,
      keysToBuy
    );
    uint256 payment = priceForKeys + protocolFee + bondRequirement;
    vm.startPrank(owner);
    subKey.buyKeys{value: payment}(owner, keysToBuy, proof);

    // now buy from second key subject
    proof = subKey.getPriceProof(owner);

    uint256 additionalReq = subKey.getPoolRequirementForBuy(
      owner,
      addr1,
      keysToBuy
    ) - subKey.getSubscriptionPool(owner);
    payment = priceForKeys + protocolFee + additionalReq - 1;
    vm.expectRevert(
      abi.encodeWithSelector(InsufficientSubscriptionPool.selector)
    );
    subKey.buyKeys{value: payment}(addr1, keysToBuy, proof);

    payment = priceForKeys + protocolFee + additionalReq;
    subKey.buyKeys{value: payment}(addr1, keysToBuy, proof);

    vm.stopPrank();
  }
}
