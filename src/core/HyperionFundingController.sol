// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionFundingController} from "../interfaces/IHyperionFundingController.sol";
import {IHyperionVAMM} from "../interfaces/IHyperionVAMM.sol";
import {IHyperionOracleRelay} from "../interfaces/IHyperionOracleRelay.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {SignedMath} from "../libraries/SignedMath.sol";

/**
 * @title HyperionFundingController
 * @notice Dynamic Proportional-Integral-Derivative (PID) controller for continuous perpetual funding rates.
 * @dev Measures mark-to-index premium, enforces velocity limits, and maintains a 27-decimal Ray cumulative index.
 */
contract HyperionFundingController is IHyperionFundingController {
    using WadRayMath for uint256;
    using SignedMath for int256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    address public immutable owner;
    address public immutable oracleRelay;

    uint32 public constant DEFAULT_LOOKBACK = 900; // 15-minute TWAP window
    int256 internal constant RAY = 1e27;
    int256 internal constant WAD = 1e18;

    // =========================================================================
    // STATE VARIABLES
    // =========================================================================

    // Market ID => PID Configuration
    mapping(uint256 => PIDConfig) public pidConfigs;

    // Market ID => VAMM address
    mapping(uint256 => address) public vamms;

    // Market ID => Cumulative funding index (in Ray: 27 decimals)
    mapping(uint256 => int256) public cumulativeFundingRates;

    // Market ID => Instantaneous funding rate per second (in Wad: 18 decimals)
    mapping(uint256 => int256) public currentFundingRates;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _owner, address _oracleRelay) {
        if (_owner == address(0) || _oracleRelay == address(0)) revert ZeroAddress();
        owner = _owner;
        oracleRelay = _oracleRelay;
    }

    // =========================================================================
    // EXTERNAL VIEW FUNCTIONS
    // =========================================================================

    /// @inheritdoc IHyperionFundingController
    function getCumulativeFundingRate(uint256 marketId) external view override returns (int256) {
        return cumulativeFundingRates[marketId];
    }

    /// @inheritdoc IHyperionFundingController
    function getInstantaneousFundingRate(uint256 marketId) external view override returns (int256) {
        return currentFundingRates[marketId];
    }

    // =========================================================================
    // MUTATING FUNCTIONS
    // =========================================================================

    /**
     * @notice Registers a vAMM address for a market.
     */
    function registerMarketVAMM(uint256 marketId, address vamm) external onlyOwner {
        if (vamm == address(0)) revert ZeroAddress();
        vamms[marketId] = vamm;
    }

    /// @inheritdoc IHyperionFundingController
    function setPIDConfig(uint256 marketId, PIDConfig calldata config) external override onlyOwner {
        if (config.maxFundingRate <= 0) revert ZeroAmount();

        pidConfigs[marketId] = config;
        emit PIDParametersUpdated(
            marketId, config.kp, config.ki, config.kd, config.maxFundingVelocity, config.maxFundingRate
        );
    }

    /// @inheritdoc IHyperionFundingController
    function updateFundingRate(uint256 marketId) external override returns (int256 currentRate, int256 cumulativeRate) {
        address vamm = vamms[marketId];
        if (vamm == address(0)) revert InvalidMarket();

        PIDConfig storage cfg = pidConfigs[marketId];
        uint256 markPrice = IHyperionVAMM(vamm).getTWAP(DEFAULT_LOOKBACK);
        (uint256 indexPrice,) = IHyperionOracleRelay(oracleRelay).getIndexPrice(marketId);

        if (indexPrice == 0) revert ZeroAmount();

        // Calculate premium error: e(t) = (mark - index) / index (normalized Wad)
        int256 error = (int256(markPrice) - int256(indexPrice)).sWadDiv(int256(indexPrice));

        uint256 dt = cfg.lastTimestamp == 0 ? 0 : block.timestamp - cfg.lastTimestamp;
        if (dt == 0 && cfg.lastTimestamp != 0) {
            return (currentFundingRates[marketId], cumulativeFundingRates[marketId]);
        }

        // Proportional term
        int256 pTerm = cfg.kp.sWadMul(error);

        // Integral term with trapezoidal integration
        if (dt > 0) {
            int256 deltaIntegral = ((error + cfg.lastError) * int256(dt)) / 2;
            cfg.integralError += deltaIntegral;
        }
        int256 iTerm = cfg.ki.sWadMul(cfg.integralError);

        // Derivative term
        int256 dTerm = 0;
        if (dt > 0) {
            dTerm = cfg.kd.sWadMul((error - cfg.lastError).sWadDiv(int256(dt)));
        }

        int256 rawRate = pTerm + iTerm + dTerm;

        // Apply velocity limit: max change per second
        if (dt > 0 && cfg.maxFundingVelocity > 0) {
            int256 maxDelta = cfg.maxFundingVelocity * int256(dt);
            int256 lastRate = currentFundingRates[marketId];
            rawRate = rawRate.clamp(lastRate - maxDelta, lastRate + maxDelta);
        }

        // Apply absolute rate clamp
        currentRate = rawRate.clamp(-cfg.maxFundingRate, cfg.maxFundingRate);
        currentFundingRates[marketId] = currentRate;

        // Update cumulative index: cumulative += rate * dt (in Ray)
        if (dt > 0) {
            // Convert currentRate (Wad) to Ray and multiply by dt
            int256 rateRay = currentRate * 1e9;
            int256 deltaCumulative = rateRay * int256(dt);
            cumulativeFundingRates[marketId] += deltaCumulative;
        }

        cumulativeRate = cumulativeFundingRates[marketId];

        cfg.lastError = error;
        cfg.lastTimestamp = block.timestamp;

        emit FundingRateUpdated(marketId, currentRate, cumulativeRate, block.timestamp);
    }
}
