// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/SubscriptionKeys.sol";
import "forge-std/Script.sol";

contract DeployUpdated is Script {
  SubscriptionKeys keyContract;

  function run() public {
    // Start broadcast (assuming you still want to keep this logic)
    uint256 feeRate = 100000000000000000; // ten percent
    uint256 liquidationPenalty = 150000000000000000; // fifteen percent
    uint256 protocolFeePercent = 50000000000000000; // five percent
    address destination = vm.envAddress("OWNER_PUBLIC_KEY");

    uint256 ownerpk = vm.envUint("PRIVATE_KEY");
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

    // Initialize keySubjects
    vm.startBroadcast(subcaster1);
    keyContract.initializeKeySubject();
    keyContract.buyKeys(ownerAddr, 3, keyContract.getPriceProof(s1Addr));
    keyContract.buyKeys(s1Addr, 3, keyContract.getPriceProof(s1Addr));
    vm.stopBroadcast();

    vm.startBroadcast(subcaster2);
    keyContract.initializeKeySubject();
    keyContract.buyKeys(s1Addr, 3, keyContract.getPriceProof(s2Addr));
    keyContract.buyKeys(s2Addr, 3, keyContract.getPriceProof(s2Addr));
    vm.stopBroadcast();
  }
}
