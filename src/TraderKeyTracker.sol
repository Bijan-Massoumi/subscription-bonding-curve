// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./Common.sol";

abstract contract TraderKeyTracker {
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  mapping(address trader => EnumerableMap.AddressToUintMap)
    internal _groupedTraderKeyContractBalances;

  function getTraderSubjectInfo(
    address trader
  ) public view returns (Common.SubjectTraderInfo[] memory) {
    uint256 length = _groupedTraderKeyContractBalances[trader].length();
    Common.SubjectTraderInfo[]
      memory contractInfos = new Common.SubjectTraderInfo[](length);

    for (uint256 i = 0; i < length; i++) {
      (address keySubject, uint256 balance) = _groupedTraderKeyContractBalances[
        trader
      ].at(i);
      contractInfos[i] = Common.SubjectTraderInfo({
        keySubject: keySubject,
        balance: balance
      });
    }

    return contractInfos;
  }

  function _updateBalances(
    uint256 newBal,
    address trader,
    address keySubject
  ) internal {
    if (newBal == 0) {
      _groupedTraderKeyContractBalances[trader].remove(keySubject);
    } else {
      _groupedTraderKeyContractBalances[trader].set(keySubject, newBal);
    }
  }

  function getNumUniqueSubjects(address trader) public view returns (uint256) {
    return _groupedTraderKeyContractBalances[trader].length();
  }

  function getUniqueTraderSubjectAtIndex(
    address trader,
    uint256 index
  ) public view returns (address, uint256) {
    return _groupedTraderKeyContractBalances[trader].at(index);
  }
}
