// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafUtils.sol";
import "./ISubscriptionPoolErrors.sol";
import "./KeyFactory.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import "./SubscriptionKeys.sol";

struct SubscriptionPoolCheckpoint {
  uint256 subscriptionPoolRemaining;
  uint256 lastModifiedAt;
}

struct ParamChange {
  uint256 timestamp;
  uint256 priceAtTime;
  uint256 rateAtTime;
}

contract SubscriptionPool is ISubscriptionPoolErrors {
  event FeeCollected(
    uint256 feeCollected,
    uint256 subscriptionPoolRemaining,
    uint256 liquidationStartedAt
  );

  using EnumerableSet for EnumerableSet.AddressSet;

  mapping(address trader => SubscriptionPoolCheckpoint checkpoint)
    internal _subscriptionCheckpoints;
  mapping(address keyContract => ParamChange[] paramChanges)
    internal _paramChangesByContract;
  mapping(address keyContract => mapping(address trader => uint256 index))
    internal _lastTraderIndexByContract;
  mapping(address trader => EnumerableSet.AddressSet set) internal hasKeyFor;
  mapping(address => uint256) internal _subscriptionRateByContract;
  DoubleEndedQueue.Bytes32Deque queue;

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

    // Initialize the total requirement to 0
    uint256 totalRequirement = 0;

    // Iterate through the set of keyContracts for the trader
    EnumerableSet.AddressSet memory contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();
    for (uint256 i = 0; i < length; i++) {
      address keyContract = contractSet.at(i);
      if (keyContract == buyContract) {
        continue;
      }

      // Calculate the requirement for the current contract
      uint256 balance = SubscriptionKeys(keyContract).balanceOf(trader);
      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      // Add the requirement to the total requirement
      totalRequirement += requirement;
    }

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

    // Initialize the total requirement to 0
    uint256 totalRequirement = 0;

    // Iterate through the set of keyContracts for the trader
    EnumerableSet.AddressSet memory contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();
    for (uint256 i = 0; i < length; i++) {
      address keyContract = contractSet.at(i);
      if (keyContract == sellContract) {
        continue;
      }

      // Calculate the requirement for the current contract
      uint256 balance = SubscriptionKeys(keyContract).balanceOf(trader);
      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      // Add the requirement to the total requirement
      totalRequirement += requirement;
    }

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

  function getSubscriptionPoolRemaining(
    address trader
  ) public view returns (uint256 poolRemaining, uint256 fees) {
    SubscriptionPoolCheckpoint memory checkpoint = _subscriptionCheckpoints[
      trader
    ];

    // Iterate through the set of keyContracts for the trader
    uint256 feesToCollect;
    EnumerableSet.AddressSet memory contractSet = hasKeyFor[trader];
    uint256 length = contractSet.length();
    for (uint256 i = 0; i < length; i++) {
      address keyContract = contractSet.at(i);
      uint256 balance = SubscriptionKeys(keyContract).balanceOf(trader);
      uint256 price = SubscriptionKeys(keyContract).getCurrentPrice();
      feesToCollect += _calculateFees(
        owner,
        price,
        checkpoint.lastModifiedAt,
        balance,
        _paramChangesByContract[keyContract]
      );
      if (feesToCollect >= checkpoint.subscriptionPoolRemaining) {
        break;
      }
    }

    if (feesToCollect >= checkpoint.subscriptionPoolRemaining) {
      return (0, feesToCollect);
    }
    return (
      checkpoint.subscriptionPoolRemaining - feesToCollect,
      feesToCollect
    );
  }

  function _calculateFees(
    address trader,
    uint256 currentPrice,
    uint256 memory lastCheckpointAt,
    uint256 balance,
    ParamChange[] memory paramChanges
  ) internal view returns (uint256) {
    uint256 totalFee;
    uint256 prevIntervalFee;
    uint256 startTime = lastCheckpointAt;
    uint256 startIndex = _lastTraderIndexByContract[trader]; // Start from the last index that affected the trader
    for (uint256 i = startIndex; i < paramChanges.length; i++) {
      ParamChange memory pc = paramChanges[i];
      if (pc.timestamp > startTime) {
        uint256 intervalFee = balance *
          SafUtils._calculateFeeBetweenTimes(
            pc.priceAtTime,
            startTime,
            pc.timestamp,
            pc.rateAtTime
          );
        totalFee += intervalFee;
        startTime = pc.timestamp;
        prevIntervalFee += intervalFee;
      }
    }

    totalFee +=
      balance *
      SafUtils._calculateFeeBetweenTimes(
        currentPrice,
        startTime,
        block.timestamp,
        subscriptionRate
      );
    totalFee += intervalFee;

    return totalFee;
  }

  function updatePoolCheckpoints(
    address trader,
    uint256 newSubPool,
    uint256 price,
    uint256 amount
  ) external {
    require(
      KeyFactory(factoryAddress).isValidDeployment(msg.sender),
      "Invalid artist contract"
    );

    // update pool checkpoint
    _updateTraderPool(trader, newSubPool);

    queue.pushBack(bytes32(uint256(trader)));

    // update price checkpoint
    ParamChange[] changes = _paramChangesByContract[msg.sender];
    changes.push(
      ParamChange({
        timestamp: block.timestamp,
        priceAtTime: currPrice,
        rateAtTime: subscriptionRate
      })
    );

    _lastTraderIndexByContract[msg.sender][trader] = paramChanges.length > 0
      ? paramChanges.length - 1
      : 0;
  }

  function _updateTraderPool(address trader, uint256 newSubPool) internal {
    SubscriptionPoolCheckpoint storage cp = _subscriptionCheckpoints[trader];
    cp.subscriptionPoolRemaining = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }

  function _setSubscriptionRate(uint256 newSubscriptionRate) internal {
    uint256 currentPrice = paramChanges.length > 0
      ? paramChanges[paramChanges.length - 1].priceAtTime
      : 0; // Set a default value, for example, 0, if paramChanges is empty

    paramChanges.push(
      ParamChange({
        timestamp: block.timestamp,
        priceAtTime: currentPrice,
        rateAtTime: subscriptionRate
      })
    );

    subscriptionRate = newSubscriptionRate;
  }
}
