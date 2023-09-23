// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title Custom errors for SneakyAuction
interface ISubscriptionPoolTrackerErrors {
    /// @notice Thrown if invalid price values
    error InvalidAlterPriceValue();
    /// @notice Thrown if invalid subscriptionPool values
    error InvalidAlterSubscriptionPoolValue();
    /// @notice Thrown if subscriptionPool isnt enough to cover miminum subscriptionPool
    error InsufficientSubscriptionPool();
    error InvalidAssessmentFee();
}
