// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Common {
  struct SubjectTraderInfo {
    address keySubject;
    uint256 balance;
  }

  struct PriceChange {
    uint256 price;
    uint128 rate;
    uint112 startTimestamp;
    uint16 index;
  }
}
