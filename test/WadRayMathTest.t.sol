// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract WadRayMathTest is Test {
    using WadRayMath for uint256;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    function test_WadMul_Identity() public pure {
        uint256 a = 42 * WAD;
        uint256 b = 1 * WAD;
        assertEq(a.wadMul(b), 42 * WAD);
    }

    function test_WadMul_Fractional() public pure {
        uint256 a = 10 * WAD;
        uint256 b = 0.5e18; // 0.5
        assertEq(a.wadMul(b), 5 * WAD);
    }

    function test_WadMulUp_Ceiling() public pure {
        uint256 a = 1;
        uint256 b = 1;
        // 1 * 1 / 1e18 = 0 in wadMul, but 1 in wadMulUp
        assertEq(a.wadMul(b), 0);
        assertEq(a.wadMulUp(b), 1);
    }

    function test_WadDiv_Identity() public pure {
        uint256 a = 100 * WAD;
        uint256 b = 1 * WAD;
        assertEq(a.wadDiv(b), 100 * WAD);
    }

    function test_WadDiv_Half() public pure {
        uint256 a = 100 * WAD;
        uint256 b = 2 * WAD;
        assertEq(a.wadDiv(b), 50 * WAD);
    }

    function test_WadDivUp_Ceiling() public pure {
        uint256 a = 1;
        uint256 b = 2 * WAD;
        // 1 * 1e18 / 2e18 = 0, but wadDivUp should round to 1
        assertEq(a.wadDiv(b), 0);
        assertEq(a.wadDivUp(b), 1);
    }

    function externalDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return a.wadDiv(b);
    }

    function test_WadDiv_RevertOnZero() public {
        vm.expectRevert(IHyperionTypes.DivisionByZero.selector);
        this.externalDiv(10 * WAD, 0);
    }

    function test_RayMul_Identity() public pure {
        uint256 a = 77 * RAY;
        uint256 b = 1 * RAY;
        assertEq(a.rayMul(b), 77 * RAY);
    }

    function test_RayDiv_Identity() public pure {
        uint256 a = 500 * RAY;
        uint256 b = 10 * RAY;
        assertEq(a.rayDiv(b), 50 * RAY);
    }

    function test_WadToRay_Conversion() public pure {
        uint256 wad = 3.5e18;
        uint256 ray = wad.wadToRay();
        assertEq(ray, 3.5e27);
        assertEq(ray.rayToWad(), wad);
    }

    function test_WadSqrt_KnownValues() public pure {
        // sqrt(4e18 * 1e18) = sqrt(4e36) = 2e18
        assertEq(WadRayMath.wadSqrt(4 * WAD), 2 * WAD);
        assertEq(WadRayMath.wadSqrt(9 * WAD), 3 * WAD);
        assertEq(WadRayMath.wadSqrt(16 * WAD), 4 * WAD);
        assertEq(WadRayMath.wadSqrt(100 * WAD), 10 * WAD);
    }

    function test_RayPow_BaseCases() public pure {
        uint256 r = 1.05e27; // 1.05 in Ray
        assertEq(WadRayMath.rayPow(r, 0), RAY);
        assertEq(WadRayMath.rayPow(r, 1), r);
        // (1.05)^2 = 1.1025
        assertEq(WadRayMath.rayPow(r, 2), 1.1025e27);
    }

    function testFuzz_WadMulDiv_Inversion(uint128 aRaw, uint128 bRaw) public pure {
        vm.assume(bRaw > 1e14 && bRaw < 1e30);
        vm.assume(aRaw > 1e14 && aRaw < 1e30);

        uint256 a = uint256(aRaw);
        uint256 b = uint256(bRaw);

        uint256 product = a.wadMul(b);
        uint256 recovered = product.wadDiv(b);

        assertApproxEqRel(recovered, a, 1e14); // within 0.01%
    }
}
