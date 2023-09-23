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

    function _getTimeLiquidationBegan(
        uint256 totalStatedPrice,
        uint256 lastCheckInAt,
        uint256 feeRate,
        uint256 subscriptionPoolRemaining
    ) internal pure returns (uint256 liquidationStartedAt) {
        liquidationStartedAt =
            (subscriptionPoolRemaining * (secondsInYear * 10000)) /
            (feeRate * totalStatedPrice) +
            lastCheckInAt;
    }

    function getLiquidationPrice(
        uint256 value,
        uint256 t,
        uint256 halfLife
    ) internal pure returns (uint256 price) {
        price = value >> (t / halfLife);
        t %= halfLife;
        price -= (price * t) / halfLife / 2;
    }
}
