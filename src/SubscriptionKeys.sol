// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SubscriptionPool} from "./SubscriptionPool.sol";
import {ISubscriptionKeysErrors} from "./errors/ISubscriptionKeysErrors.sol";
import "./ComputeUtils.sol";
import "./Common.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {TraderKeyTracker} from "./TraderKeyTracker.sol";
import "forge-std/console.sol";

struct Proof {
  address keySubject;
  Common.PriceChange[] pcs;
}

struct FeeBreakdown {
  uint256 fees;
  address keySubject;
}

struct PriceInteractionRecord {
  uint128 lastHistoricalPriceIdx;
  uint128 lastInteractionTime;
}

struct RunningTotal {
  uint256 weightedSum;
  uint256 totalDuration;
  uint256 lastUpdateTime;
  uint256 lastPrice;
}

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
contract SubscriptionKeys is
  TraderKeyTracker,
  SubscriptionPool,
  ISubscriptionKeysErrors,
  Ownable
{
  event Trade(
    address trader,
    address subject,
    bool isBuy,
    uint256 keyAmount,
    uint256 ethAmount,
    uint256 supply
  );
  event NewInitializedKeySubject(address keySubject);
  event Liquidation(address liquidator, address liquidatedSub, uint256 amount);
  event FeesCollected(address trader, address keySubject, uint256 amount);
  event PriceOracleUpdated(address keySubject, uint256 newPrice);

  // TODO replace _balances with EnumerableMap implementation
  mapping(address trader => mapping(address keySubject => uint256))
    private _balances;
  mapping(address keySubject => uint256) public keySupply;
  mapping(address keySubject => bool) private initializedKeySubjects;

  mapping(address keySubject => Common.PriceChange[])
    internal historicalPriceChanges;
  mapping(address keySubject => bytes32[]) private historicalPriceHashes;
  mapping(address keySubject => RunningTotal) internal runningTotals;
  mapping(address keySubject => uint256) internal periodLastOccuredAt;
  mapping(address keySubject => mapping(address trader => PriceInteractionRecord))
    internal traderInfos;

  uint256 protocolFeePercent;
  address protocolFeeDestination;
  uint256 liquidationPenalty;
  uint256 subscriptionRate;

  // 12 HOURS
  uint256 period = 43_200;

  // 100% fee rate
  uint256 internal maxSubscriptionRate = 10000;

  constructor() Ownable() {}

  function setProtocolFeePercent(uint256 _feePercent) public onlyOwner {
    protocolFeePercent = _feePercent;
  }

  function getProtocolFeePercent() public view returns (uint256) {
    return protocolFeePercent;
  }

  function setProtocolFeeDestination(address _feeDestination) public onlyOwner {
    protocolFeeDestination = _feeDestination;
  }

  function getProtocolFeeDestination() public view returns (address) {
    return protocolFeeDestination;
  }

  function setLiquidationPenalty(uint256 _penalty) public onlyOwner {
    liquidationPenalty = _penalty;
  }

  function getLiquidationPenalty() public view returns (uint256) {
    return liquidationPenalty;
  }

  function setSubscriptionRate(uint256 _subscriptionRate) public onlyOwner {
    subscriptionRate = _subscriptionRate;
  }

  function getSubscriptionRate() public view returns (uint256) {
    return subscriptionRate;
  }

  // TODO add signature
  function initializeKeySubject() public {
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
      rate: uint128(subscriptionRate),
      startTimestamp: uint112(block.timestamp),
      index: 0
    });
    // initialize genesis price change
    historicalPriceChanges[_keySubject].push(newPriceChange);
    bytes32 h = keccak256(abi.encode(newPriceChange, bytes32(0)));
    historicalPriceHashes[_keySubject].push(h);

    periodLastOccuredAt[_keySubject] = block.timestamp;
    emit NewInitializedKeySubject(_keySubject);
  }

  // Bonding Curve methods ------------------------ 00000000000000000000000000000000000000000000000000000000655629f8
  function getPrice(
    uint256 _supply,
    uint256 amount
  ) public pure returns (uint256) {
    require(
      _supply + amount >= _supply,
      "Integer overflow in supply calculation"
    );

    uint256 sum1 = _supply == 0 ? 0 : sumOfSquares(_supply - 1);
    uint256 sum2 = sumOfSquares(_supply + amount - 1);

    uint256 summation = sum2 - sum1;
    return (summation * 1 ether) / 16000;
  }

  function sumOfSquares(uint256 x) internal pure returns (uint256) {
    return (x * (x + 1) * (2 * x + 1)) / 6;
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

  function getBuyPriceAfterFee(
    address sharesSubject,
    uint256 amount
  ) public view returns (uint256) {
    uint256 price = getBuyPrice(sharesSubject, amount);
    uint256 protocolFee = getProtocalFee(price);
    return price + protocolFee;
  }

  function getSellPriceAfterFee(
    address sharesSubject,
    uint256 amount
  ) public view returns (uint256) {
    uint256 price = getSellPrice(sharesSubject, amount);
    uint256 protocolFee = getProtocalFee(price);
    return price - protocolFee;
  }

  function getProtocalFee(uint256 price) public view returns (uint256) {
    return (price * protocolFeePercent) / 1 ether;
  }

  // TODO add test suite for bond requirment
  function calculateBondRequirement(
    uint256 supply,
    uint256 bal
  ) public view returns (uint256) {
    uint256 price = getPrice(supply, 1);
    uint256 requirement = (price * bal * minimumPoolRatio) / 1 ether;
    return requirement;
  }

  function getLiquidationPayment(uint256 price) public view returns (uint256) {
    uint256 liquidationAmount = ((price) * liquidationPenalty) / 1 ether;
    return liquidationAmount;
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

  function buyKeys(
    address keySubject,
    uint256 amount,
    Proof[] calldata proofs
  ) public payable {
    require(
      initializedKeySubjects[keySubject],
      "KeySubject must be initialized"
    );

    require(amount > 0, "Cannot buy 0 keys");
    uint256 price = getPrice(keySupply[keySubject], amount);
    uint256 protocolFee = getProtocalFee(price);
    require(msg.value >= price + protocolFee, "Inusfficient payment");

    uint256 newDeposit = collectFees(msg.sender, proofs) +
      (msg.value - price - protocolFee);

    // if we didnt already verify a proof for this subject, we need to update the trader info
    if (!traderOwnsKeySubject(msg.sender, keySubject))
      _updatePriceInteractionRecord(keySubject, msg.sender);

    if (getPoolRequirementForBuy(msg.sender, keySubject, amount) > newDeposit)
      revert InsufficientSubscriptionPool();

    _updateTraderPool(msg.sender, newDeposit);

    // adjust supply
    uint256 newBal = _balances[msg.sender][keySubject] + amount;
    _balances[msg.sender][keySubject] = newBal;
    keySupply[keySubject] += amount;
    emit Trade(
      msg.sender,
      keySubject,
      true,
      amount,
      price,
      keySupply[keySubject]
    );
    _updateOwnedSubjectSet(newBal, msg.sender, keySubject);
    _updatePriceOracle(keySubject, getCurrentPrice(keySubject));

    (bool success, ) = protocolFeeDestination.call{value: protocolFee}("");
    if (!success) revert ProtocolFeeTransferFailed();
  }

  function sellKeys(
    address keySubject,
    uint256 amount,
    Proof[] calldata proofs
  ) public {
    require(
      initializedKeySubjects[keySubject],
      "KeySubject must be initialized"
    );

    // TODO reconsider conditions
    uint256 supply = keySupply[keySubject];
    require(amount > 0, "Cannot sell 0 keys");

    uint256 price = getPrice(supply - amount, amount);
    uint256 currBalance = _balances[msg.sender][keySubject];
    require(currBalance >= amount, "Insufficient keys");

    _updateTraderPool(msg.sender, collectFees(msg.sender, proofs));
    // update checkpoints
    uint256 newBal = currBalance - amount;
    _balances[msg.sender][keySubject] = newBal;
    keySupply[keySubject] -= amount;
    emit Trade(
      msg.sender,
      keySubject,
      false,
      amount,
      price,
      keySupply[keySubject]
    );
    _updateOwnedSubjectSet(newBal, msg.sender, keySubject);
    _updatePriceOracle(keySubject, getCurrentPrice(keySubject));

    uint256 protocolFee = getProtocalFee(price);
    (bool success1, ) = msg.sender.call{value: price - protocolFee}("");
    (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
    require(success1 && success2, "Unable to send funds");
  }

  function collectFees(
    address trader,
    Proof[] calldata proofs
  ) internal returns (uint256 _newDeposit) {
    uint256 lastSubPool = getSubscriptionPool(trader);
    Common.SubjectTraderInfo[] memory subInfo = getTraderSubjectInfo(trader);
    (FeeBreakdown[] memory breakdown, uint256 totalFees) = _getFeeBreakdown(
      subInfo,
      trader,
      proofs
    );
    return _distributeFees(breakdown, lastSubPool, totalFees, trader);
  }

  function _distributeFees(
    FeeBreakdown[] memory breakdown,
    uint256 lastSubPool,
    uint256 totalFees,
    address trader
  ) internal returns (uint256) {
    if (totalFees <= lastSubPool) {
      for (uint256 i = 0; i < breakdown.length; i++) {
        address keySub = breakdown[i].keySubject;
        (bool sent, ) = keySub.call{value: breakdown[i].fees}("");
        require(sent, "Fee transfer failed");
        lastSubPool -= breakdown[i].fees;
        emit FeesCollected(trader, keySub, breakdown[i].fees);

        // Update the trader information with the new historical price index and interaction time
        _updatePriceInteractionRecord(keySub, trader);
      }
    } else {
      uint256 totalScaledFees = totalFees * 1 ether;
      for (uint256 i = 0; i < breakdown.length; i++) {
        uint256 feeProportion = (breakdown[i].fees * lastSubPool * 1 ether) /
          totalScaledFees;
        address keySub = breakdown[i].keySubject;
        (bool sent, ) = keySub.call{value: feeProportion}("");
        require(sent, "Pro-rata fee transfer failed");
        emit FeesCollected(trader, keySub, breakdown[i].fees);

        // Update the trader information with the new historical price index and interaction time
        _updatePriceInteractionRecord(keySub, trader);
      }
      lastSubPool = 0;
    }

    return lastSubPool;
  }

  function _getFeeBreakdown(
    Common.SubjectTraderInfo[] memory subInfos,
    address trader,
    Proof[] calldata proofs
  )
    internal
    view
    returns (FeeBreakdown[] memory _breakdown, uint256 _totalFees)
  {
    if (proofs.length != subInfos.length) revert InvalidProofsLength();

    FeeBreakdown[] memory breakdown = new FeeBreakdown[](subInfos.length);
    uint256 totalFees = 0;
    for (uint256 i = 0; i < proofs.length; i++) {
      if (proofs[i].keySubject != subInfos[i].keySubject)
        revert InvalidProofsOrder();

      uint256 feeForSubject = _calculateFeeForSubject(
        subInfos[i],
        trader,
        proofs[i]
      );
      totalFees += feeForSubject;
      breakdown[i] = FeeBreakdown({
        fees: feeForSubject,
        keySubject: subInfos[i].keySubject
      });
    }

    return (breakdown, totalFees);
  }

  function _calculateFeeForSubject(
    Common.SubjectTraderInfo memory subjectInfo,
    address trader,
    Proof calldata proof
  ) internal view returns (uint256 _fee) {
    PriceInteractionRecord memory info = traderInfos[subjectInfo.keySubject][
      trader
    ];
    uint256 lastInteractionTime = uint256(info.lastInteractionTime);
    (uint256 fee, bytes32 h) = getFeeWithFinalHash(
      lastInteractionTime,
      getStartHash(subjectInfo.keySubject, trader),
      proof,
      subjectInfo.balance
    );
    verifyHash(h, subjectInfo.keySubject);

    return fee;
  }

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
      if (lastInteractionTime >= nextTimestamp) {
        continue;
      }

      uint256 lastTimestamp = pastPrices[i].startTimestamp;
      uint256 startInterestAt = lastInteractionTime >= lastTimestamp &&
        lastInteractionTime < nextTimestamp
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

  function verifyHash(bytes32 h, address keySubject) internal view {
    bytes32[] memory his = historicalPriceHashes[keySubject];

    // Check if the hash is valid
    bool valid = his[his.length - 1] == h;
    if (!valid)
      revert InvalidProof({
        subject: keySubject,
        expectedProof: his[his.length - 1],
        actualProof: h
      });
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
      rate: uint128(subscriptionRate),
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

    emit PriceOracleUpdated(keySubject, averagePrice);
  }

  function _updatePriceInteractionRecord(
    address keySubject,
    address trader
  ) internal {
    PriceInteractionRecord storage info = traderInfos[keySubject][trader];
    info.lastHistoricalPriceIdx = uint128(
      historicalPriceHashes[keySubject].length - 1
    );
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
    return historicalPriceHashes[keySubject][lastPriceIndex - 1];
  }

  function getLastTraderPriceIndex(
    address keySubject,
    address trader
  ) public view returns (uint256) {
    uint256 bal = balanceOf(keySubject, trader);

    PriceInteractionRecord memory info = traderInfos[keySubject][trader];
    uint256 idx = uint256(info.lastHistoricalPriceIdx);
    if (bal == 0) {
      return historicalPriceChanges[keySubject].length - 1;
    }

    return idx;
  }

  //getPriceProof only to be used externally to construct proofs to conduct mutations
  function getPriceProof(
    address trader
  ) external view returns (Proof[] memory) {
    Common.SubjectTraderInfo[] memory ownedKeys = getTraderSubjectInfo(trader);
    Proof[] memory proofs = new Proof[](ownedKeys.length);
    for (uint256 i = 0; i < ownedKeys.length; i++) {
      address ks = ownedKeys[i].keySubject;
      uint256 startIndex = getLastTraderPriceIndex(ks, trader);

      uint256 length = historicalPriceChanges[ks].length - startIndex;
      Common.PriceChange[] memory pc = new Common.PriceChange[](length);
      for (uint256 j = 0; j < length; j++) {
        pc[j] = historicalPriceChanges[ks][startIndex + j];
      }
      proofs[i] = Proof({keySubject: ks, pcs: pc});
    }

    return proofs;
  }

  // -------------- Pool Requirement methods ----------------

  // TODO these need to extract fees
  function increaseSubscriptionPool(Proof[] calldata proofs) external payable {
    address trader = msg.sender;

    uint256 newDeposit = collectFees(trader, proofs);
    newDeposit = newDeposit + msg.value;
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
    uint256 newDeposit = collectFees(trader, proofs);
    newDeposit = newDeposit - amount;
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

    uint256 additionalRequirement = calculateBondRequirement(
      keySupply[buySubject] + amount,
      balanceOf(buySubject, trader) + amount
    );
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

      uint256 requirement = calculateBondRequirement(
        keySupply[keySubject],
        balance
      );
      totalRequirement += requirement;
    }

    return totalRequirement;
  }

  // -------------- Liquidation methods ----------------
  function liquidateSubscriber(
    address subscriber,
    address keySubject,
    Proof[] calldata proofs,
    uint256 amount
  ) external {
    require(
      balanceOf(keySubject, subscriber) >= amount,
      "cannot liquidate more than balance"
    );

    uint256 newDeposit = collectFees(subscriber, proofs);
    if (newDeposit != 0) revert CannotLiquidate();
    _updateTraderPool(subscriber, 0);

    uint256 price = getSellPrice(keySubject, amount);
    uint256 protocolFee = getProtocalFee(price);
    uint256 liquidatorPayment = getLiquidationPayment(price - protocolFee);

    // update checkpoints
    uint256 newBal = _balances[subscriber][keySubject] - amount;
    keySupply[keySubject] -= amount;
    _balances[subscriber][keySubject] = newBal;
    _updateOwnedSubjectSet(newBal, subscriber, keySubject);
    _updatePriceOracle(keySubject, getCurrentPrice(keySubject));

    // send payments
    (bool success1, ) = msg.sender.call{value: liquidatorPayment}("");
    (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
    (bool success3, ) = subscriber.call{
      value: price - protocolFee - liquidatorPayment
    }("");
    require(success1 && success2 && success3, "Unable to send funds");
  }
}
