// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionKeys.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

uint256 constant perc = 1500;

contract SubKeys is SubscriptionKeys {
  constructor(
    uint256 _subscriptionRate,
    address _subject,
    address _subPoolContract,
    address _factoryContract
  )
    SubscriptionKeys(
      _subscriptionRate,
      _subject,
      _subPoolContract,
      _factoryContract
    )
  {}
}

contract KeyFactory is Ownable {
  address subPoolContract;
  // TODO why is this here?
  address public newSubKeys;
  uint256 groupId;
  mapping(address => address) public subjectToContract;

  address[] public deployedSubjects;
  mapping(address => bool) public validDeployments;

  event ShareSampleCreated(
    address indexed shareSampleAddress,
    uint indexed subRate,
    address indexed sharesSubject
  );

  constructor(address _subPoolContract) {
    subPoolContract = _subPoolContract;
    groupId = SubscriptionPool(subPoolContract).addPermissionGroup(
      "KeyFactory"
    );
  }

  function getGroupId() external view returns (uint256) {
    return groupId;
  }

  function createSubKeyContract(
    address _sharesSubject
  ) external onlyOwner returns (address) {
    // Require that a contract hasn’t been deployed for this _sharesSubject before
    require(
      subjectToContract[_sharesSubject] == address(0),
      "Contract already deployed for this sharesSubject"
    );

    newSubKeys = address(
      new SubKeys(perc, _sharesSubject, subPoolContract, address(this))
    );

    _AddNewSubKeyContract(_sharesSubject, newSubKeys);

    return newSubKeys;
  }

  function _AddNewSubKeyContract(
    address _sharesSubject,
    address _newSubKeys
  ) internal {
    SubscriptionPool(subPoolContract).addContractToPermissionGroup(
      groupId,
      _newSubKeys
    );
    // Update the mapping and the array
    subjectToContract[_sharesSubject] = _newSubKeys;
    deployedSubjects.push(_sharesSubject);
    validDeployments[_newSubKeys] = true;

    emit ShareSampleCreated(_newSubKeys, perc, _sharesSubject);
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
