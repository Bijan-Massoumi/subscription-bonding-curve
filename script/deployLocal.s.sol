// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/SubscriptionPool.sol";
import "forge-std/Script.sol";

contract DeployUpdated is Script {
  // SubscriptionPool subPool;
  // KeyFactory keyFactory;
  // // Setting these addresses as constants for demonstration purposes.
  // // You might want to fetch or derive them differently in a real deployment.
  // address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
  // address addr1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
  // address addr2 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
  // function run() public {
  //   // Deploy SubscriptionPool
  //   // subPool = new SubscriptionPool();
  //   // Start broadcast (assuming you still want to keep this logic)
  //   // uint256 ownerpk = vm.envUint("PRIVATE_KEY");
  //   // vm.startBroadcast(ownerpk);
  //   // Deploy KeyFactory
  //   // keyFactory = new KeyFactory(address(subPool));
  //   // Create and deploy subscription keys for addr1
  //   // keyFactory.createSubKeyContract(addr1);
  //   // Stop the broadcast (assuming you still want this)
  //   vm.stopBroadcast();
}
