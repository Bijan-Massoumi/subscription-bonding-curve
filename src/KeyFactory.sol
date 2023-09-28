// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionKeys.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

uint256 constant perc = 1500;

contract SubKeys is SubscriptionKeys {
  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address owner
  ) SubscriptionKeys(_withdrawAddress, _subscriptionRate, owner) {}
}

contract KeyFactory is Ownable {
  address public newShareSample;
  mapping(address => address) public subjectToContract;

  address[] public deployedSubjects;
  mapping(address => bool) public validDeployments;

  event ShareSampleCreated(
    address indexed shareSampleAddress,
    uint indexed subRate,
    address indexed sharesSubject
  );

  function createShareSample(
    address _sharesSubject
  ) external onlyOwner returns (address) {
    // Require that a contract hasn’t been deployed for this _sharesSubject before
    require(
      subjectToContract[_sharesSubject] == address(0),
      "Contract already deployed for this sharesSubject"
    );

    newShareSample = address(
      new ShareSample(_sharesSubject, perc, _sharesSubject)
    );

    // Update the mapping and the array
    subjectToContract[_sharesSubject] = newShareSample;
    deployedSubjects.push(_sharesSubject);
    validDeployments[newShareSample] = true;

    emit ShareSampleCreated(newShareSample, perc, _sharesSubject);

    return newShareSample;
  }

  function getDeployedContracts()
    external
    view
    returns (address[] memory, address[] memory)
  {
    uint256 length = deployedSubjects.length;
    address[] memory subjects = new address[](length);
    address[] memory contracts = new address[](length);
    for (uint256 i = 0; i < length; i++) {
      address subject = deployedSubjects[i];
      address contractAddress = subjectToContract[subject];
      subjects[i] = subject;
      contracts[i] = contractAddress;
    }
    return (subjects, contracts);
  }

  function getContractForSharesSubject(
    address _sharesSubject
  ) external view returns (address) {
    return subjectToContract[_sharesSubject];
  }

  function isValidDeployment(
    address contractAddress
  ) external view returns (bool) {
    return validDeployments[contractAddress];
  }
}
