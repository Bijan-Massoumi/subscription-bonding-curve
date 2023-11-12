// SPDX-License-Identifier: MITs
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ComputeUtils.sol";
import "forge-std/console.sol";

contract ComputeUtilsTest is Test {
  function testCalculateFeeForOneDay() public {
    uint256 rate = 10 * 1 ether;
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      100 ether, // totalStatedPrice
      0, // startTime
      1 days, // endTime
      10 * 1 ether // feeRate
    );
    uint256 expectedFeeNumerator = 100 ether * 1 days * rate;
    uint256 expectedFee = expectedFeeNumerator / 365 days / SCALE; // As feeRate is in thousandths
    assertEq(fee, expectedFee, "Fee does not match expected for one day");
  }

  function testCalculateFeeForHalfYear() public {
    uint256 rate = 5 * 1 ether;
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      200 ether, // totalStatedPrice
      0, // startTime
      182 days, // endTime (half year)
      rate // feeRate
    );
    uint256 expectedFeeNumerator = 200 ether * 182 days * rate;
    uint256 expectedFee = expectedFeeNumerator / 365 days / SCALE; // As feeRate is in thousandths
    assertEq(fee, expectedFee, "Fee does not match expected for half year");
  }

  function testCalculateFeeWithNoTimeElapsed() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      150 ether, // totalStatedPrice
      50, // startTime
      50, // endTime (no time elapsed)
      20
    );
    assertEq(fee, 0, "Fee should be zero when no time has elapsed");
  }

  function testCalculateFeeWithNoRate() public {
    uint256 fee = ComputeUtils._calculateFeeBetweenTimes(
      150 ether, // totalStatedPrice
      0, // startTime
      100 days, // endTime
      0 // feeRate (0%)
    );
    assertEq(fee, 0, "Fee should be zero when rate is zero");
  }
}
