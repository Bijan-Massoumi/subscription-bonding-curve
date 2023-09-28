// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "../SubscriptionKeys.sol";

library CircularSetDequeue {
  using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

  struct Bytes32Dequeue {
    DoubleEndedQueue.Bytes32Deque queue;
    mapping(address => bool) exists;
  }

  function push(Bytes32Dequeue storage carousel, address _address) internal {
    if (!carousel.exists[_address]) {
      carousel.queue.pushBack(bytes32(uint256(uint160(_address))));
      carousel.exists[_address] = true;
    }
  }

function pop(
  Bytes32Dequeue storage carousel,
  address keyContract
) internal returns (address) {
  if (carousel.queue.length() == 0) {
    return address(0); // Return zero address if the carousel is empty
  }

  address poppedAddress;
  uint256 balance;
  
  do {
    poppedAddress = address(uint160(uint256(carousel.queue.popFront())));
    balance = SubscriptionKeys(keyContract).balanceOf(poppedAddress);
    
    if (balance == 0) {
      carousel.exists[poppedAddress] = false;
      
      if (carousel.queue.length() == 0) {
        return address(0); // Return zero address if the carousel becomes empty
      }
    }
  } while (balance == 0);

  carousel.queue.pushBack(bytes32(uint256(uint160(poppedAddress))));
  return poppedAddress;
}
