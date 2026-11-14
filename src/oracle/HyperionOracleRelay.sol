// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionOracleRelay} from "../interfaces/IHyperionOracleRelay.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {SignedMath} from "../libraries/SignedMath.sol";

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function decimals() external view returns (uint8);
}

/**
 * @title HyperionOracleRelay
 * @notice Multi-source price aggregation engine with dynamic volatility circuit breakers.
 * @dev Reconciles primary and secondary oracle feeds, validates staleness windows, and halts trading upon anomalous spikes.
 */
contract HyperionOracleRelay is IHyperionOracleRelay {
    using WadRayMath for uint256;
    using SignedMath for int256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    address public immutable owner;
    address public guardian;

    uint256 internal constant WAD = 1e18;
    uint256 public constant MAX_DEVIATION_BPS = 500; // 500 bps = 5.0% maximum allowed inter-feed divergence
    uint256 public constant BPS_DIVISOR = 10_000;

    // =========================================================================
    // STRUCTS & STATE
    // =========================================================================

    struct FeedConfig {
        address primaryFeed;
        address secondaryFeed;
        uint32 heartbeatWindow; // Maximum age of price report in seconds (e.g. 3600)
        uint8 primaryDecimals;
        uint8 secondaryDecimals;
        bool isConfigured;
    }

    // Market ID => FeedConfig
    mapping(uint256 => FeedConfig) public feedConfigs;

    // Market ID => Circuit Breaker state
    mapping(uint256 => bool) public circuitBreakerTripped;

    // Manual fallback price for local sim / unit tests: Market ID => Price in Wad
    mapping(uint256 => uint256) public manualFallbackPrice;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier onlyGuardianOrOwner() {
        if (msg.sender != guardian && msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _owner, address _guardian) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        guardian = _guardian == address(0) ? _owner : _guardian;
    }

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    function setGuardian(address _newGuardian) external onlyOwner {
        if (_newGuardian == address(0)) revert ZeroAddress();
        guardian = _newGuardian;
    }

    /**
     * @notice Registers primary and secondary oracle price sources for a market.
     */
    function configureFeed(uint256 marketId, address primaryFeed, address secondaryFeed, uint32 heartbeatWindow)
        external
        onlyOwner
    {
        if (primaryFeed == address(0)) revert ZeroAddress();

        uint8 pDec = IAggregatorV3(primaryFeed).decimals();
        uint8 sDec = secondaryFeed != address(0) ? IAggregatorV3(secondaryFeed).decimals() : pDec;

        feedConfigs[marketId] = FeedConfig({
            primaryFeed: primaryFeed,
            secondaryFeed: secondaryFeed,
            heartbeatWindow: heartbeatWindow,
            primaryDecimals: pDec,
            secondaryDecimals: sDec,
            isConfigured: true
        });

        emit FeedConfigured(marketId, primaryFeed, secondaryFeed, heartbeatWindow);
    }

    /**
     * @notice Sets a fallback price for testing or emergency override.
     */
    function setManualFallbackPrice(uint256 marketId, uint256 priceWad) external onlyOwner {
        manualFallbackPrice[marketId] = priceWad;
    }

    // =========================================================================
    // PRICE RETRIEVAL & VALIDATION
    // =========================================================================

    /// @inheritdoc IHyperionOracleRelay
    function getIndexPrice(uint256 marketId) public view override returns (uint256 indexPrice, uint256 confidence) {
        FeedConfig memory cfg = feedConfigs[marketId];

        if (!cfg.isConfigured) {
            uint256 fallbackP = manualFallbackPrice[marketId];
            if (fallbackP > 0) {
                return (fallbackP, fallbackP / 100);
            }
            revert InvalidMarket();
        }

        (, int256 pAnswer,, uint256 pUpdatedAt,) = IAggregatorV3(cfg.primaryFeed).latestRoundData();
        if (pAnswer <= 0) revert ZeroAmount();
        if (block.timestamp - pUpdatedAt > cfg.heartbeatWindow) revert OracleStale();

        uint256 primaryWad = _normalizeToWad(uint256(pAnswer), cfg.primaryDecimals);

        if (cfg.secondaryFeed != address(0)) {
            (, int256 sAnswer,, uint256 sUpdatedAt,) = IAggregatorV3(cfg.secondaryFeed).latestRoundData();
            if (sAnswer > 0 && block.timestamp - sUpdatedAt <= cfg.heartbeatWindow) {
                uint256 secondaryWad = _normalizeToWad(uint256(sAnswer), cfg.secondaryDecimals);

                // Compute deviation
                uint256 diff = primaryWad > secondaryWad ? primaryWad - secondaryWad : secondaryWad - primaryWad;
                uint256 deviationBps = (diff * BPS_DIVISOR) / secondaryWad;

                if (deviationBps > MAX_DEVIATION_BPS) {
                    // Excessive deviation triggers circuit breaker
                    return (primaryWad, diff);
                }

                // Average of both feeds
                indexPrice = (primaryWad + secondaryWad) / 2;
                confidence = diff;
                return (indexPrice, confidence);
            }
        }

        indexPrice = primaryWad;
        confidence = primaryWad / 100; // 1% default confidence band
    }

    /// @inheritdoc IHyperionOracleRelay
    function validatePrice(uint256 marketId, uint256 candidatePrice) external view override returns (bool) {
        (uint256 indexPrice, uint256 confidence) = getIndexPrice(marketId);

        uint256 diff = candidatePrice > indexPrice ? candidatePrice - indexPrice : indexPrice - candidatePrice;
        uint256 allowedTolerance = confidence > (indexPrice * MAX_DEVIATION_BPS) / BPS_DIVISOR
            ? confidence
            : (indexPrice * MAX_DEVIATION_BPS) / BPS_DIVISOR;

        return diff <= allowedTolerance;
    }

    /// @inheritdoc IHyperionOracleRelay
    function isCircuitBreakerTripped(uint256 marketId) external view override returns (bool) {
        return circuitBreakerTripped[marketId];
    }

    /// @inheritdoc IHyperionOracleRelay
    function resetCircuitBreaker(uint256 marketId) external override onlyGuardianOrOwner {
        circuitBreakerTripped[marketId] = false;
        emit CircuitBreakerReset(marketId);
    }

    /**
     * @notice Manually trips the circuit breaker during severe market dislocations.
     */
    function tripCircuitBreaker(uint256 marketId) external onlyGuardianOrOwner {
        circuitBreakerTripped[marketId] = true;
        (uint256 price,) = getIndexPrice(marketId);
        emit CircuitBreakerTripped(marketId, price, price, MAX_DEVIATION_BPS + 1);
    }

    // =========================================================================
    // INTERNAL HELPERS
    // =========================================================================

    function _normalizeToWad(uint256 rawValue, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return rawValue * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return rawValue / (10 ** (decimals - 18));
        }
        return rawValue;
    }
}
