// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/SubscriptionKeys.sol";
import "forge-std/Script.sol";

contract DeployUpdated is Script {
  // Helper function for calculating total payment
  function calculateTotalPayment(
    address contractAddr,
    address trader,
    address keySubject,
    uint256 keysToBuy
  ) internal view returns (uint256) {
    uint256 priceForKeys = SubscriptionKeys(contractAddr).getPrice(
      SubscriptionKeys(contractAddr).keySupply(keySubject),
      keysToBuy
    );
    uint256 protocolFee = SubscriptionKeys(contractAddr).getProtocalFee(
      priceForKeys
    );
    uint256 poolRequirement = SubscriptionKeys(contractAddr)
      .getPoolRequirementForBuy(trader, keySubject, keysToBuy);
    uint256 existingPool = SubscriptionKeys(contractAddr).getSubscriptionPool(
      trader
    );

    return priceForKeys + protocolFee + (poolRequirement - existingPool);
  }

  function run() public {
    address contractAddr = 0x85F27145b4bb11DD843fb4ede1b90F3786aCfB9A;

    uint256 ownerpk = vm.envUint("GOERLI_PRIVATE_KEY");
    address ownerAddr = vm.addr(ownerpk);

    uint256 subcaster1 = vm.envUint("TEST_ACCOUNT_1_PRIVATE_KEY");
    address s1Addr = vm.addr(subcaster1);

    uint256 subcaster2 = vm.envUint("TEST_ACCOUNT_2_PRIVATE_KEY");
    address s2Addr = vm.addr(subcaster2);

    // Initialize keySubjects and buy keys with the correct payment
    uint256 payment;

    vm.startBroadcast(subcaster1);
    payment = calculateTotalPayment(contractAddr, s1Addr, ownerAddr, 3);
    SubscriptionKeys(contractAddr).buyKeys{value: payment}(
      ownerAddr,
      3,
      SubscriptionKeys(contractAddr).getPriceProof(s1Addr)
    );
    vm.stopBroadcast();

    vm.startBroadcast(subcaster2);
    payment = calculateTotalPayment(contractAddr, s2Addr, ownerAddr, 3);
    SubscriptionKeys(contractAddr).buyKeys{value: payment}(
      ownerAddr,
      3,
      SubscriptionKeys(contractAddr).getPriceProof(s2Addr)
    );
    vm.stopBroadcast();
  }
}
