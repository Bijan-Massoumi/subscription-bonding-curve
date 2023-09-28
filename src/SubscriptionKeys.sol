// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionPool.sol";

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
abstract contract SubscriptionKeys is SubscriptionPool {
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

  uint256 supply;
  uint256 creatorFees;
  address withdrawAddress;
  address sharesSubject;
  address subPoolContract;

  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address _sharesSubject,
    address _subPoolContract
  ) SubscriptionPool(_subscriptionRate) {
    withdrawAddress = _withdrawAddress;
    sharesSubject = _sharesSubject;
    subPoolContract = _subPoolContract;
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
    return sharesSubject;
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

  function getMinimumSubPool() public view returns (uint256) {
    //TODO:  implement
  }

  function balanceOf(address addr) public view returns (uint256) {
    return _balances[addr];
  }

  function getSubscriptionPoolRemaining(
    address addr
  ) public view returns (uint256) {
    uint256 subPoolRemaining;
    (subPoolRemaining, ) = _getSubscriptionPoolRemaining(
      addr,
      _balances[addr],
      getPrice(supply, 1)
    );
    return subPoolRemaining;
  }

  function getCurrentPrice() public view returns (uint256) {
    return getPrice(supply, 1);
  }

  function getTaxPrice(uint256 amount) public view returns (uint256) {
    return getPrice(supply + amount, 1);
  }

  // TODO is there a way to liquidate people before we buy to ensure the best price?
  function buyShares(uint256 amount) public payable {
    require(amount > 0, "Cannot buy 0 shares");

    uint256 price = getPrice(supply, amount);
    require(msg.value >= price, "Inusfficient nft price");

    // is the trader paying enought to cover minimum pool requirements?
    // if so update their checkpoints
    uint256 subPoolMinimum = SubscriptionPool(subPoolContract)
      .getPoolRequirementForBuy(msg.sender, address(this), amount);
    uint256 totalDeposit = msg.value - price;
    (uint256 traderPoolRemaining, uint256 fees) = SubscriptionPool(
      subPoolContract
    ).getSubscriptionPoolRemaining(msg.sender);
    uint256 newSubscriptionPool = (totalDeposit + traderPoolRemaining);
    require(newSubscriptionPool >= subPoolMinimum, "Insufficient payment");
    SubscriptionPool(subPoolContract).updatePoolCheckpoints(
      msg.sender,
      newSubscriptionPool,
      price
    );

    // conduct ammoratized maintance on the subscription pool
    SubscriptionPool(subPoolContract).updateLRUCheckpoint(price);

    // reap fees for creator
    creatorFees += fees;

    // purchase tokens -------
    _balances[msg.sender] = _balances[msg.sender] + amount;
    supply = supply + amount;

    //TODO: emit new subscription Pool
    emit Trade(msg.sender, sharesSubject, true, amount, price, supply + amount);
  }

  function sellShares(uint256 amount) public payable {
    require(supply > amount, "Cannot sell the last share");
    require(amount > 0, "Cannot sell 0 shares");
    uint256 price = getPrice(supply - amount, amount);
    require(_balances[msg.sender] >= amount, "Insufficient shares");

    uint256 currentPrice = getCurrentPrice();
    uint256 traderPoolRemaining;
    uint256 fees;
    (traderPoolRemaining, fees) = _getSubscriptionPoolRemaining(
      msg.sender,
      _balances[msg.sender],
      currentPrice
    );
    _updateCheckpoints(msg.sender, currentPrice, traderPoolRemaining);

    _balances[msg.sender] = _balances[msg.sender] - amount;
    supply = supply - amount;
    // reap fees for creator
    creatorFees += fees;

    //TODO: emit the minimum bond requirment
    emit Trade(
      msg.sender,
      sharesSubject,
      false,
      amount,
      price,
      supply - amount
    );

    (bool success1, ) = msg.sender.call{value: price}("");
    require(success1, "Unable to send funds");
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
