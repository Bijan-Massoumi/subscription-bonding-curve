// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SubscriptionPoolTracker.sol";


// TODO add method that liquidates all users, it should give a gas refund, it should revert if there are no users to liquidate

abstract contract SubscriptionKeys is SubscriptionPoolTracker {
  using Address for address;

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

  function getBuyPriceAfterFee(uint256 amount) public view returns (uint256) {
    uint256 price = getBuyPrice(amount);
    uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
    uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
    return price + protocolFee + subjectFee;
  }

  function getSellPriceAfterFee(uint256 amount) public view returns (uint256) {
    uint256 price = getSellPrice(amount);
    uint256 protocolFee = (price * protocolFeePercent) / 1 ether;
    uint256 subjectFee = (price * subjectFeePercent) / 1 ether;
    return price - protocolFee - subjectFee;
  }

  function getMinimumSubPool() public view returns (uint256) {
    //TODO:  implement
  }

  function getSubscriptionPoolRemaining() public view returns (uint256) {
    uint256 subPoolRemaining;
    (subPoolRemaining, ) = _getSubscriptionPoolRemaining(msg.sender, _balances[msg.sender], getPrice(supply, 1));
    return subPoolRemaining;
  }

  // TODO is there a way to liquidate people before we buy to ensure the best price?
  function buyShares(uint256 amount) public payable {
    require(
      supply > 0 || sharesSubject == msg.sender,
      "Only the shares' subject can buy the first share"
    );
    uint256 price = getPrice(supply, amount);
    uint256 subPoolMinimum = _getMinimumPool(getPrice(supply+amount,1));
    require(msg.value > price, "Inusfficient nft price");

    // is the trader paying enought to cover minimum pool requirements?
    uint256 subPoolDelta = msg.value - price;
    uint256 traderPoolRemaining;
    (traderPoolRemaining, ) = _getSubscriptionPoolRemaining(msg.sender, _balances[msg.sender], getPrice(supply, 1));
    uint256 newSubscriptionPool = (subPoolDelta + traderPoolRemaining);
    require(newSubscriptionPool > SubPoolMinimum, "Insufficient payment");

    // purchase tokens
    _balances[msg.sender] = _balances[msg.sender] + amount;
    supply = supply + amount;
    // tokens have been bought, params have changed
    _updatePriceParam(price);
    _updateCheckpoint(msg.sender, newSubscriptionPool);

    //TODO: emit new subscription Pool
    emit Trade(
      msg.sender,
      sharesSubject,
      true,
      amount,
      price,
      supply + amount
    );
  }

  function sellShares(uint256 amount) public payable {
    require(supply > amount, "Cannot sell the last share");
    uint256 price = getPrice(supply - amount, amount);
    require(
    _balances[msg.sender] >= amount,
      "Insufficient shares"
    );
    _balances[msg.sender] =
      _balances[msg.sender] -
      amount;
    supply = supply - amount;

    //TODO update their checkpoint now that we're changing their annual rate

    //TODO: emit the minimum bond requirment
    emit Trade(
      msg.sender,
      sharesSubject,
      false,
      amount,
      price,
      supply - amount
    );
  }

  // External functions ------------------------------------------------------


  function increaseSubscriptionPool(
    uint256 tokenId,
    uint256 amount
  ) external override {
    if (!_isApprovedOrOwner(msg.sender, tokenId)) revert IsNotApprovedOrOwner();

    _alterStatedPriceAndSubscriptionPool(tokenId, int256(amount), 0);
  }

  function decreaseSubscriptionPool(
    uint256 tokenId,
    uint256 amount
  ) external override {
    if (!_isApprovedOrOwner(msg.sender, tokenId)) revert IsNotApprovedOrOwner();

    _alterStatedPriceAndSubscriptionPool(tokenId, -int256(amount), 0);
  }

  function reapAndWithdrawFees(uint256[] calldata tokenIds) external {
    reapSafForTokenIds(tokenIds);
    withdrawAccumulatedFees();
  }


  function reapSafForTokenIds(uint256[] calldata tokenIds) public {
    uint256 netFees = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (!_exists(tokenIds[i])) revert TokenDoesntExist();
      netFees += _getFeesToCollectForToken(tokenIds[i]);
    }
    creatorFees += netFees;
  }

  function withdrawAccumulatedFees() public {
    subscriptionPoolToken.safeTransfer(withdrawAddress, creatorFees);
    creatorFees = 0;
  }
