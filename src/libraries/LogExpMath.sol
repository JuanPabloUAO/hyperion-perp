// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {SignedMath} from "./SignedMath.sol";

/**
 * @title LogExpMath
 * @notice Fixed-point 18-decimal logarithm and exponentiation library.
 * @dev Computes exp(x), ln(x), and x^y using Horner polynomial expansions and argument reduction.
 */
library LogExpMath {
    using SignedMath for int256;

    int256 internal constant WAD = 1e18;
    int256 internal constant LN2 = 693147180559945309; // ln(2) in Wad

    // Bounds for exp
    int256 internal constant MIN_EXP_INPUT = -41446531673892822312; // ln(2^-60)
    int256 internal constant MAX_EXP_INPUT = 135305999368893231589; // ln(2^195)

    /**
     * @notice Computes e^x where x and return value are fixed-point Wad values.
     * @param x Exponent in Wad (18 decimals)
     * @return result e^x in Wad
     */
    function expWad(int256 x) internal pure returns (uint256 result) {
        if (x < MIN_EXP_INPUT) return 0;
        if (x > MAX_EXP_INPUT) revert IHyperionTypes.MathOverflow();

        // Reduce range using x = k * ln(2) + r, where -ln(2)/2 <= r <= ln(2)/2
        int256 k = (x + (x >= 0 ? LN2 / 2 : -LN2 / 2)) / LN2;
        int256 r = x - k * LN2;

        // Horner's evaluation of e^r: 1 + r + r^2/2! + r^3/3! + r^4/4! + r^5/5! + r^6/6!
        int256 r2 = (r * r) / WAD;
        int256 r3 = (r2 * r) / WAD;
        int256 r4 = (r3 * r) / WAD;
        int256 r5 = (r4 * r) / WAD;
        int256 r6 = (r5 * r) / WAD;

        int256 series = WAD + r + r2 / 2 + r3 / 6 + r4 / 24 + r5 / 120 + r6 / 720;

        // Multiply by 2^k
        if (k >= 0) {
            result = uint256(series) << uint256(k);
        } else {
            result = uint256(series) >> uint256(-k);
        }
    }

    /**
     * @notice Computes the natural logarithm ln(x) where x and return value are in Wad.
     * @param x Input argument in Wad (must be strictly positive)
     * @return result ln(x) in Wad
     */
    function lnWad(int256 x) internal pure returns (int256 result) {
        if (x <= 0) revert IHyperionTypes.MathUnderflow();

        // Count binary exponent
        int256 k = 0;
        int256 y = x;

        while (y >= 2 * WAD) {
            y >>= 1;
            k++;
        }
        while (y < WAD) {
            y <<= 1;
            k--;
        }

        // Now y in [1.0, 2.0). Map z = (y - 1) / (y + 1)
        int256 num = (y - WAD) * WAD;
        int256 den = y + WAD;
        int256 z = num / den;

        // Series: ln((1+z)/(1-z)) = 2 * (z + z^3/3 + z^5/5 + z^7/7 + z^9/9)
        int256 z2 = (z * z) / WAD;
        int256 z3 = (z2 * z) / WAD;
        int256 z5 = (z3 * z2) / WAD;
        int256 z7 = (z5 * z2) / WAD;
        int256 z9 = (z7 * z2) / WAD;

        int256 poly = z + z3 / 3 + z5 / 5 + z7 / 7 + z9 / 9;
        int256 logY = 2 * poly;

        result = logY + k * LN2;
    }

    /**
     * @notice Computes x^y for Wad values.
     * @param x Base (Wad)
     * @param y Exponent (Wad)
     * @return z x^y (Wad)
     */
    function powWad(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (y == 0) return uint256(WAD);
        if (x == 0) return 0;
        int256 lnX = lnWad(int256(x));
        int256 product = SignedMath.sWadMul(int256(y), lnX);
        return expWad(product);
    }
}
