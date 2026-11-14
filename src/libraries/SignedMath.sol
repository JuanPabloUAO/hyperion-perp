// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";

/**
 * @title SignedMath
 * @notice Fixed-point 18-decimal signed math library with overflow checks and clamps.
 * @dev Supports signed Wad multiplication, division, abs, signum, and range clamping.
 */
library SignedMath {
    int256 internal constant WAD = 1e18;
    int256 internal constant RAY = 1e27;

    /**
     * @notice Returns absolute value of signed integer.
     */
    function abs(int256 a) internal pure returns (uint256) {
        unchecked {
            if (a == type(int256).min) revert IHyperionTypes.MathOverflow();
            return a >= 0 ? uint256(a) : uint256(-a);
        }
    }

    /**
     * @notice Returns signum of integer (-1, 0, or 1).
     */
    function sign(int256 a) internal pure returns (int256) {
        if (a > 0) return 1;
        if (a < 0) return -1;
        return 0;
    }

    /**
     * @notice Multiplies two signed Wad values.
     */
    function sWadMul(int256 a, int256 b) internal pure returns (int256) {
        if (a == 0 || b == 0) return 0;
        int256 c = a * b;
        if (a != 0 && c / a != b) revert IHyperionTypes.MathOverflow();
        return c / WAD;
    }

    /**
     * @notice Divides two signed Wad values.
     */
    function sWadDiv(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        int256 aScaled = a * WAD;
        if (a != 0 && aScaled / a != WAD) revert IHyperionTypes.MathOverflow();
        return aScaled / b;
    }

    /**
     * @notice Multiplies two signed Ray values.
     */
    function sRayMul(int256 a, int256 b) internal pure returns (int256) {
        if (a == 0 || b == 0) return 0;
        int256 c = a * b;
        if (a != 0 && c / a != b) revert IHyperionTypes.MathOverflow();
        return c / RAY;
    }

    /**
     * @notice Divides two signed Ray values.
     */
    function sRayDiv(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        int256 aScaled = a * RAY;
        if (a != 0 && aScaled / a != RAY) revert IHyperionTypes.MathOverflow();
        return aScaled / b;
    }

    /**
     * @notice Clamps value between lower and upper bound inclusive.
     */
    function clamp(int256 val, int256 minVal, int256 maxVal) internal pure returns (int256) {
        if (val < minVal) return minVal;
        if (val > maxVal) return maxVal;
        return val;
    }

    /**
     * @notice Returns smaller of two signed values.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @notice Returns larger of two signed values.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }
}
