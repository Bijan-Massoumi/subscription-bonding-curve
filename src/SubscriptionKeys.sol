// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionPool} from "./SubscriptionPool.sol";
import "./ComputeUtils.sol";
import "./Common.sol";
import {TraderKeyTracker} from "./TraderKeyTracker.sol";
import "forge-std/console.sol";

struct Proof {
  address keySubject;
  Common.PriceChange[] pcs;
}

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
contract SubscriptionKeys is TraderKeyTracker, SubscriptionPool {
  event Trade(
    address trader,
    address subject,
    bool isBuy,
    uint256 shareAmount,
    uint256 ethAmount,
    uint256 supply
  );

  // Mapping owner address to token count
  mapping(address trader => mapping(address keySubject => uint256))
    private _balances;
  mapping(address keySubject => uint256) public keySupply;

  // TODO make subscriptinoRate changes work
  mapping(address keySubject => Common.PriceChange[])
    private historicalPriceChanges;
  mapping(address keySubject => bytes32[]) private historicalPriceHashes;
  mapping(address keySubject => Common.PriceChange[])
    private recentPriceChanges;
  mapping(address keySubject => mapping(address => uint256))
    private _lastHistoricalPriceByTrader;
  mapping(address keySubject => mapping(address => uint256))
    private _lastTraderInteractionTime;
  mapping(address keySubject => uint256) private periodLastOccuredAt;

  // This mapping is used to check if a keySubject is already initialized
  mapping(address keySubject => bool) private initializedKeySubjects;

  uint256 period = 43_200;

  // 100% fee rate
  uint256 internal maxSubscriptionRate = 10000;

  // TODO add signature
  function initializeKeySubject(uint256 _subscriptionRate) public {
    address _keySubject = msg.sender;
    require(
      !initializedKeySubjects[_keySubject],
      "KeySubject already initialized"
    );

    initializedKeySubjects[_keySubject] = true;

    // first period has no interest rate on buys
    Common.PriceChange memory newPriceChange = Common.PriceChange({
      price: 0,
      rate: uint128(_subscriptionRate),
      startTimestamp: uint112(block.timestamp),
      index: 0
    });

    // initialize genesis price change
    historicalPriceChanges[_keySubject].push(newPriceChange);
    bytes32 h = keccak256(abi.encode(newPriceChange, bytes32(0)));
    historicalPriceHashes[_keySubject].push(h);
  }

  // Bonding Curve methods ------------------------
  function getPrice(
    uint256 _supply,
    uint256 amount
  ) public pure returns (uint256) {
    uint256 sum1 = _supply == 0
      ? 0
      : ((_supply - 1) * (_supply) * (2 * (_supply - 1) + 1)) / 6;

    uint256 sum2 = _supply == 0 && amount == 1
      ? 0
      : ((_supply - 1 + amount) *
        (_supply + amount) *
        (2 * (_supply - 1 + amount) + 1)) / 6;

    uint256 summation = sum2 - sum1;
    return (summation * 1 ether) / 16000;
  }

  function getBuyPrice(
    address keySubject,
    uint256 amount
  ) public view returns (uint256) {
    return getPrice(keySupply[keySubject], amount);
  }

  function getSellPrice(
    address keySubject,
    uint256 amount
  ) public view returns (uint256) {
    return getPrice(keySupply[keySubject] - amount, amount);
  }

  function getSupply(address keySubject) public view returns (uint256) {
    return keySupply[keySubject];
  }

  function balanceOf(
    address _keySubject,
    address trader
  ) public view returns (uint256) {
    return _balances[trader][_keySubject];
  }

  function getCurrentPrice(address keySubject) public view returns (uint256) {
    return getPrice(keySupply[keySubject], 1);
  }

  // TODO is there a way to liquidate people before we buy to ensure the best price?
  function buyKeys(
    address keySubject,
    uint256 amount,
    Proof[] calldata proofs
  ) public payable {
    require(amount > 0, "Cannot buy 0 keys");
    uint256 price = getPrice(keySupply[keySubject], amount);
    require(msg.value >= price, "Inusfficient nft price");
    address trader = msg.sender;
    // fetch last subscription deposit checkpoint
    uint256 deposit = getSubscriptionPool(trader);
    // collect fees
    Common.SubjectTraderInfo[] memory subInfo = getTraderSubjectInfo(trader);

    uint256 fees = _verifyAndCollectFees(subInfo, keySubject, trader, proofs);

    // confirm that the trader has enough in the deposit for subscription
    uint256 req = getPoolRequirementForBuy(trader, address(this), amount);
    uint256 additionalDeposit = msg.value - price;
    require(additionalDeposit + deposit > fees, "Insufficient pool");
    uint256 newDeposit = additionalDeposit + deposit - fees;
    require(req <= newDeposit, "Insufficient pool");

    // adjust supply
    uint256 newBal = _balances[trader][keySubject] + amount;
    keySupply[keySubject] += amount;
    _balances[trader][keySubject] = newBal;

    // update checkpoints
    _updateBalances(newBal, trader, keySubject);
    _updateTraderPool(trader, newDeposit);
    _updatePriceOracle(keySubject, price);
    _lastTraderInteractionTime[keySubject][trader] = block.timestamp;

    // send fees to keySubject
    (bool success, ) = keySubject.call{value: fees}("");
    require(success, "Unable to send funds");
  }

  function sellKeys(
    address keySubject,
    uint256 amount,
    Proof[] calldata proofs
  ) public {
    // TODO reconsider conditions
    uint256 supply = keySupply[keySubject];
    require(supply > amount, "Cannot sell the last key");
    require(amount > 0, "Cannot sell 0 keys");

    uint256 price = getPrice(supply - amount, amount);
    address trader = msg.sender;
    uint256 currBalance = _balances[trader][keySubject];
    require(currBalance >= amount, "Insufficient keys");

    // fetch last subscription deposit checkpoint
    uint256 subPool = getSubscriptionPool(trader);

    // collect fees
    Common.SubjectTraderInfo[] memory subInfo = getTraderSubjectInfo(trader);
    uint256 fees = _verifyAndCollectFees(subInfo, keySubject, trader, proofs);

    // update checkpoints
    uint256 newBal = currBalance - amount;
    uint256 newDeposit = subPool - fees;

    _updateBalances(newBal, trader, keySubject);
    _updateTraderPool(trader, newDeposit);
    _updatePriceOracle(keySubject, price);
    _lastTraderInteractionTime[keySubject][trader] = block.timestamp;
    _balances[msg.sender][keySubject] = newBal;
    supply = supply - amount;

    (bool success1, ) = msg.sender.call{value: price}("");
    (bool success2, ) = keySubject.call{value: fees}("");
    require(success1 && success2, "Unable to send funds");
  }

  function _updatePriceOracle(address keySubject, uint256 newPrice) internal {
    uint256 currentTime = block.timestamp;

    // Check if a full period has elapsed
    if (currentTime - periodLastOccuredAt[keySubject] >= period) {
      // If there's at least one price change in the recent changes
      uint256 averagePrice;
      if (recentPriceChanges[keySubject].length > 0) {
        // Calculate the time-weighted average
        averagePrice = ComputeUtils.calculateTimeWeightedAveragePrice(
          recentPriceChanges[keySubject],
          currentTime
        );
      } else {
        uint256 len = historicalPriceChanges[keySubject].length - 1;
        averagePrice = historicalPriceChanges[keySubject][len].price;
      }

      _addHistoricalPriceChange(keySubject, averagePrice, currentTime);

      // Reset the recentPriceChanges and update the period's last occurrence time
      delete recentPriceChanges[keySubject];
      periodLastOccuredAt[keySubject] = currentTime;
    }

    // TODO check if last elem has the same timestamp and combine if so
    // add the new price to recentPriceChanges
    Common.PriceChange memory newRecentPriceChange = Common.PriceChange({
      price: newPrice,
      rate: historicalPriceChanges[keySubject][
        historicalPriceChanges[keySubject].length - 1
      ].rate,
      startTimestamp: uint112(currentTime),
      index: uint16(recentPriceChanges[keySubject].length)
    });

    recentPriceChanges[keySubject].push(newRecentPriceChange);
  }

  function _addHistoricalPriceChange(
    address keySubject,
    uint256 averagePrice,
    uint256 currentTime
  ) internal {
    Common.PriceChange memory newHistoricalPriceChange = Common.PriceChange({
      price: averagePrice,
      rate: historicalPriceChanges[keySubject][
        historicalPriceChanges[keySubject].length - 1
      ].rate,
      startTimestamp: uint112(currentTime),
      index: uint16(historicalPriceChanges[keySubject].length)
    });
    historicalPriceChanges[keySubject].push(newHistoricalPriceChange);

    // Hash chaining
    bytes32 previousHash = historicalPriceHashes[keySubject][
      historicalPriceHashes[keySubject].length - 1
    ];
    bytes32 newHash = keccak256(
      abi.encode(newHistoricalPriceChange, previousHash)
    );
    historicalPriceHashes[keySubject].push(newHash);
  }

  function _verifyAndCollectFees(
    Common.SubjectTraderInfo[] memory subInfo,
    address buySubject,
    address trader,
    Proof[] calldata proofs
  ) internal returns (uint256 _fees) {
    uint256 fees = 0;
    for (uint256 i = 0; i < subInfo.length; i++) {
      if (subInfo[i].keySubject == buySubject) {
        continue;
      }

      Common.SubjectTraderInfo memory info = subInfo[i];
      uint256 feeForSubject = _calculateFeeForSubject(info, trader, proofs);
      fees += feeForSubject;
    }

    bool found;
    for (uint256 i = 0; i < proofs.length; i++) {
      if (proofs[i].keySubject == buySubject) {
        found = true;
        Common.SubjectTraderInfo memory info = Common.SubjectTraderInfo({
          keySubject: proofs[i].keySubject,
          balance: balanceOf(buySubject, trader)
        });
        fees += _calculateFeeForSubject(info, trader, proofs);
      }
    }
    require(found, "No proof for buying keySubject");

    return fees;
  }

  function _calculateFeeForSubject(
    Common.SubjectTraderInfo memory subjectInfo,
    address trader,
    Proof[] calldata proofs
  ) internal returns (uint256 _fee) {
    bytes32 initialHash = getStartHash(subjectInfo.keySubject, trader);

    for (uint256 j = 0; j < proofs.length; j++) {
      if (proofs[j].keySubject == subjectInfo.keySubject) {
        uint256 lastDepositTime = _lastTraderInteractionTime[
          subjectInfo.keySubject
        ][trader];
        (uint256 fee, bytes32 h) = getFeeWithFinalHash(
          lastDepositTime,
          initialHash,
          proofs[j],
          subjectInfo.balance
        );
        require(verifyHash(h, trader), "Invalid proof");

        return fee;
      }
    }

    revert("No matching Proof found for keySubject");
  }

  // ------------ fee calculation methods ----------------

  function getFeeWithFinalHash(
    uint256 lastCheckpointAt,
    bytes32 initialHash,
    Proof calldata proof,
    uint256 balance
  ) internal view returns (uint256 fees, bytes32 h) {
    Common.PriceChange[] calldata pastPrices = proof.pcs;
    require(pastPrices.length > 0, "No past prices");

    bytes32 currentHash = initialHash;
    uint256 endIndex = pastPrices.length - 1;
    uint256 totalFee = 0;
    for (uint256 i = 0; i <= endIndex; i++) {
      // Update the hash chain
      currentHash = keccak256(abi.encode(pastPrices[i], currentHash));
      uint256 nextTimestamp = i < endIndex
        ? pastPrices[i + 1].startTimestamp
        : block.timestamp;
      if (lastCheckpointAt > nextTimestamp) {
        continue;
      }

      uint256 lastTimestamp = pastPrices[i].startTimestamp;
      uint256 startInterestAt = lastCheckpointAt > lastTimestamp &&
        lastCheckpointAt <= nextTimestamp
        ? lastCheckpointAt
        : lastTimestamp;

      totalFee += ComputeUtils._calculateFeeBetweenTimes(
        balance * pastPrices[i].price,
        startInterestAt,
        nextTimestamp,
        pastPrices[i].rate
      );
    }

    return (totalFee, currentHash);
  }

  function verifyHash(
    bytes32 h,
    address keySubject,
    address trader
  ) internal returns (bool) {
    bytes32[] memory his = historicalPriceHashes[keySubject];
    bool valid = his[his.length - 1] == h;
    if (valid) {
      _lastHistoricalPriceByTrader[keySubject][trader] = his.length - 1;
      return true;
    }

    return false;
  }

  function getStartHash(
    address keySubject,
    address trader
  ) public view returns (bytes32) {
    uint256 lastPriceIndex = getLastTraderPriceIndex(keySubject, trader);
    if (lastPriceIndex == 0) {
      return bytes32(0);
    }

    // get hash right before the traders price change. The prover will hash chain off of this
    return
      historicalPriceHashes[keySubject][getLastTraderPriceIndex(trader) - 1];
  }

  function getLastTraderPriceIndex(
    address keySubject,
    address trader
  ) public view returns (uint256) {
    uint256 bal = balanceOf(keySubject, trader);
    uint256 idx = _lastHistoricalPriceByTrader[keySubject][trader];
    if (bal == 0) {
      return historicalPriceChanges[keySubject].length - 1;
    }

    return idx;
  }

  function getPriceProof(
    address keySubject,
    address trader
  ) external view returns (Proof memory) {
    require(initializedKeySubjects[keySubject], "KeySubject not initialized");

    uint256 startIndex = getLastTraderPriceIndex(keySubject, trader);
    uint256 length = historicalPriceChanges[keySubject].length - startIndex;
    Common.PriceChange[] memory pc = new Common.PriceChange[](length);
    for (uint256 i = 0; i < length; i++) {
      pc[i] = historicalPriceChanges[keySubject][startIndex + i];
    }

    return Proof({keySubject: keySubject, pcs: pc});
  }

  // -------------- Pool Requirement methods ----------------
  // -------------- subscription pool methods ----------------

  // TODO these need to extract fees
  function increaseSubscriptionPool(address trader) external payable {
    // uint256 subPool = getSubscriptionPool(trader);
    // uint256 newDeposit = subPool + msg.value;
    // _updateTraderPool(msg.sender, newDeposit);
  }

  // TODO
  function decreaseSubscriptionPool(uint256 amount) external {
    //   uint256 subPool = getSubscriptionPool(msg.sender, groupId);
    //   uint256 req = getCurrentPoolRequirement(msg.sender, groupId);
    //   require(subPool >= amount, "Insufficient deposit");
    //   require(
    //     subPool - amount >= req,
    //     "Deposit cannot be less than current requirement"
    //   );
    //   uint256 newDeposit = subPool - amount;
    //   _updateTraderPool(msg.sender, 0, newDeposit);
    //   // Transfer the amount to the trader
    //   (bool success, ) = msg.sender.call{value: amount}("");
    //   require(success, "Transfer failed");
    // }
    // function getCurrentPoolRequirement(
    //   address trader
    // ) public view returns (uint256) {
    //   // Initialize the total pool requirement to 0
    //   uint256 totalPoolRequirement = _getUnchangingPoolRequirement(
    //     trader,
    //     address(0)
    //   );
    //   return totalPoolRequirement;
  }

  function getPoolRequirementForBuy(
    address trader,
    address buySubject,
    uint256 amount
  ) public view returns (uint256) {
    uint256 totalRequirement = _getUnchangingPoolRequirement(
      trader,
      buySubject
    );

    // For the calling subject, calculate the requirement after the buy
    uint256 newPrice = getBuyPrice(buySubject, amount);
    uint256 newBalance = balanceOf(buySubject, trader) + amount;
    uint256 additionalRequirement = (newPrice * newBalance * minimumPoolRatio) /
      10000;

    // Add the additional requirement to the total requirement
    totalRequirement += additionalRequirement;

    return totalRequirement;
  }

  function _getUnchangingPoolRequirement(
    address trader,
    address buySubject
  ) internal view returns (uint256) {
    uint256 totalRequirement = 0;
    uint256 length = _groupedTraderKeyContractBalances[trader].length();

    for (uint256 i = 0; i < length; i++) {
      (address keySubject, uint256 balance) = _groupedTraderKeyContractBalances[
        trader
      ].at(i);
      if (keySubject == buySubject) {
        continue;
      }

      uint256 price = getCurrentPrice(buySubject);
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      totalRequirement += requirement;
    }

    return totalRequirement;
  }
}
