// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafUtils.sol";
import "./ISubscriptionPoolErrors.sol";
import "./KeyFactory.sol";
import "./Common.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./SubscriptionKeys.sol";

contract SubscriptionPool is ISubscriptionPoolErrors {
  event FeeCollected(
    uint256 feeCollected,
    uint256 deposit,
    uint256 liquidationStartedAt
  );

  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address trader => Common.SubscriptionPoolCheckpoint checkpoint)
    internal _subscriptionCheckpoints;
  mapping(address trader => EnumerableSet.AddressSet set) internal _hasKeyFor;
  address factoryContract;

  // min percentage (10%) of total stated price that
  // must be convered by subscriptionPool
  uint256 internal minimumPoolRatio = 1000;
  // 100% fee rate
  uint256 internal maxSubscriptionRate = 10000;
  // 100% pool percent
  uint256 internal maxMinimumPoolRatio = 10000;

  constructor(uint256 _subscriptionRate, address _factoryContract) {
    subscriptionRate = _subscriptionRate;
    factoryContract = _factoryContract;
  }

  function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
    minimumPoolRatio = newMinimumPoolRatio;
  }

  function getTraderContracts(
    address trader
  ) external view returns (address[] memory) {
    EnumerableSet.AddressSet memory contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();
    address[] memory contracts = new address[](length);
    for (uint256 i = 0; i < length; i++) {
      contracts[i] = contractSet.at(i);
    }
    return contracts;
  }

  function updateTraderInfo(
    address trader,
    uint256 newDeposit,
    uint256 newBal
  ) external {
    require(
      KeyFactory(factoryAddress).isValidDeployment(msg.sender),
      "Invalid artist contract"
    );

    // update pool checkpoint
    _updateTraderPool(trader, newDeposit);

    if (newBal == 0) {
      hasKeyFor[trader].remove(trader);
    } else {
      hasKeyFor[trader].add(trader);
    }
  }

  function getCurrentPoolRequirement(
    address trader
  ) public view returns (uint256) {
    // Initialize the total pool requirement to 0
    uint256 totalPoolRequirement = 0;

    // Get the set of contracts for which the trader has keys
    EnumerableSet.AddressSet storage contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();

    // Iterate over each contract
    for (uint256 i = 0; i < length; i++) {
      address keyContract = contractSet.at(i);

      // Get the balance of keys the trader holds for this contract
      uint256 balance = SubscriptionKeys(keyContract).balanceOf(trader);

      // Get the current price for each key
      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();

      // Calculate the minimum pool requirement for this contract using the given formula
      // and add it to the total
      totalPoolRequirement += (price * balance * minimumPoolRatio) / 10000;
    }

    return totalPoolRequirement;
  }

  function getPoolRequirementForBuy(
    address trader,
    address buyContract,
    uint256 amount
  ) external view returns (uint256) {
    require(
      KeyFactory(factoryContract).isValidDeployment(buyContract),
      "Invalid artist contract"
    );

    uint256 totalRequirement = _getUnchangingPoolRequirement(
      trader,
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

  function getCurrentPoolRequirementForSell(
    address trader,
    address sellContract,
    uint256 amount
  ) external view returns (uint256) {
    require(
      KeyFactory(factoryContract).isValidDeployment(sellContract),
      "Invalid artist contract"
    );

    uint256 totalRequirement = _getUnchangingPoolRequirement(
      trader,
      sellContract
    );
    // For the calling contract, calculate the requirement after the buy
    uint256 newPrice = SubscriptionKeys(sellContract).getSellPrice(amount);
    uint256 balance = SubscriptionKeys(sellContract).balanceOf(trader);
    require(balance >= amount, "Insufficient balance");

    uint256 additionalRequirement = (newPrice *
      (balance - amount) *
      minimumPoolRatio) / 10000;

    // Add the additional requirement to the total requirement
    totalRequirement += additionalRequirement;

    return totalRequirement;
  }

  function _getUnchangingPoolRequirement(
    address trader,
    address changingContract
  ) internal view returns (uint256) {
    // Initialize the total requirement to 0
    uint256 totalRequirement = 0;
    // Iterate through the set of keyContracts for the trader
    EnumerableSet.AddressSet memory contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();
    for (uint256 i = 0; i < length; i++) {
      address keyContract = contractSet.at(i);
      if (keyContract == changingContract) {
        continue;
      }

      // Calculate the requirement for the current contract
      uint256 balance = SubscriptionKeys(keyContract).balanceOf(trader);
      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      // Add the requirement to the total requirement
      totalRequirement += requirement;
    }

    return totalRequirement;
  }

  function getSubscriptionPoolCheckpoint(
    address trader
  ) public view returns (Common.SubscriptionPoolCheckpoint) {
    return _subscriptionCheckpoints[trader];
  }

  function _updateTraderPool(address trader, uint256 newSubPool) internal {
    SubscriptionPoolCheckpoint storage cp = _subscriptionCheckpoints[trader];
    cp.deposit = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }
}
