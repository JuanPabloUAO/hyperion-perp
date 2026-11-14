// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IHyperionTypes
 * @notice Global types, enums, structs, and custom errors for the HyperionPerp exchange suite.
 * @dev Common data structures shared across core, periphery, oracle, and risk modules.
 */
interface IHyperionTypes {
    // =========================================================================
    // ENUMS
    // =========================================================================

    /// @notice Side of a perpetual futures position or order
    enum Side {
        LONG,
        SHORT
    }

    /// @notice Margin account operating mode
    enum MarginMode {
        CROSS,
        ISOLATED
    }

    /// @notice Liquidation urgency tier
    enum LiquidationTier {
        NONE,
        TIER1_SOFT,
        TIER2_DUTCH_AUCTION,
        TIER3_INSURANCE_TAKEOVER
    }

    /// @notice Execution order type
    enum OrderType {
        MARKET,
        LIMIT,
        STOP_LOSS,
        TAKE_PROFIT
    }

    // =========================================================================
    // STRUCTS
    // =========================================================================

    /// @notice Represents an open perpetual position for a trader
    struct Position {
        uint256 marketId;
        address account;
        Side side;
        uint256 size; // Position size in base asset units (Wad: 18 decimals)
        uint256 openNotional; // Cumulative notional value paid at entry (Wad: 18 decimals)
        uint256 entryPrice; // Average entry price (Wad: 18 decimals)
        int256 lastCumulativeFunding; // Cumulative funding index at last settlement (Ray: 27 decimals)
        uint256 marginAllocated; // Explicit collateral allocated (for isolated margin, Wad)
        uint256 lastUpdatedTimestamp; // Block timestamp of last modification
        MarginMode marginMode; // Cross or Isolated margin
    }

    /// @notice Market-specific parameter configuration
    struct MarketConfig {
        uint256 marketId;
        string symbol;
        address vamm; // Address of virtual AMM for this market
        uint256 maxLeverage; // Maximum leverage (Wad, e.g. 50e18 for 50x)
        uint256 initialMarginRatio; // IMR in Wad (e.g. 0.05e18 = 5% for 20x max, 0.02e18 for 50x)
        uint256 maintenanceMarginRatio; // MMR in Wad (e.g. 0.02e18 = 2%)
        uint256 liquidationPenalty; // Fee penalty paid on liquidation (Wad, e.g. 0.03e18 = 3%)
        uint256 takerFeeRate; // Protocol taker fee (Wad, e.g. 0.0006e18 = 6 bps)
        uint256 makerFeeRate; // Protocol maker rebate/fee (Wad, e.g. 0.0002e18 = 2 bps)
        uint256 maxOpenInterest; // Max open interest cap per side (Wad base units)
        uint256 liquidationFeeSplit; // Fraction of penalty directed to insurance fund (Wad, e.g. 0.6e18)
        bool isActive; // Whether trading is active on this market
    }

    /// @notice Collateral asset configuration
    struct CollateralConfig {
        address token; // ERC-20 token address
        uint8 decimals; // Token decimals
        uint256 haircut; // Valuation discount factor in Wad (e.g. 0.90e18 = 90% credit)
        uint256 depositCap; // Maximum allowed total deposits (token units)
        bool isAllowed; // Whether token can be deposited
    }

    /// @notice Ongoing Dutch auction liquidation record
    struct DutchAuction {
        uint256 auctionId;
        uint256 marketId;
        address trader;
        Side side;
        uint256 sizeToLiquidate; // Base units to liquidate
        uint256 bankruptPrice; // Price at which equity is exactly 0
        uint256 startPrice; // Initial auction trigger price (Wad)
        uint256 endPrice; // Floor auction execution price (Wad)
        uint256 startTime; // Auction start block timestamp
        uint256 duration; // Total auction duration in seconds
        uint256 filledSize; // Base units already filled by keepers
        bool isSettled; // True if auction concluded or cancelled
    }

    /// @notice PID controller parameters and dynamic state
    struct PIDConfig {
        int256 kp; // Proportional gain (Wad)
        int256 ki; // Integral gain (Wad)
        int256 kd; // Derivative gain (Wad)
        int256 maxFundingVelocity; // Max change in funding rate per hour (Wad)
        int256 maxFundingRate; // Absolute ceiling on funding rate (Wad, e.g. 0.01e18 = 1% / 8h)
        int256 integralError; // Accumulated integral state (Wad)
        int256 lastError; // Error at last evaluation (Wad)
        uint256 lastTimestamp; // Timestamp of last controller tick
    }

    /// @notice Price observation snapshot for TWAP calculation
    struct Observation {
        uint32 timestamp;
        uint256 cumulativePrice; // Cumulative price for arithmetic TWAP
        uint256 cumulativeLogPrice; // Cumulative log price for geometric TWAP
    }

    // =========================================================================
    // CUSTOM ERRORS
    // =========================================================================

    error ZeroAddress();
    error ZeroAmount();
    error InvalidMarket();
    error MarketNotActive();
    error MarketAlreadyExists();
    error InvalidLeverage();
    error ExceedsMaxLeverage();
    error ExceedsMaxOpenInterest();
    error InsufficientFreeMargin();
    error InsufficientCollateral();
    error AccountUnderwater();
    error AccountHealthy();
    error PositionNotFound();
    error PositionSizeZero();
    error SlippageExceeded();
    error OracleStale();
    error OracleDeviationExceeded();
    error AuctionAlreadySettled();
    error AuctionExpired();
    error AuctionNotExpired();
    error UnauthorizedCaller();
    error ReentrancyGuardTriggered();
    error FlashLoanActive();
    error MathOverflow();
    error MathUnderflow();
    error DivisionByZero();
    error ArrayLengthMismatch();
    error EmergencyPaused();
}
