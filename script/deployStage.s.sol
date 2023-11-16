// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/SubscriptionKeys.sol";
import "forge-std/Script.sol";

contract DeployUpdated is Script {
  SubscriptionKeys keyContract;

  // Helper function for calculating total payment
  function calculateTotalPayment(
    address trader,
    address keySubject,
    uint256 keysToBuy
  ) internal view returns (uint256) {
    uint256 priceForKeys = keyContract.getPrice(
      keyContract.keySupply(keySubject),
      keysToBuy
    );
    uint256 protocolFee = keyContract.getProtocalFee(priceForKeys);
    uint256 poolRequirement = keyContract.getPoolRequirementForBuy(
      trader,
      keySubject,
      keysToBuy
    );
    uint256 existingPool = keyContract.getSubscriptionPool(trader);

    return priceForKeys + protocolFee + (poolRequirement - existingPool);
  }

  function run() public {
    // Start broadcast (assuming you still want to keep this logic)
    uint256 feeRate = 100000000000000000; // ten percent
    uint256 liquidationPenalty = 150000000000000000; // fifteen percent
    uint256 protocolFeePercent = 50000000000000000; // five percent
    address destination = vm.envAddress("OWNER_PUBLIC_KEY");

    uint256 ownerpk = vm.envUint("GOERLI_PRIVATE_KEY");
    address ownerAddr = vm.addr(ownerpk);

    uint256 subcaster1 = vm.envUint("TEST_ACCOUNT_1_PRIVATE_KEY");
    address s1Addr = vm.addr(subcaster1);

    uint256 subcaster2 = vm.envUint("TEST_ACCOUNT_2_PRIVATE_KEY");
    address s2Addr = vm.addr(subcaster2);

    vm.startBroadcast(ownerpk);
    keyContract = new SubscriptionKeys();
    keyContract.setProtocolFeePercent(protocolFeePercent);
    keyContract.setSubscriptionRate(feeRate);
    keyContract.setProtocolFeeDestination(destination);
    keyContract.setLiquidationPenalty(liquidationPenalty);
    keyContract.initializeKeySubject();
    vm.stopBroadcast();

    // Initialize keySubjects and buy keys with the correct payment
    uint256 payment;

    vm.startBroadcast(subcaster1);
    keyContract.initializeKeySubject();
    payment = calculateTotalPayment(s1Addr, s1Addr, 3);
    keyContract.buyKeys{value: payment}(
      s1Addr,
      3,
      SubscriptionKeys(address(keyContract)).getPriceProof(s1Addr)
    );
    vm.stopBroadcast();

    vm.startBroadcast(subcaster2);
    keyContract.initializeKeySubject();
    payment = calculateTotalPayment(s2Addr, s2Addr, 3);
    keyContract.buyKeys{value: payment}(
      s2Addr,
      3,
      SubscriptionKeys(address(keyContract)).getPriceProof(s2Addr)
    );
    vm.stopBroadcast();
  }
}
