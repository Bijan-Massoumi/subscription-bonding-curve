// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionPool.sol";
import "./SafUtils.sol";
import "./Common.sol";

struct PriceChange {
  uint256 price;
  uint128 rate;
  uint112 startTimestamp;
  uint16 index;
}

struct Proof {
  address keyContract;
  PriceChange[] pcs;
}

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
abstract contract SubscriptionKeys {
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
  PriceChange[] historicalPriceChanges;
  uint256[] historicalPriceHashes;

  // price changes over the length of the set period
  PriceChange[] recentPriceChanges;

  mapping(address trader => uint256 index) private _traderPriceIndex;

  uint256 period;
  uint256 periodLastOccuredAt;

  uint256 supply;
  uint256 creatorFees;
  address withdrawAddress;
  address keySubject;
  address subPoolContract;

  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address _keySubject,
    address _subPoolContract
  ) {
    withdrawAddress = _withdrawAddress;
    keySubject = _keySubject;
    subPoolContract = _subPoolContract;

    // first period has no interest rate on buys
    PriceChange memory newPriceChange = PriceChange({
      price: 0,
      rate: _subscriptionRate,
      startTimestamp: uint112(block.timestamp),
      index: 0
    });

    // initialize genesis price change
    historicalPriceChanges.push(newPriceChange);
    bytes32 h = keccak256(abi.encode(newPriceChange));
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

  function getShareSubject() public view returns (address) {
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
  function buyShares(uint256 amount, Proof[] calldata proofs) public payable {
    require(amount > 0, "Cannot buy 0 shares");
    uint256 price = getPrice(supply, amount);
    require(msg.value >= price, "Inusfficient nft price");
    address trader = msg.sender;

    // fetch last subscription deposit checkpoint
    Common.SubscriptionPoolCheckpoint memory cp = SubscriptionPool(
      subPoolContract
    ).getSubscriptionPoolCheckpoint(trader);

    // collect fees
    address[] traderContracts = SubscriptionPool(subPoolContract)
      .getTraderContracts(trader);
    uint256 fees = _verifyAndCollectFees(
      traderContracts,
      trader,
      cp.lastModifiedAt
    );

    // confirm that the trader has enough in the deposit for subscription
    uint256 req = getPoolRequirementForBuy(trader, address(this), amount);
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
      newDeposit,
      newBal
    );
    _updatePriceOracle(price);
  }

  // TODO
  function sellShares(uint256 amount) public payable {
    // require(supply > amount, "Cannot sell the last share");
    // require(amount > 0, "Cannot sell 0 shares");
    // uint256 price = getPrice(supply - amount, amount);
    // require(_balances[msg.sender] >= amount, "Insufficient shares");
    // _balances[msg.sender] = _balances[msg.sender] - amount;
    // supply = supply - amount;
    // creatorFees += fees;
    // (bool success1, ) = msg.sender.call{value: price}("");
    // require(success1, "Unable to send funds");
  }

  function _updatePriceOracle(uint256 newPrice) internal {
    uint256 currentTime = block.timestamp;

    // Check if a full period has elapsed
    if (currentTime - periodLastOccuredAt >= period) {
      uint256 totalWeightedPrice = 0;
      uint256 totalDuration = 0;

      // If there's at least one price change in the recent changes
      if (recentPriceChanges.length > 0) {
        // Calculate the time-weighted average
        for (uint256 i = 0; i < recentPriceChanges.length; i++) {
          uint256 duration = (i == recentPriceChanges.length - 1)
            ? currentTime - recentPriceChanges[i].startTimestamp
            : recentPriceChanges[i + 1].startTimestamp -
              recentPriceChanges[i].startTimestamp;

          totalWeightedPrice += duration * recentPriceChanges[i].price;
          totalDuration += duration;
        }
      }
      uint256 averagePrice = (totalDuration == 0)
        ? newPrice
        : totalWeightedPrice / totalDuration;

      PriceChange memory newHistoricalPriceChange = PriceChange({
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

      // Reset the recentPriceChanges and update the period's last occurrence time
      delete recentPriceChanges;
      periodLastOccuredAt = currentTime;
    } else {
      // If not a full period, simply add the new price to recentPriceChanges
      PriceChange memory newRecentPriceChange = PriceChange({
        price: newPrice,
        rate: historicalPriceChanges[historicalPriceChanges.length - 1].rate,
        startTimestamp: uint112(currentTime),
        index: uint16(recentPriceChanges.length)
      });

      recentPriceChanges.push(newRecentPriceChange);
    }
  }

  function _verifyAndCollectFees(
    address[] memory traderContracts,
    address trader,
    uint256 lastDepositTime
  ) internal view {
    uint256 fee;
    fee += getFeeOwed(trader, lastDepositTime);
    _traderPriceIndex[trader] = historicalPriceChanges.length - 1;
    for (uint256 i = 0; i < traderContracts.length; i++) {
      address keyContract = traderContracts[i];
      fee += SubscriptionKey(keyContract).getFeeOwedForKeyContract(
        traderContracts[i]
      );
    }
  }

  // ------------ fee calculation methods ----------------

  function getFeeOwed(
    address trader,
    uint256 lastCheckpointAt
  ) internal returns (uint256) {
    uint256 balance = balanceOf(trader);

    uint256 endIndex = historicalPriceChanges.length - 1;
    uint256 startIndex = _traderPriceIndex[trader];
    require(startIndex <= endIndex, "Invalid index");

    uint256 lastTimestamp;
    uint256 lastPrice;
    uint256 lastRate;
    uint256 totalFee = 0;
    for (uint256 i = startIndex; i < endIndex; i++) {
      nextTimestamp = historicalPriceChanges[i + 1].startTimestamp;
      if (lastCheckpoint > nextTimestamp) {
        continue;
      }

      lastTimestamp = historicalPriceChanges[i].startTimestamp;
      lastPrice = historicalPriceChanges[i].price;
      lastRate = historicalPriceChanges[i].rate;

      uint256 startInterestAt = lastCheckpointAt > lastTimestamp &&
        lastCheckpointAt <= nextTimestamp
        ? lastCheckpointAt
        : lastTimestamp;
      totalFee += SafUtils._calculateFeeBetweenTimes(
        balance * lastPrice,
        lastRate,
        startInterestAt,
        nextTimestamp
      );
    }

    lastTimestamp = historicalPriceChanges[endIndex].startTimestamp;
    uint256 startInterestAt = lastCheckpointAt > lastTimestamp
      ? lastCheckpointAt
      : lastTimestamp;
    totalFee += SafUtils._calculateFeeBetweenTimes(
      balance * lastPrice,
      lastRate,
      startInterestAt,
      block.timestamp
    );

    return totalFee;
  }

  function getFeeOwedForKeyContract(address trader) external returns (uint256) {
    require(
      KeyFactory(factoryContract).isValidDeployment(msg.sender),
      "Invalid artist contract"
    );

    uint256 fee = getFeeOwed(trader);
    _traderPriceIndex[trader] = historicalPriceChanges.length - 1;
    return fee;
  }

  // External functions ------------------------------------------------------
  function increaseSubscriptionPool(uint256 tokenId, uint256 amount) external {
    // TODO
  }

  function decreaseSubscriptionPool(uint256 tokenId, uint256 amount) external {
    // TODO
  }

  function withdrawDeposit() public {
    uint256 pool = getSubscriptionPoolRemaining(msg.sender);
    require(pool > 0, "Insufficient pool");
    (bool success, ) = msg.sender.call{value: pool}("");
    require(success, "Unable to send funds");
    _updateTraderPool(msg.sender, 0);
    creatorFees = 0;
  }
}
