// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Utils.sol";
import "./ISubscriptionPoolErrors.sol";
import "./KeyFactory.sol";
import "./Common.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./SubscriptionKeys.sol";

// TODO ADD PERMISSION GROUPS

contract SubscriptionPool is ISubscriptionPoolErrors {
  event FeeCollected(
    uint256 feeCollected,
    uint256 deposit,
    uint256 liquidationStartedAt
  );

  using EnumerableMap for EnumerableMap.AddressToUintMap;

  mapping(address trader => Common.SubscriptionPoolCheckpoint checkpoint)
    internal _subscriptionCheckpoints;

  mapping(address trader => EnumerableMap.AddressToUintMap)
    internal _traderKeyContractBalances;

  address factoryContract;

  // min percentage (10%) of total stated price that
  // must be convered by subscriptionPool
  uint256 internal minimumPoolRatio = 1000;
  // 100% pool percent
  uint256 internal maxMinimumPoolRatio = 10000;

  constructor(address _factoryContract) {
    factoryContract = _factoryContract;
  }

  function _setMinimumPoolRatio(uint256 newMinimumPoolRatio) internal {
    minimumPoolRatio = newMinimumPoolRatio;
  }

  function getTraderContracts(
    address trader
  ) external view returns (Common.ContractInfo[] memory) {
    uint256 length = _traderKeyContractBalances[trader].length();
    Common.ContractInfo[] memory contractInfos = new Common.ContractInfo[](
      length
    );

    for (uint256 i = 0; i < length; i++) {
      (address keyContract, uint256 balance) = _traderKeyContractBalances[
        trader
      ].at(i);
      contractInfos[i] = Common.ContractInfo({
        keyContract: keyContract,
        balance: balance
      });
    }

    return contractInfos;
  }

  function updateTraderInfo(
    address trader,
    uint256 newDeposit,
    uint256 newBal
  ) external {
    require(
      KeyFactory(factoryContract).isValidDeployment(msg.sender),
      "Invalid artist contract"
    );

    // update pool checkpoint
    _updateTraderPool(trader, newDeposit);

    if (newBal == 0) {
      _traderKeyContractBalances[trader].remove(msg.sender);
    } else {
      _traderKeyContractBalances[trader].set(msg.sender, newBal);
    }
  }

  function getCurrentPoolRequirement(
    address trader
  ) public view returns (uint256) {
    // Initialize the total pool requirement to 0
    uint256 totalPoolRequirement = _getUnchangingPoolRequirement(
      trader,
      address(0)
    );

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

  // function getCurrentPoolRequirementForSell(
  //   address trader,
  //   address sellContract,
  //   uint256 amount
  // ) external view returns (uint256) {
  //   require(
  //     KeyFactory(factoryContract).isValidDeployment(sellContract),
  //     "Invalid artist contract"
  //   );

  //   uint256 totalRequirement = _getUnchangingPoolRequirement(
  //     trader,
  //     sellContract
  //   );
  //   // For the calling contract, calculate the requirement after the buy
  //   uint256 newPrice = SubscriptionKeys(sellContract).getSellPrice(amount);
  //   uint256 balance = SubscriptionKeys(sellContract).balanceOf(trader);
  //   require(balance >= amount, "Insufficient balance");

  //   uint256 additionalRequirement = (newPrice *
  //     (balance - amount) *
  //     minimumPoolRatio) / 10000;

  //   // Add the additional requirement to the total requirement
  //   totalRequirement += additionalRequirement;

  //   return totalRequirement;
  // }

  function _getUnchangingPoolRequirement(
    address trader,
    address changingContract
  ) internal view returns (uint256) {
    uint256 totalRequirement = 0;

    uint256 length = _traderKeyContractBalances[trader].length();

    for (uint256 i = 0; i < length; i++) {
      (address keyContract, uint256 balance) = _traderKeyContractBalances[
        trader
      ].at(i);

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
    address trader
  ) public view returns (Common.SubscriptionPoolCheckpoint memory) {
    return _subscriptionCheckpoints[trader];
  }

  function _updateTraderPool(address trader, uint256 newSubPool) internal {
    Common.SubscriptionPoolCheckpoint storage cp = _subscriptionCheckpoints[
      trader
    ];
    cp.deposit = newSubPool;
    cp.lastModifiedAt = block.timestamp;
  }
}
