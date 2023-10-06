// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionPool.sol";
import "./ComputeUtils.sol";
import "./Common.sol";
import "forge-std/console.sol";

struct Proof {
  address keyContract;
  Common.PriceChange[] pcs;
}

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
contract SubscriptionKeys {
  event Trade(
    address trader,
    address subject,
    bool isBuy,
    uint256 shareAmount,
    uint256 ethAmount,
    uint256 supply
  );

  // Mapping from token ID to owner address
  mapping(uint256 => address) internal _owners;
  // Mapping owner address to token count
  mapping(address => uint256) private _balances;

  // TODO make subscriptinoRate changes work
  // historical prices
  Common.PriceChange[] historicalPriceChanges;
  bytes32[] historicalPriceHashes;

  // price changes over the length of the set period
  Common.PriceChange[] recentPriceChanges;

  mapping(address trader => uint256 index) _traderPriceIndex;

  uint256 period = 43_200;
  uint256 periodLastOccuredAt;

  uint256 supply;
  address keySubject;
  address subPoolContract;
  address factoryContract;
  uint256 groupId;

  // 100% fee rate
  uint256 internal maxSubscriptionRate = 10000;

  constructor(
    uint256 _subscriptionRate,
    address _keySubject,
    address _subPoolContract,
    address _factoryContract
  ) {
    keySubject = _keySubject;
    subPoolContract = _subPoolContract;
    factoryContract = _factoryContract;
    groupId = KeyFactory(_factoryContract).getGroupId();

    // first period has no interest rate on buys
    Common.PriceChange memory newPriceChange = Common.PriceChange({
      price: 0,
      rate: uint128(_subscriptionRate),
      startTimestamp: uint112(block.timestamp),
      index: 0
    });

    // initialize genesis price change
    historicalPriceChanges.push(newPriceChange);
    bytes32 h = keccak256(abi.encode(newPriceChange, bytes32(0)));
    historicalPriceHashes.push(h);
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

  function getKeySubject() public view returns (address) {
    return keySubject;
  }

  function getBuyPrice(uint256 amount) public view returns (uint256) {
    return getPrice(supply, amount);
  }

  function getSellPrice(uint256 amount) public view returns (uint256) {
    return getPrice(supply - amount, amount);
  }

  function getSupply() public view returns (uint256) {
    return supply;
  }

  function balanceOf(address addr) public view returns (uint256) {
    return _balances[addr];
  }

  function getCurrentPrice() public view returns (uint256) {
    return getPrice(supply, 1);
  }

  function getTaxPrice(uint256 amount) public view returns (uint256) {
    return getPrice(supply + amount, 1);
  }

  // TODO is there a way to liquidate people before we buy to ensure the best price?
  function buyKeys(uint256 amount, Proof[] calldata proofs) public payable {
    require(amount > 0, "Cannot buy 0 keys");
    uint256 price = getPrice(supply, amount);
    require(msg.value >= price, "Inusfficient nft price");
    address trader = msg.sender;

    // fetch last subscription deposit checkpoint
    Common.SubscriptionPoolCheckpoint memory cp = SubscriptionPool(
      subPoolContract
    ).getSubscriptionPoolCheckpoint(trader, groupId);

    // collect fees
    Common.ContractInfo[] memory traderContracts = SubscriptionPool(
      subPoolContract
    ).getTraderContracts(trader, groupId);
    uint256 fees = _verifyAndCollectFees(
      traderContracts,
      trader,
      cp.lastModifiedAt,
      proofs
    );

    // confirm that the trader has enough in the deposit for subscription
    uint256 req = SubscriptionPool(subPoolContract).getPoolRequirementForBuy(
      trader,
      groupId,
      address(this),
      amount
    );
    uint256 additionalDeposit = msg.value - price;
    require(additionalDeposit + cp.deposit > fees, "Insufficient pool");
    uint256 newDeposit = additionalDeposit + cp.deposit - fees;
    require(req <= newDeposit, "Insufficient pool");

    // adjust supply
    uint256 newBal = _balances[trader] + amount;
    supply = supply + amount;
    _balances[trader] = _balances[trader] + amount;

    // update checkpoints
    SubscriptionPool(subPoolContract).updateTraderInfo(
      trader,
      groupId,
      newDeposit,
      newBal
    );
    _updatePriceOracle(price);

    // send fees to keySubject
    (bool success, ) = keySubject.call{value: fees}("");
    require(success, "Unable to send funds");
  }

  function sellKeys(uint256 amount, Proof[] calldata proofs) public {
    // TODO reconsider conditions
    require(supply > amount, "Cannot sell the last key");
    require(amount > 0, "Cannot sell 0 keys");

    uint256 price = getPrice(supply - amount, amount);
    address trader = msg.sender;
    uint256 currBalance = _balances[trader];
    require(currBalance >= amount, "Insufficient keys");

    // fetch last subscription deposit checkpoint
    Common.SubscriptionPoolCheckpoint memory cp = SubscriptionPool(
      subPoolContract
    ).getSubscriptionPoolCheckpoint(trader, groupId);

    // collect fees
    Common.ContractInfo[] memory traderContracts = SubscriptionPool(
      subPoolContract
    ).getTraderContracts(trader, groupId);
    uint256 fees = _verifyAndCollectFees(
      traderContracts,
      trader,
      cp.lastModifiedAt,
      proofs
    );

    // update checkpoints
    uint256 newBal = currBalance - amount;
    uint256 newDeposit = cp.deposit - fees;
    SubscriptionPool(subPoolContract).updateTraderInfo(
      trader,
      groupId,
      newDeposit,
      newBal
    );
    _updatePriceOracle(price);

    _balances[msg.sender] = newBal;
    supply = supply - amount;

    (bool success1, ) = msg.sender.call{value: price}("");
    (bool success2, ) = keySubject.call{value: fees}("");
    require(success1 && success2, "Unable to send funds");
  }

  function _updatePriceOracle(uint256 newPrice) internal {
    uint256 currentTime = block.timestamp;

    // Check if a full period has elapsed
    if (currentTime - periodLastOccuredAt >= period) {
      // If there's at least one price change in the recent changes
      uint256 averagePrice;
      if (recentPriceChanges.length > 0) {
        // Calculate the time-weighted average
        averagePrice = ComputeUtils.calculateTimeWeightedAveragePrice(
          recentPriceChanges,
          currentTime
        );
      } else {
        averagePrice = historicalPriceChanges[historicalPriceChanges.length - 1]
          .price;
      }

      _addHistoricalPriceChange(averagePrice, currentTime);

      // Reset the recentPriceChanges and update the period's last occurrence time
      delete recentPriceChanges;
      periodLastOccuredAt = currentTime;
    }

    // TODO check if last elem has the same timestamp and combine if so
    // add the new price to recentPriceChanges
    Common.PriceChange memory newRecentPriceChange = Common.PriceChange({
      price: newPrice,
      rate: historicalPriceChanges[historicalPriceChanges.length - 1].rate,
      startTimestamp: uint112(currentTime),
      index: uint16(recentPriceChanges.length)
    });

    recentPriceChanges.push(newRecentPriceChange);
  }

  function _addHistoricalPriceChange(
    uint256 averagePrice,
    uint256 currentTime
  ) internal {
    Common.PriceChange memory newHistoricalPriceChange = Common.PriceChange({
      price: averagePrice,
      rate: historicalPriceChanges[historicalPriceChanges.length - 1].rate,
      startTimestamp: uint112(currentTime),
      index: uint16(historicalPriceChanges.length)
    });
    historicalPriceChanges.push(newHistoricalPriceChange);

    // Hash chaining
    bytes32 previousHash = historicalPriceHashes[
      historicalPriceHashes.length - 1
    ];
    bytes32 newHash = keccak256(
      abi.encode(newHistoricalPriceChange, previousHash)
    );
    historicalPriceHashes.push(newHash);
  }

  function _verifyAndCollectFees(
    Common.ContractInfo[] memory traderContracts,
    address trader,
    uint256 lastDepositTime,
    Proof[] calldata proofs
  ) internal returns (uint256 _fees) {
    uint256 fees = 0;
    for (uint256 i = 0; i < traderContracts.length; i++) {
      Common.ContractInfo memory contractInfo = traderContracts[i];
      if (contractInfo.keyContract == address(this)) {
        continue;
      }
      uint256 feeForContract = _processContract(
        contractInfo,
        trader,
        lastDepositTime,
        proofs
      );
      fees += feeForContract;
    }

    uint256 feeForThis;
    (feeForThis) = _processContractForThis(trader, lastDepositTime, proofs);
    fees += feeForThis;

    return fees;
  }

  function _processContract(
    Common.ContractInfo memory contractInfo,
    address trader,
    uint256 lastDepositTime,
    Proof[] calldata proofs
  ) internal returns (uint256 _fee) {
    bytes32 initialHash = SubscriptionKeys(contractInfo.keyContract)
      .getStartHash(trader);

    for (uint256 j = 0; j < proofs.length; j++) {
      if (proofs[j].keyContract == contractInfo.keyContract) {
        (uint256 fee, bytes32 h) = getFeeWithFinalHash(
          lastDepositTime,
          initialHash,
          proofs[j],
          contractInfo.balance
        );
        require(
          SubscriptionKeys(contractInfo.keyContract).verifyHashExternal(
            h,
            trader
          ),
          "Invalid proof"
        );

        return fee;
      }
    }

    revert("No matching Proof found for keyContract");
  }

  function _processContractForThis(
    address trader,
    uint256 lastDepositTime,
    Proof[] calldata proofs
  ) internal returns (uint256 _fee) {
    bytes32 initialHash = getStartHash(trader);
    for (uint256 j = 0; j < proofs.length; j++) {
      if (proofs[j].keyContract == address(this)) {
        (uint256 fee, bytes32 h) = getFeeWithFinalHash(
          lastDepositTime,
          initialHash,
          proofs[j],
          balanceOf(trader)
        );
        require(verifyHash(h, trader), "Invalid proof");

        return fee;
      }
    }

    revert("No matching Proof found for address(this)");
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

  function verifyHashExternal(
    bytes32 h,
    address trader
  ) external returns (bool) {
    require(
      KeyFactory(factoryContract).isValidDeployment(msg.sender),
      "Invalid artist contract"
    );

    bool valid = historicalPriceHashes[historicalPriceHashes.length - 1] == h;
    if (valid) {
      _traderPriceIndex[trader] = historicalPriceChanges.length - 1;
      return true;
    }

    return false;
  }

  function verifyHash(bytes32 h, address trader) internal returns (bool) {
    bool valid = historicalPriceHashes[historicalPriceHashes.length - 1] == h;
    if (valid) {
      _traderPriceIndex[trader] = historicalPriceChanges.length - 1;
      return true;
    }

    return false;
  }

  function getStartHash(address trader) public view returns (bytes32) {
    uint256 lastPriceIndex = getLastTraderPriceIndex(trader);
    if (lastPriceIndex == 0) {
      return bytes32(0);
    }

    // get hash right before the traders price change. The prover will hash chain off of this
    return historicalPriceHashes[getLastTraderPriceIndex(trader) - 1];
  }

  function getLastTraderPriceIndex(
    address trader
  ) public view returns (uint256) {
    uint256 idx = _traderPriceIndex[trader];
    if (idx == 0) {
      return historicalPriceChanges.length - 1;
    }

    return idx;
  }

  function getPriceProof(address trader) external view returns (Proof memory) {
    uint256 startIndex = getLastTraderPriceIndex(trader);
    uint256 length = historicalPriceChanges.length - startIndex;
    Common.PriceChange[] memory pc = new Common.PriceChange[](length);
    for (uint256 i = 0; i < length; i++) {
      pc[i] = historicalPriceChanges[startIndex + i];
    }

    return Proof({keyContract: address(this), pcs: pc});
  }
}
