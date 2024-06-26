// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Custom errors for SneakyAuction
interface ISubscriptionKeysErrors {
  /// @notice Thrown if missing proof for subject your trying to buy
  error SubjectProofMissing(address subject);
  /// @notice Thrown if subscriptionPool isnt enough to cover miminum subscriptionPool
  error InvalidProof(
    address subject,
    bytes32 expectedProof,
    bytes32 actualProof
  );
  error InvalidProofsOrder();
  error InvalidProofsLength();
  error ProtocolFeeTransferFailed();
  error CannotLiquidate();
}
