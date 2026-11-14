// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "../src/libraries/TickMath.sol";

contract TickMathTest is Test {
    function test_SqrtRatioAtTick_Zero() public pure {
        // At tick 0, ratio = 1.0 * 2^96 = 79228162514264337593543950336
        uint160 ratio = TickMath.getSqrtRatioAtTick(0);
        assertEq(ratio, 79228162514264337593543950336);
    }

    function test_SqrtRatioAtTick_Boundaries() public pure {
        uint160 minRatio = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK);
        uint160 maxRatio = TickMath.getSqrtRatioAtTick(TickMath.MAX_TICK);

        assertGe(minRatio, TickMath.MIN_SQRT_RATIO);
        assertLe(maxRatio, TickMath.MAX_SQRT_RATIO);
    }

    function test_TickAtSqrtRatio_RoundTrip() public pure {
        int24[] memory ticks = new int24[](5);
        ticks[0] = 0;
        ticks[1] = 100;
        ticks[2] = -100;
        ticks[3] = 50000;
        ticks[4] = -50000;

        for (uint256 i = 0; i < ticks.length; i++) {
            uint160 ratio = TickMath.getSqrtRatioAtTick(ticks[i]);
            int24 recoveredTick = TickMath.getTickAtSqrtRatio(ratio);
            assertEq(recoveredTick, ticks[i]);
        }
    }

    function testFuzz_TickMonotonicity(int24 tickA, int24 tickB) public pure {
        vm.assume(tickA >= -100000 && tickA <= 100000);
        vm.assume(tickB >= -100000 && tickB <= 100000);

        uint160 ratioA = TickMath.getSqrtRatioAtTick(tickA);
        uint160 ratioB = TickMath.getSqrtRatioAtTick(tickB);

        if (tickA < tickB) {
            assertLt(ratioA, ratioB);
        } else if (tickA > tickB) {
            assertGt(ratioA, ratioB);
        } else {
            assertEq(ratioA, ratioB);
        }
    }
}
