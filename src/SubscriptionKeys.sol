// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionPool} from "./SubscriptionPool.sol";
import {ISubscriptionKeysErrors} from "./errors/ISubscriptionKeysErrors.sol";
import "./ComputeUtils.sol";
import "./Common.sol";
import {TraderKeyTracker} from "./TraderKeyTracker.sol";
import "forge-std/console.sol";

struct Proof {
  address keySubject;
  Common.PriceChange[] pcs;
}

struct TraderInfoForSubject {
  uint128 lastHistoricalPriceIdx;
  uint128 lastInteractionTime;
}

struct RunningTotal {
  uint256 weightedSum; // Sum of products: price * time
  uint256 totalDuration; // Total duration that contributed to the sum
  uint256 lastUpdateTime; // Last time the price was updated
  uint256 lastPrice; // The last price that was set
}

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
contract SubscriptionKeys is
  TraderKeyTracker,
  SubscriptionPool,
  ISubscriptionKeysErrors
{
  event Trade(
    address trader,
    address subject,
    bool isBuy,
    uint256 shareAmount,
    uint256 ethAmount,
    uint256 supply
  );

  // TODO replace _balances with EnumerableMap implementation
  mapping(address trader => mapping(address keySubject => uint256))
    private _balances;
  mapping(address keySubject => uint256) public keySupply;

  // TODO make subscriptinoRate changes work
  mapping(address keySubject => Common.PriceChange[])
    internal historicalPriceChanges;
  mapping(address keySubject => bytes32[]) private historicalPriceHashes;

  mapping(address keySubject => RunningTotal) internal runningTotals;

  mapping(address keySubject => mapping(address trader => TraderInfoForSubject))
    internal traderInfos;

  mapping(address keySubject => uint256) internal periodLastOccuredAt;

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

    runningTotals[_keySubject] = RunningTotal({
      weightedSum: 0,
      totalDuration: 0,
      lastUpdateTime: block.timestamp,
      lastPrice: 0
    });

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

    // collect fees
    Common.SubjectTraderInfo[] memory subInfos = getTraderSubjectInfo(trader);
    uint256 fees = _verifyAndCollectFees(subInfos, keySubject, trader, proofs);

    // confirm that the trader has enough in the deposit for subscription
    uint256 req = getPoolRequirementForBuy(trader, address(this), amount);
    uint256 additionalDeposit = msg.value - price;
    uint256 existingDeposit = getSubscriptionPool(trader);
    require(additionalDeposit + existingDeposit > fees, "Insufficient pool");
    uint256 newDeposit = additionalDeposit + existingDeposit - fees;
    require(req <= newDeposit, "Insufficient pool");

    // adjust supply
    uint256 newBal = _balances[trader][keySubject] + amount;
    keySupply[keySubject] += amount;
    _balances[trader][keySubject] = newBal;

    // update checkpoints
    _updateOwnedSubjectSet(newBal, trader, keySubject);
    _updateTraderPool(trader, newDeposit);
    _updatePriceOracle(keySubject, price);
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
    _balances[msg.sender][keySubject] = newBal;
    supply = supply - amount;

    _updateOwnedSubjectSet(newBal, trader, keySubject);
    _updateTraderPool(trader, newDeposit);
    _updatePriceOracle(keySubject, price);

    (bool success1, ) = msg.sender.call{value: price}("");
    require(success1, "Unable to send funds");
  }

  function _updatePriceOracle(address keySubject, uint256 newPrice) internal {
    uint256 currentTime = block.timestamp;
    RunningTotal storage total = runningTotals[keySubject];

    // Check if a full period has elapsed
    if (currentTime - periodLastOccuredAt[keySubject] >= period) {
      // Calculate the time-weighted average price for the period
      uint256 averagePrice;
      if (total.totalDuration > 0) {
        averagePrice = total.weightedSum / total.totalDuration;
      } else {
        // No price change occurred during this period; use the last known price
        averagePrice = total.lastPrice;
      }

      _addHistoricalPriceChange(keySubject, averagePrice, currentTime);

      // Reset the weighted sum and duration for the new period
      total.weightedSum = 0;
      total.totalDuration = 0;
      total.lastUpdateTime = currentTime;
      periodLastOccuredAt[keySubject] = currentTime;
    }

    uint256 timeElapsed = currentTime - total.lastUpdateTime;
    if (timeElapsed > 0) {
      total.weightedSum += (total.lastPrice * timeElapsed) * SCALE;
      total.totalDuration += timeElapsed * SCALE;
      total.lastUpdateTime = currentTime;
    }
    total.lastPrice = newPrice;
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
    Common.SubjectTraderInfo[] memory subInfos,
    address buySubject,
    address trader,
    Proof[] calldata proofs
  ) internal returns (uint256 _feesCollected) {
    uint256 feesCollected = collectFeesForOwnedSubjects(
      buySubject,
      trader,
      subInfos,
      proofs
    );

    bool found;
    for (uint256 i = 0; i < proofs.length; i++) {
      if (proofs[i].keySubject == buySubject) {
        found = true;
        Common.SubjectTraderInfo memory info = Common.SubjectTraderInfo({
          keySubject: proofs[i].keySubject,
          balance: balanceOf(buySubject, trader)
        });
        uint256 subjectFee = _calculateFeeForSubject(info, trader, proofs);
        (bool success, ) = info.keySubject.call{value: subjectFee}("");
        require(success, "Unable to send funds");

        feesCollected += subjectFee;
      }
    }
    if (!found) revert SubjectProofMissing({subject: buySubject});

    return feesCollected;
  }

  function collectFeesForOwnedSubjects(
    address subject,
    address trader,
    Common.SubjectTraderInfo[] memory subInfos,
    Proof[] calldata proofs
  ) internal returns (uint256 _feesCollected) {
    uint256 feesCollected = 0;
    for (uint256 i = 0; i < subInfos.length; i++) {
      if (subInfos[i].keySubject == subject) {
        continue;
      }

      Common.SubjectTraderInfo memory info = subInfos[i];
      uint256 feeForSubject = _calculateFeeForSubject(info, trader, proofs);
      (bool success, ) = info.keySubject.call{value: feeForSubject}("");
      require(success, "Unable to send funds");

      feesCollected += feeForSubject;
    }

    return feesCollected;
  }

  function _calculateFeeForSubject(
    Common.SubjectTraderInfo memory subjectInfo,
    address trader,
    Proof[] calldata proofs
  ) internal returns (uint256 _fee) {
    bytes32 initialHash = getStartHash(subjectInfo.keySubject, trader);

    for (uint256 j = 0; j < proofs.length; j++) {
      if (proofs[j].keySubject == subjectInfo.keySubject) {
        TraderInfoForSubject memory info = traderInfos[subjectInfo.keySubject][
          trader
        ];
        uint256 lastInteractionTime = uint256(info.lastInteractionTime);
        (uint256 fee, bytes32 h) = getFeeWithFinalHash(
          lastInteractionTime,
          initialHash,
          proofs[j],
          subjectInfo.balance
        );
        verifyHash(h, subjectInfo.keySubject, trader);

        return fee;
      }
    }

    revert SubjectProofMissing({subject: subjectInfo.keySubject});
  }

  // ------------ fee calculation methods ----------------

  function getFeeWithFinalHash(
    uint256 lastInteractionTime,
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

      // if Proof contains elements before their last iteraction index don't count toward fee
      if (lastInteractionTime > nextTimestamp) {
        continue;
      }

      uint256 lastTimestamp = pastPrices[i].startTimestamp;
      uint256 startInterestAt = lastInteractionTime > lastTimestamp &&
        lastInteractionTime <= nextTimestamp
        ? lastInteractionTime
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

  function verifyHash(bytes32 h, address keySubject, address trader) internal {
    bytes32[] storage his = historicalPriceHashes[keySubject];

    // Check if the hash is valid
    bool valid = his[his.length - 1] == h;
    if (!valid) revert InvalidProof({subject: keySubject});

    // Update the trader information with the new historical price index and interaction time
    TraderInfoForSubject storage info = traderInfos[keySubject][trader];
    info.lastHistoricalPriceIdx = uint128(his.length - 1);
    info.lastInteractionTime = uint128(block.timestamp);
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
      historicalPriceHashes[keySubject][
        getLastTraderPriceIndex(keySubject, trader) - 1
      ];
  }

  function getLastTraderPriceIndex(
    address keySubject,
    address trader
  ) public view returns (uint256) {
    uint256 bal = balanceOf(keySubject, trader);

    TraderInfoForSubject memory info = traderInfos[keySubject][trader];
    uint256 idx = uint256(info.lastHistoricalPriceIdx);
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

  // TODO these need to extract fees
  function increaseSubscriptionPool(Proof[] calldata proofs) external payable {
    address trader = msg.sender;

    Common.SubjectTraderInfo[] memory subInfos = getTraderSubjectInfo(trader);
    uint256 fees = collectFeesForOwnedSubjects(
      address(0),
      trader,
      subInfos,
      proofs
    );
    uint256 existingDeposit = getSubscriptionPool(trader);
    uint256 newDeposit = existingDeposit + msg.value - fees;

    uint256 req = _getUnchangingPoolRequirement(trader, address(0));
    if (req > newDeposit) revert InsufficientSubscriptionPool();

    _updateTraderPool(trader, newDeposit);
  }

  function decreaseSubscriptionPool(
    uint256 amount,
    Proof[] calldata proofs
  ) external {
    address trader = msg.sender;
    // collect fees
    Common.SubjectTraderInfo[] memory subInfos = getTraderSubjectInfo(trader);
    uint256 fees = collectFeesForOwnedSubjects(
      address(0),
      trader,
      subInfos,
      proofs
    );

    uint256 existingDeposit = getSubscriptionPool(trader);
    uint256 newDeposit = existingDeposit - fees - amount;

    uint256 req = _getUnchangingPoolRequirement(trader, address(0));

    if (req > newDeposit) revert InsufficientSubscriptionPool();

    _updateTraderPool(trader, newDeposit);

    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Unable to send funds");
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
    for (uint256 i = 0; i < getNumUniqueSubjects(trader); i++) {
      (address keySubject, uint256 balance) = getUniqueTraderSubjectAtIndex(
        trader,
        i
      );
      if (keySubject == buySubject) {
        continue;
      }

      uint256 price = getCurrentPrice(buySubject);
      uint256 requirement = (price * balance * minimumPoolRatio) / 10000;

      totalRequirement += requirement;
    }

    return totalRequirement;
  }

  // TODO liquidation
}
