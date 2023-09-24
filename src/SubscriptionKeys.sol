// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionPoolTracker.sol";

// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate
abstract contract SubscriptionKeys is SubscriptionPoolTracker {
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

  constructor(
    address _withdrawAddress,
    uint256 _subscriptionRate,
    address _sharesSubject
  ) SubscriptionPoolTracker(_subscriptionRate) {
    withdrawAddress = _withdrawAddress;
    sharesSubject = _sharesSubject;
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

  function getSubscriptionPoolRemaining(address addr) public view returns (uint256) {
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

  // TODO is there a way to liquidate people before we buy to ensure the best price?
  function buyShares(uint256 amount) public payable {
    require(
      supply > 0 || sharesSubject == msg.sender,
      "Only the shares' subject can buy the first share"
    );
    require(amount > 0, "Cannot buy 0 shares");
    uint256 price = getPrice(supply, amount);
    uint256 subPoolMinimum = _getMinimumPool(getPrice(supply + amount, 1));
    require(msg.value >= price, "Inusfficient nft price");

    // is the trader paying enought to cover minimum pool requirements?
    uint256 subPoolDelta = msg.value - price;
    uint256 traderPoolRemaining;
    uint256 fees;
    (traderPoolRemaining, fees) = _getSubscriptionPoolRemaining(
      msg.sender,
      _balances[msg.sender],
      getCurrentPrice()
    );
    uint256 newSubscriptionPool = (subPoolDelta + traderPoolRemaining);
    require(newSubscriptionPool > subPoolMinimum, "Insufficient payment");

    // reap fees for creator
    creatorFees += fees;

    // purchase tokens -------
    // save a timestamp of the currentParams for retroactive fee calculation
    _updatePriceParam(getCurrentPrice());
    _balances[msg.sender] = _balances[msg.sender] + amount;
    supply = supply + amount;
    // tokens have been bought, params have changed
    _updateCheckpoint(msg.sender, newSubscriptionPool);

    //TODO: emit new subscription Pool
    emit Trade(msg.sender, sharesSubject, true, amount, price, supply + amount);
  }

  function sellShares(uint256 amount) public payable {
    require(supply > amount, "Cannot sell the last share");
    require(amount > 0, "Cannot sell 0 shares");
    uint256 price = getPrice(supply - amount, amount);
    require(_balances[msg.sender] >= amount, "Insufficient shares");

    uint256 traderPoolRemaining;
    uint256 fees;
    (traderPoolRemaining, fees) = _getSubscriptionPoolRemaining(
      msg.sender,
      _balances[msg.sender],
      getCurrentPrice()
    );
    _balances[msg.sender] = _balances[msg.sender] - amount;
    supply = supply - amount;
    _updateCheckpoint(msg.sender, traderPoolRemaining);
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
  function increaseSubscriptionPool(
    uint256 tokenId,
    uint256 amount
  ) external {
    // TODO
  }

  function decreaseSubscriptionPool(
    uint256 tokenId,
    uint256 amount
  ) external {
    // TODO
  }

  function withdrawAccumulatedFees() public {
    uint256 pool = getSubscriptionPoolRemaining(msg.sender);
    require(pool > 0, "Insufficient pool"); 
    (bool success,) = msg.sender.call{value: pool}("");
    require(success, "Unable to send funds");
    _updateCheckpoint(msg.sender, 0);
    creatorFees = 0;
  }
}
