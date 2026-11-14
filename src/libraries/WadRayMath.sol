// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";

/**
 * @title WadRayMath
 * @notice Fixed-point 18-decimal (Wad) and 27-decimal (Ray) mathematical library with explicit rounding.
 * @dev Implements overflow-safe fixed-point multiplication, division, exponentiation, and Babylonian square root.
 */
library WadRayMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant HALF_WAD = 0.5e18;

    uint256 internal constant RAY = 1e27;
    uint256 internal constant HALF_RAY = 0.5e27;

    uint256 internal constant WAD_RAY_RATIO = 1e9;

    /**
     * @notice Multiplies two Wad values, rounding down to nearest integer.
     * @param a Left operand (Wad)
     * @param b Right operand (Wad)
     * @return c Result of (a * b) / WAD
     */
    function wadMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        unchecked {
            if (a > type(uint256).max / b) revert IHyperionTypes.MathOverflow();
            c = (a * b) / WAD;
        }
    }

    /**
     * @notice Multiplies two Wad values, rounding half up.
     * @param a Left operand (Wad)
     * @param b Right operand (Wad)
     * @return c Result of (a * b + HALF_WAD) / WAD
     */
    function wadMulHalfUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        unchecked {
            if (a > (type(uint256).max - HALF_WAD) / b) revert IHyperionTypes.MathOverflow();
            c = (a * b + HALF_WAD) / WAD;
        }
    }

    /**
     * @notice Multiplies two Wad values, rounding up to ceiling.
     * @param a Left operand (Wad)
     * @param b Right operand (Wad)
     * @return c Ceiling of (a * b) / WAD
     */
    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        unchecked {
            if (a > (type(uint256).max - (WAD - 1)) / b) revert IHyperionTypes.MathOverflow();
            c = (a * b + (WAD - 1)) / WAD;
        }
    }

    /**
     * @notice Divides two Wad values, rounding down.
     * @param a Numerator (Wad)
     * @param b Denominator (Wad)
     * @return c Result of (a * WAD) / b
     */
    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        unchecked {
            if (a > type(uint256).max / WAD) revert IHyperionTypes.MathOverflow();
            c = (a * WAD) / b;
        }
    }

    /**
     * @notice Divides two Wad values, rounding half up.
     * @param a Numerator (Wad)
     * @param b Denominator (Wad)
     * @return c Result of (a * WAD + b / 2) / b
     */
    function wadDivHalfUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        unchecked {
            uint256 halfB = b / 2;
            if (a > (type(uint256).max - halfB) / WAD) revert IHyperionTypes.MathOverflow();
            c = (a * WAD + halfB) / b;
        }
    }

    /**
     * @notice Divides two Wad values, rounding up to ceiling.
     * @param a Numerator (Wad)
     * @param b Denominator (Wad)
     * @return c Ceiling of (a * WAD) / b
     */
    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        unchecked {
            if (a > (type(uint256).max - (b - 1)) / WAD) revert IHyperionTypes.MathOverflow();
            c = (a * WAD + (b - 1)) / b;
        }
    }

    /**
     * @notice Multiplies two Ray values, rounding down.
     */
    function rayMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        unchecked {
            if (a > type(uint256).max / b) revert IHyperionTypes.MathOverflow();
            c = (a * b) / RAY;
        }
    }

    /**
     * @notice Multiplies two Ray values, rounding half up.
     */
    function rayMulHalfUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0 || b == 0) return 0;
        unchecked {
            if (a > (type(uint256).max - HALF_RAY) / b) revert IHyperionTypes.MathOverflow();
            c = (a * b + HALF_RAY) / RAY;
        }
    }

    /**
     * @notice Divides two Ray values, rounding down.
     */
    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        unchecked {
            if (a > type(uint256).max / RAY) revert IHyperionTypes.MathOverflow();
            c = (a * RAY) / b;
        }
    }

    /**
     * @notice Divides two Ray values, rounding up.
     */
    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (b == 0) revert IHyperionTypes.DivisionByZero();
        if (a == 0) return 0;
        unchecked {
            if (a > (type(uint256).max - (b - 1)) / RAY) revert IHyperionTypes.MathOverflow();
            c = (a * RAY + (b - 1)) / b;
        }
    }

    /**
     * @notice Converts a Wad value (18 decimals) to a Ray value (27 decimals).
     */
    function wadToRay(uint256 a) internal pure returns (uint256) {
        unchecked {
            if (a > type(uint256).max / WAD_RAY_RATIO) revert IHyperionTypes.MathOverflow();
            return a * WAD_RAY_RATIO;
        }
    }

    /**
     * @notice Converts a Ray value (27 decimals) to a Wad value (18 decimals), rounding half up.
     */
    function rayToWad(uint256 a) internal pure returns (uint256) {
        unchecked {
            uint256 halfRatio = WAD_RAY_RATIO / 2;
            return (a + halfRatio) / WAD_RAY_RATIO;
        }
    }

    /**
     * @notice Computes integer square root using the Babylonian method.
     * @param y Value whose square root is computed
     * @return z Floor of sqrt(y)
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (y > 3) {
                z = y;
                uint256 x = y / 2 + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) / 2;
                }
            } else if (y != 0) {
                z = 1;
            }
        }
    }

    /**
     * @notice Computes Wad square root: sqrt(x * WAD).
     * @param x Wad value
     * @return z Square root in Wad
     */
    function wadSqrt(uint256 x) internal pure returns (uint256 z) {
        unchecked {
            return sqrt(x * WAD);
        }
    }

    /**
     * @notice Exponentiation for Ray values: a^n.
     * @param a Base in Ray
     * @param n Exponent integer
     * @return z Result in Ray
     */
    function rayPow(uint256 a, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? a : RAY;
        for (n /= 2; n != 0; n /= 2) {
            a = rayMul(a, a);
            if (n % 2 != 0) {
                z = rayMul(z, a);
            }
        }
    }
}
