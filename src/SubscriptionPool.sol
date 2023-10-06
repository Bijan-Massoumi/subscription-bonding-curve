// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ISubscriptionPoolErrors.sol";
import "./KeyFactory.sol";
import "./Common.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./SubscriptionKeys.sol";

// TODO can a contract be a part of two different groups?

contract SubscriptionPool is ISubscriptionPoolErrors {
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  // event FeeCollected(
  //   uint256 feeCollected,
  //   uint256 deposit,
  //   uint256 liquidationStartedAt
  // );

  // Permission group storage
  struct PermissionGroup {
    string name; // Name of the permission group for easy identification
    address owner; // Owner of the permission group
    mapping(address => bool) members; // List of contracts authorized within this group
  }
  mapping(uint256 => PermissionGroup) public permissionGroups;
  uint256 public permissionGroupCount = 0;

  mapping(address trader => mapping(uint256 groupId => Common.SubscriptionPoolCheckpoint checkpoint))
    internal _groupedSubscriptionCheckpoints;
  mapping(address => mapping(uint256 => EnumerableMap.AddressToUintMap))
    internal _groupedTraderKeyContractBalances;

  function addPermissionGroup(
    string memory name
  ) external returns (uint256 groupId) {
    permissionGroupCount++;
    permissionGroups[permissionGroupCount].name = name;
    permissionGroups[permissionGroupCount].owner = msg.sender; // Set the owner to the caller
    return permissionGroupCount;
  }

  function addContractToPermissionGroup(
    uint256 groupId,
    address contractAddr
  ) external {
    require(groupId <= permissionGroupCount, "Invalid group ID");
    require(permissionGroups[groupId].owner == msg.sender, "Not the owner");
    permissionGroups[groupId].members[contractAddr] = true;
  }

  function removeContractFromPermissionGroup(
    uint256 groupId,
    address contractAddr
  ) external {
    require(groupId <= permissionGroupCount, "Invalid group ID");
    require(permissionGroups[groupId].owner == msg.sender, "Not the owner");
    permissionGroups[groupId].members[contractAddr] = false;
  }

  function isContractValidInGroup(
    uint256 groupId,
    address contractAddr
  ) public view returns (bool) {
    require(groupId <= permissionGroupCount, "Invalid group ID");
    return permissionGroups[groupId].members[contractAddr];
  }

  // min percentage (10%) of total stated price that
  // move to groupInfo
  uint256 internal minimumPoolRatio = 1000;
  // 100% pool percent
  uint256 internal maxMinimumPoolRatio = 10000;

  function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
    minimumPoolRatio = newMinimumPoolRatio;
  }

  function getTraderContracts(
    address trader,
    uint256 groupId
  ) external view returns (Common.ContractInfo[] memory) {
    uint256 length = _groupedTraderKeyContractBalances[trader][groupId]
      .length();
    Common.ContractInfo[] memory contractInfos = new Common.ContractInfo[](
      length
    );

    for (uint256 i = 0; i < length; i++) {
      (
        address keyContract,
        uint256 balance
      ) = _groupedTraderKeyContractBalances[trader][groupId].at(i);
      contractInfos[i] = Common.ContractInfo({
        keyContract: keyContract,
        balance: balance
      });
    }

    return contractInfos;
  }

  function updateTraderInfo(
    address trader,
    uint256 groupId,
    uint256 newDeposit,
    uint256 newBal
  ) external {
    require(
      isContractValidInGroup(groupId, msg.sender),
      "Contract not valid in this group"
    );

    // update pool checkpoint
    _updateTraderPool(trader, groupId, newDeposit);

    if (newBal == 0) {
      _groupedTraderKeyContractBalances[trader][groupId].remove(msg.sender);
    } else {
      _groupedTraderKeyContractBalances[trader][groupId].set(
        msg.sender,
        newBal
      );
    }
  }

  function getCurrentPoolRequirement(
    address trader,
    uint256 groupId
  ) public view returns (uint256) {
    // Initialize the total pool requirement to 0
    uint256 totalPoolRequirement = _getUnchangingPoolRequirement(
      trader,
      groupId,
      address(0)
    );

    return totalPoolRequirement;
  }

  function getPoolRequirementForBuy(
    address trader,
    uint256 groupId,
    address buyContract,
    uint256 amount
  ) external view returns (uint256) {
    require(
      isContractValidInGroup(groupId, buyContract),
      "Invalid contract for group"
    );

    uint256 totalRequirement = _getUnchangingPoolRequirement(
      trader,
      groupId,
      buyContract
    );

    // For the calling contract, calculate the requirement after the buy
    uint256 newPrice = SubscriptionKeys(buyContract).getBuyPrice(amount);
    uint256 newBalance = SubscriptionKeys(buyContract).balanceOf(trader) +
      amount;
    uint256 additionalRequirement = (newPrice * newBalance * minimumPoolRatio) /
      10000;

    // Add the additional requirement to the total requirement
    totalRequirement += additionalRequirement;

    return totalRequirement;
  }

  function _getUnchangingPoolRequirement(
    address trader,
    uint256 groupId,
    address changingContract
  ) internal view returns (uint256) {
    uint256 totalRequirement = 0;
    uint256 length = _groupedTraderKeyContractBalances[trader][groupId]
      .length();

    for (uint256 i = 0; i < length; i++) {
      (
        address keyContract,
        uint256 balance
      ) = _groupedTraderKeyContractBalances[trader][groupId].at(i);

      if (keyContract == changingContract) {
        continue;
      }

      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      totalRequirement += requirement;
    }

    return totalRequirement;
  }

  function getSubscriptionPoolCheckpoint(
    address trader,
    uint256 groupId
  ) public view returns (Common.SubscriptionPoolCheckpoint memory) {
    return _groupedSubscriptionCheckpoints[trader][groupId];
  }

  function _updateTraderPool(
    address trader,
    uint256 groupId,
    uint256 newSubPool
  ) internal {
    Common.SubscriptionPoolCheckpoint
      storage cp = _groupedSubscriptionCheckpoints[trader][groupId];
    cp.deposit = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }

  // -------------- subscription pool methods ----------------

  function increaseSubscriptionPoolForGroupId(
    uint256 groupId
  ) external payable {
    Common.SubscriptionPoolCheckpoint memory cp = getSubscriptionPoolCheckpoint(
      msg.sender,
      groupId
    );

    uint256 newDeposit = cp.deposit + msg.value;
    _updateTraderPool(msg.sender, groupId, newDeposit);
  }

  function decreaseSubscriptionPool(uint256 groupId, uint256 amount) external {
    Common.SubscriptionPoolCheckpoint memory cp = getSubscriptionPoolCheckpoint(
      msg.sender,
      groupId
    );
    uint256 req = getCurrentPoolRequirement(msg.sender, groupId);

    require(cp.deposit >= amount, "Insufficient deposit");
    require(
      cp.deposit - amount >= req,
      "Deposit cannot be less than current requirement"
    );
    uint256 newDeposit = cp.deposit - amount;
    _updateTraderPool(msg.sender, 0, newDeposit);

    // Transfer the amount to the trader
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
  }
}
