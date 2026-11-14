// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SignedMath} from "../src/libraries/SignedMath.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract SignedMathTest is Test {
    using SignedMath for int256;

    int256 internal constant WAD = 1e18;

    function test_SignedAbs() public pure {
        assertEq((-42 * WAD).abs(), 42 * 1e18);
        assertEq((42 * WAD).abs(), 42 * 1e18);
        assertEq((int256(0)).abs(), 0);
    }

    function test_SignedSign() public pure {
        assertEq(SignedMath.sign(-100), -1);
        assertEq(SignedMath.sign(100), 1);
        assertEq(SignedMath.sign(0), 0);
    }

    function test_SignedWadMul_Signs() public pure {
        int256 a = 10 * WAD;
        int256 b = -2 * WAD;
        assertEq(a.sWadMul(b), -20 * WAD);
        assertEq(b.sWadMul(b), 4 * WAD);
    }

    function test_SignedWadDiv_Signs() public pure {
        int256 a = -100 * WAD;
        int256 b = 4 * WAD;
        assertEq(a.sWadDiv(b), -25 * WAD);
        assertEq(a.sWadDiv(-b), 25 * WAD);
    }

    function test_SignedClamp() public pure {
        int256 minVal = -10 * WAD;
        int256 maxVal = 10 * WAD;

        assertEq((int256(5 * WAD)).clamp(minVal, maxVal), 5 * WAD);
        assertEq((int256(-15 * WAD)).clamp(minVal, maxVal), -10 * WAD);
        assertEq((int256(25 * WAD)).clamp(minVal, maxVal), 10 * WAD);
    }

    function test_SignedMinMax() public pure {
        int256 a = -5 * WAD;
        int256 b = 8 * WAD;
        assertEq(a.min(b), -5 * WAD);
        assertEq(a.max(b), 8 * WAD);
    }
}
