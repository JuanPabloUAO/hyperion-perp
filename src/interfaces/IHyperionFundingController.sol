// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionFundingController
 * @notice Interface for the continuous Proportional-Integral-Derivative (PID) funding rate engine.
 * @dev Computes continuous funding premium, updates cumulative indexes, and enforces velocity limits.
 */
interface IHyperionFundingController is IHyperionTypes {
    event FundingRateUpdated(
        uint256 indexed marketId, int256 fundingRate, int256 cumulativeFundingRate, uint256 timestamp
    );

    event PIDParametersUpdated(
        uint256 indexed marketId, int256 kp, int256 ki, int256 kd, int256 maxFundingVelocity, int256 maxFundingRate
    );

    /**
     * @notice Recalculates and updates the funding rate for a specific market using the PID controller.
     * @param marketId Market identifier
     * @return currentRate New per-second funding rate (Wad)
     * @return cumulativeRate Updated cumulative funding rate index (Ray: 27 decimals)
     */
    function updateFundingRate(uint256 marketId) external returns (int256 currentRate, int256 cumulativeRate);

    /**
     * @notice Returns the latest cumulative funding rate index for a market.
     * @param marketId Market identifier
     * @return cumulativeFunding Current cumulative index (Ray: 27 decimals)
     */
    function getCumulativeFundingRate(uint256 marketId) external view returns (int256 cumulativeFunding);

    /**
     * @notice Returns the current instantaneous annualized/8h funding rate for a market.
     * @param marketId Market identifier
     * @return rate Instantaneous funding rate in Wad
     */
    function getInstantaneousFundingRate(uint256 marketId) external view returns (int256 rate);

    /**
     * @notice Configures PID gain coefficients for a market.
     * @param marketId Market identifier
     * @param config PID controller parameter configuration
     */
    function setPIDConfig(uint256 marketId, PIDConfig calldata config) external;
}
