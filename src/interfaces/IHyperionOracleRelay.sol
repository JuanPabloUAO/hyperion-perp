// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionOracleRelay
 * @notice Interface for the multi-source oracle aggregator and dynamic volatility circuit breaker.
 * @dev Combines primary and secondary price feeds, checks staleness, and halts on excessive deviation.
 */
interface IHyperionOracleRelay is IHyperionTypes {
    event PriceReported(uint256 indexed marketId, uint256 price, uint256 confidence, uint256 timestamp);
    event CircuitBreakerTripped(
        uint256 indexed marketId, uint256 reportedPrice, uint256 benchmarkPrice, uint256 deviationBps
    );
    event CircuitBreakerReset(uint256 indexed marketId);
    event FeedConfigured(uint256 indexed marketId, address primaryFeed, address secondaryFeed, uint32 heartbeatWindow);

    /**
     * @notice Retrieves verified benchmark index price for a market.
     * @param marketId Market identifier
     * @return indexPrice Wad representation of current fair index price (18 decimals)
     * @return confidence Confidence interval width (Wad)
     */
    function getIndexPrice(uint256 marketId) external view returns (uint256 indexPrice, uint256 confidence);

    /**
     * @notice Validates that price deviation between primary oracle and secondary TWAP is within tolerance.
     * @param marketId Market identifier
     * @param candidatePrice Price being validated
     * @return isValid True if candidate price is within acceptable deviation bounds
     */
    function validatePrice(uint256 marketId, uint256 candidatePrice) external view returns (bool isValid);

    /**
     * @notice Checks whether the volatility circuit breaker is active for a market.
     * @param marketId Market identifier
     * @return isTripped True if trading is halted due to price dislocation
     */
    function isCircuitBreakerTripped(uint256 marketId) external view returns (bool isTripped);

    /**
     * @notice Allows authorized guardian or risk engine to manually reset a tripped circuit breaker.
     * @param marketId Market identifier
     */
    function resetCircuitBreaker(uint256 marketId) external;
}
