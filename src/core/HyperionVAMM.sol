// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionVAMM} from "../interfaces/IHyperionVAMM.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {LogExpMath} from "../libraries/LogExpMath.sol";
import {TransientStorage} from "../libraries/TransientStorage.sol";

/**
 * @title HyperionVAMM
 * @notice Concentrated Virtual Automated Market Maker executing perpetual swaps against virtual reserves.
 * @dev Enforces x * y = k invariant, calculates price impact, records TWAP observations, and supports dynamic liquidity.
 */
contract HyperionVAMM is IHyperionVAMM {
    using WadRayMath for uint256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    uint256 public immutable override marketId;
    address public immutable clearingHouse;
    address public immutable owner;
    address public liquidator;

    uint16 public constant OBSERVATION_CARDINALITY = 128;
    uint256 public constant MIN_VIRTUAL_RESERVE = 1e12; // 0.000001 Wad minimum reserve

    // =========================================================================
    // STATE VARIABLES
    // =========================================================================

    uint256 public virtualBase; // Virtual base asset reserve x (Wad)
    uint256 public virtualQuote; // Virtual quote asset reserve y (Wad)

    uint256 public takerFeeRate; // Taker fee rate in Wad (e.g. 0.0006e18 = 6 bps)
    uint256 public makerFeeRate; // Maker fee rate in Wad (e.g. 0.0002e18 = 2 bps)

    // Circular observation buffer for TWAP
    Observation[OBSERVATION_CARDINALITY] public observations;
    uint16 public observationIndex;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyClearingHouseOrLiquidator() {
        if (msg.sender != clearingHouse && msg.sender != liquidator) revert UnauthorizedCaller();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier nonReentrant() {
        TransientStorage.lock();
        _;
        TransientStorage.unlock();
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(
        uint256 _marketId,
        address _clearingHouse,
        address _owner,
        uint256 _initialBase,
        uint256 _initialQuote,
        uint256 _takerFee,
        uint256 _makerFee
    ) {
        if (_clearingHouse == address(0) || _owner == address(0)) revert ZeroAddress();
        if (_initialBase < MIN_VIRTUAL_RESERVE || _initialQuote < MIN_VIRTUAL_RESERVE) revert ZeroAmount();

        marketId = _marketId;
        clearingHouse = _clearingHouse;
        owner = _owner;

        virtualBase = _initialBase;
        virtualQuote = _initialQuote;
        takerFeeRate = _takerFee;
        makerFeeRate = _makerFee;

        // Initialize first observation
        observations[0] = Observation({timestamp: uint32(block.timestamp), cumulativePrice: 0, cumulativeLogPrice: 0});
    }

    // =========================================================================
    // EXTERNAL VIEW FUNCTIONS
    // =========================================================================

    /// @inheritdoc IHyperionVAMM
    function getSpotPrice() public view override returns (uint256) {
        return virtualQuote.wadDiv(virtualBase);
    }

    /// @inheritdoc IHyperionVAMM
    function getReserves() external view override returns (uint256, uint256) {
        return (virtualBase, virtualQuote);
    }

    /// @inheritdoc IHyperionVAMM
    function quoteSwap(
        Side side,
        uint256 baseAmount,
        bool /*isExactInput*/
    )
        public
        view
        override
        returns (uint256 quoteAmount, uint256 finalBaseAmount, uint256 priceAfter)
    {
        if (baseAmount == 0) revert ZeroAmount();

        uint256 x = virtualBase;
        uint256 y = virtualQuote;

        if (side == Side.LONG) {
            // Buyer takes base out, adds quote in: x decreases by baseAmount, y increases
            if (baseAmount >= x) revert SlippageExceeded();
            uint256 newX = x - baseAmount;
            // Constant product: x * y = newX * newY => newY = (x * y) / newX
            uint256 newY = (x * y) / newX;
            quoteAmount = newY - y;
            finalBaseAmount = baseAmount;
            priceAfter = newY.wadDiv(newX);
        } else {
            // Seller adds base in, takes quote out: x increases by baseAmount, y decreases
            uint256 newX = x + baseAmount;
            uint256 newY = (x * y) / newX;
            if (newY >= y) revert SlippageExceeded();
            quoteAmount = y - newY;
            finalBaseAmount = baseAmount;
            priceAfter = newY.wadDiv(newX);
        }
    }

    /// @inheritdoc IHyperionVAMM
    function getTWAP(uint32 lookbackWindow) external view override returns (uint256 twapPrice) {
        if (lookbackWindow == 0) return getSpotPrice();

        Observation memory latest = observations[observationIndex];
        uint32 currentTimestamp = uint32(block.timestamp);

        if (currentTimestamp <= latest.timestamp) {
            return getSpotPrice();
        }

        uint32 targetTimestamp = currentTimestamp - lookbackWindow;

        // Binary search for observation older than or at targetTimestamp
        uint16 i = observationIndex;
        Observation memory targetObs = observations[0];

        for (uint16 step = 0; step < OBSERVATION_CARDINALITY; step++) {
            uint16 idx = (i + OBSERVATION_CARDINALITY - step) % OBSERVATION_CARDINALITY;
            Observation memory obs = observations[idx];
            if (obs.timestamp != 0 && obs.timestamp <= targetTimestamp) {
                targetObs = obs;
                break;
            }
        }

        uint32 timeDelta = currentTimestamp - targetObs.timestamp;
        if (timeDelta == 0) return getSpotPrice();

        // Calculate latest cumulative price
        uint256 priceNow = getSpotPrice();
        uint256 currentCumulative = latest.cumulativePrice + priceNow * (currentTimestamp - latest.timestamp);

        twapPrice = (currentCumulative - targetObs.cumulativePrice) / timeDelta;
    }

    // =========================================================================
    // MUTATING FUNCTIONS
    // =========================================================================

    function setLiquidator(address _liquidator) external onlyOwner {
        liquidator = _liquidator;
    }

    /// @inheritdoc IHyperionVAMM
    function executeSwap(Side side, uint256 baseAmount)
        external
        override
        onlyClearingHouseOrLiquidator
        nonReentrant
        returns (uint256 quoteTransferred, uint256 executionPrice)
    {
        if (baseAmount == 0) revert ZeroAmount();

        uint256 x = virtualBase;
        uint256 y = virtualQuote;

        if (side == Side.LONG) {
            if (baseAmount >= x) revert SlippageExceeded();
            uint256 newX = x - baseAmount;
            uint256 newY = (x * y) / newX;
            quoteTransferred = newY - y;

            virtualBase = newX;
            virtualQuote = newY;
        } else {
            uint256 newX = x + baseAmount;
            uint256 newY = (x * y) / newX;
            if (newY >= y) revert SlippageExceeded();
            quoteTransferred = y - newY;

            virtualBase = newX;
            virtualQuote = newY;
        }

        executionPrice = quoteTransferred.wadDiv(baseAmount);
        _recordObservation(getSpotPrice());

        emit VirtualSwap(msg.sender, side, baseAmount, quoteTransferred, getSpotPrice());
    }

    /// @inheritdoc IHyperionVAMM
    function setVirtualReserves(uint256 newBaseReserve, uint256 newQuoteReserve) external override onlyOwner {
        if (newBaseReserve < MIN_VIRTUAL_RESERVE || newQuoteReserve < MIN_VIRTUAL_RESERVE) revert ZeroAmount();

        emit VirtualLiquidityUpdated(virtualBase, virtualQuote, newBaseReserve, newQuoteReserve);

        virtualBase = newBaseReserve;
        virtualQuote = newQuoteReserve;
        _recordObservation(getSpotPrice());
    }

    /**
     * @notice Updates trading fee tiers.
     */
    function setFeeTiers(uint256 newTakerFee, uint256 newMakerFee) external onlyOwner {
        takerFeeRate = newTakerFee;
        makerFeeRate = newMakerFee;
        emit FeeTiersUpdated(newTakerFee, newMakerFee);
    }

    // =========================================================================
    // INTERNAL HELPERS
    // =========================================================================

    function _recordObservation(uint256 spotPrice) internal {
        Observation memory last = observations[observationIndex];
        uint32 now32 = uint32(block.timestamp);

        if (now32 > last.timestamp) {
            uint32 dt = now32 - last.timestamp;
            uint256 newCumulative = last.cumulativePrice + spotPrice * dt;

            uint16 nextIndex = (observationIndex + 1) % OBSERVATION_CARDINALITY;
            observations[nextIndex] =
                Observation({timestamp: now32, cumulativePrice: newCumulative, cumulativeLogPrice: 0});
            observationIndex = nextIndex;
        }
    }
}
