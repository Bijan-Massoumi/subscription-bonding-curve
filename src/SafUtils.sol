// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library SafUtils {
    uint256 constant secondsInYear = 365 days;

    function _calculateSafBetweenTimes(
        uint256 totalStatedPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 feeRate
    ) internal pure returns (uint256 feeToReap) {
        feeToReap =
            (feeRate * totalStatedPrice * (endTime - startTime)) /
            (secondsInYear * 10000);
    }
}
