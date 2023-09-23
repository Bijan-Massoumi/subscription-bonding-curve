// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionKeys.sol";

contract ShareSample is SubscriptionKeys {
  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address _sharesSubject
  ) SubscriptionKeys(_withdrawAddress, _subscriptionRate, _sharesSubject) {}

  function ping() payable public returns (uint256){
    return 1;
  }
}
