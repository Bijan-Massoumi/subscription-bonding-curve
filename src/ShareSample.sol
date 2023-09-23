// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionKeys.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

uint256 constant tenPercent = 10000;

contract ShareSample is SubscriptionKeys {
  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address owner
  ) SubscriptionKeys(_withdrawAddress, _subscriptionRate, owner) {}
}

contract ShareSampleFactory is Ownable {
  address public newShareSample;
  mapping(address => address) public sharesSubjectToContract;
  address[] public deployedSubjects;
  
  event ShareSampleCreated(
    address indexed shareSampleAddress,
    uint indexed subRate,
    address indexed sharesSubject
  );

  function createShareSample(address _sharesSubject) external onlyOwner {
    // Require that a contract hasn’t been deployed for this _sharesSubject before
    require(sharesSubjectToContract[_sharesSubject] == address(0), "Contract already deployed for this sharesSubject");
    
    newShareSample = address(new ShareSample(
      _sharesSubject,
      tenPercent,
      _sharesSubject
    ));
    
    // Update the mapping and the array
    sharesSubjectToContract[_sharesSubject] = newShareSample;
    deployedSubjects.push(_sharesSubject);
    
    emit ShareSampleCreated(
      newShareSample,
      tenPercent,
      _sharesSubject
    );
  }
  
  function getDeployedContracts() external view returns (address[] memory) {
    return deployedSubjects;
  }
  
  function getContractForSharesSubject(address _sharesSubject) external view returns (address) {
    return sharesSubjectToContract[_sharesSubject];
  }
}