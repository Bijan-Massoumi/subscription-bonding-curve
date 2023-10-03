// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library Common {
  struct SubscriptionPoolCheckpoint {
    uint256 subscriptionPoolRemaining;
    uint256 lastModifiedAt;
  }
}
