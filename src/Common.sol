// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library Common {
  struct ContractInfo {
    address keyContract;
    uint256 balance;
  }

  struct PriceChange {
    uint256 price;
    uint128 rate;
    uint112 startTimestamp;
    uint16 index;
  }
}
