// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BitMapTree} from "../src/libraries/BitMapTree.sol";

contract BitMapTreeTest is Test {
    using BitMapTree for mapping(int16 => uint256);

    mapping(int16 => uint256) internal bitmap;

    function test_FlipAndCheckInitialized() public {
        int24 tick = 42;
        assertFalse(bitmap.isInitialized(tick));

        bitmap.flipTick(tick);
        assertTrue(bitmap.isInitialized(tick));

        bitmap.flipTick(tick);
        assertFalse(bitmap.isInitialized(tick));
    }

    function test_NextInitializedTick_Upwards() public {
        bitmap.flipTick(50);
        bitmap.flipTick(100);

        // Search upwards from tick 20: should find 50
        (int24 next, bool init) = bitmap.nextInitializedTickWithinOneWord(20, false);
        assertTrue(init);
        assertEq(next, 50);

        // Search upwards from tick 50: should find 100
        (next, init) = bitmap.nextInitializedTickWithinOneWord(50, false);
        assertTrue(init);
        assertEq(next, 100);
    }

    function test_NextInitializedTick_Downwards() public {
        bitmap.flipTick(50);
        bitmap.flipTick(100);

        // Search downwards from tick 80: should find 50
        (int24 next, bool init) = bitmap.nextInitializedTickWithinOneWord(80, true);
        assertTrue(init);
        assertEq(next, 50);

        // Search downwards from tick 120: should find 100
        (next, init) = bitmap.nextInitializedTickWithinOneWord(120, true);
        assertTrue(init);
        assertEq(next, 100);
    }
}
