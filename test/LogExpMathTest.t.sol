// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {LogExpMath} from "../src/libraries/LogExpMath.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract LogExpMathTest is Test {
    int256 internal constant WAD = 1e18;

    function test_ExpWad_Zero() public pure {
        // e^0 = 1.0 Wad
        assertEq(LogExpMath.expWad(0), uint256(WAD));
    }

    function test_ExpWad_One() public pure {
        // e^1 = 2.718281828459045235 Wad
        uint256 val = LogExpMath.expWad(WAD);
        assertApproxEqRel(val, 2718281828459045235, 1e15); // within 0.1%
    }

    function test_ExpWad_Negative() public pure {
        // e^(-1) = 0.367879441171442321 Wad
        uint256 val = LogExpMath.expWad(-WAD);
        assertApproxEqRel(val, 367879441171442321, 1e15);
    }

    function test_LnWad_One() public pure {
        // ln(1) = 0
        assertEq(LogExpMath.lnWad(WAD), 0);
    }

    function test_LnWad_E() public pure {
        // ln(e) = 1.0 Wad
        int256 e = 2718281828459045235;
        assertApproxEqAbs(LogExpMath.lnWad(e), WAD, 1e15);
    }

    function test_LnWad_Two() public pure {
        // ln(2) = 0.693147180559945309 Wad
        assertApproxEqAbs(LogExpMath.lnWad(2 * WAD), 693147180559945309, 1e15);
    }

    function test_PowWad_PowerOfTwo() public pure {
        // 2^3 = 8
        uint256 base = 2 * uint256(WAD);
        uint256 exp = 3 * uint256(WAD);
        uint256 result = LogExpMath.powWad(base, exp);
        assertApproxEqAbs(result, 8 * uint256(WAD), 1e16);
    }

    function test_PowWad_ZeroExponent() public pure {
        assertEq(LogExpMath.powWad(10 * uint256(WAD), 0), uint256(WAD));
    }
}
