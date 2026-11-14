// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title BitMapTree
 * @notice Packed 2-level 256-bit word bitmap for O(1) initialized tick search.
 * @dev Stores initialized ticks in a sparse mapping from word position to uint256 bitfield.
 */
library BitMapTree {
    /**
     * @notice Computes word position and bit index within that word for a given tick.
     * @param tick Integer tick index
     * @return wordPos Index of the 256-bit word in the mapping
     * @return bitPos Bit position [0..255] within the word
     */
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    /**
     * @notice Flips the initialization status of a tick in the bitmap.
     * @param self Mapping of word indices to bitfields
     * @param tick Tick index to toggle
     */
    function flipTick(mapping(int16 => uint256) storage self, int24 tick) internal {
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /**
     * @notice Checks if a tick is currently initialized in the bitmap.
     * @param self Mapping of word indices to bitfields
     * @param tick Tick index to check
     * @return isInit True if tick bit is set
     */
    function isInitialized(mapping(int16 => uint256) storage self, int24 tick) internal view returns (bool isInit) {
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        return (self[wordPos] & mask) != 0;
    }

    /**
     * @notice Finds the next initialized tick within the same word or boundary.
     * @param self Mapping of word indices to bitfields
     * @param tick Starting tick index
     * @param lte If true, search downwards (<= tick); if false, search upwards (> tick)
     * @return next Next initialized tick, or boundary if none initialized in this word
     * @return initialized True if an initialized tick was found within the word
     */
    function nextInitializedTickWithinOneWord(mapping(int16 => uint256) storage self, int24 tick, bool lte)
        internal
        view
        returns (int24 next, bool initialized)
    {
        (int16 wordPos, uint8 bitPos) = position(tick);

        if (lte) {
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            if (initialized) {
                // Find most significant bit in masked
                uint8 msb = mostSignificantBit(masked);
                next = int24((int256(wordPos) << 8) + int256(uint256(msb)));
            } else {
                next = int24((int256(wordPos) << 8));
            }
        } else {
            uint256 mask = ~((1 << (bitPos + 1)) - 1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;
            if (initialized) {
                // Find least significant bit in masked
                uint8 lsb = leastSignificantBit(masked);
                next = int24((int256(wordPos) << 8) + int256(uint256(lsb)));
            } else {
                next = int24((int256(wordPos) << 8) + 255);
            }
        }
    }

    /**
     * @notice Finds index of most significant bit set in 256-bit word.
     */
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0, "Zero input");
        assembly {
            let f := shl(7, gt(x, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(6, gt(x, 0xFFFFFFFFFFFFFFFF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(5, gt(x, 0xFFFFFFFF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(4, gt(x, 0xFFFF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(3, gt(x, 0xFF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(2, gt(x, 0xF))
            x := shr(f, x)
            r := or(r, f)
            f := shl(1, gt(x, 0x3))
            x := shr(f, x)
            r := or(r, f)
            f := gt(x, 0x1)
            r := or(r, f)
        }
    }

    /**
     * @notice Finds index of least significant bit set in 256-bit word.
     */
    function leastSignificantBit(uint256 x) internal pure returns (uint8) {
        require(x > 0, "Zero input");
        uint256 lowestBit = x & (~x + 1);
        return mostSignificantBit(lowestBit);
    }
}
