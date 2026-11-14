// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionVAMM} from "../src/core/HyperionVAMM.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";

contract HyperionVAMMTest is Test {
    using WadRayMath for uint256;

    HyperionVAMM internal vamm;
    address internal clearingHouse = address(0xC1EA);
    address internal owner = address(0x044E);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant INITIAL_BASE = 1000e18; // 1,000 ETH
    uint256 internal constant INITIAL_QUOTE = 2_000_000e18; // 2,000,000 USD (Spot price = $2,000)

    function setUp() public {
        vamm = new HyperionVAMM(
            1, // marketId
            clearingHouse,
            owner,
            INITIAL_BASE,
            INITIAL_QUOTE,
            0.0006e18, // 6 bps taker fee
            0.0002e18 // 2 bps maker rebate
        );
    }

    function test_InitialSpotPrice() public view {
        // Initial price = 2,000,000 / 1,000 = 2,000 USD
        assertEq(vamm.getSpotPrice(), 2000 * WAD);
    }

    function test_QuoteSwap_Long() public view {
        // Buy 10 ETH: base decreases to 990, quote increases to (1000 * 2M) / 990 = 2,020,202.02
        (uint256 quoteAmount, uint256 baseAmount, uint256 priceAfter) =
            vamm.quoteSwap(IHyperionTypes.Side.LONG, 10 * WAD, true);

        assertEq(baseAmount, 10 * WAD);
        assertGt(quoteAmount, 20_000 * WAD); // Due to slippage, cost > 10 * 2000
        assertGt(priceAfter, 2000 * WAD); // Price increases after buy
    }

    function test_QuoteSwap_Short() public view {
        // Sell 10 ETH: base increases to 1010, quote decreases to (1000 * 2M) / 1010 = 1,980,198.01
        (uint256 quoteAmount, uint256 baseAmount, uint256 priceAfter) =
            vamm.quoteSwap(IHyperionTypes.Side.SHORT, 10 * WAD, true);

        assertEq(baseAmount, 10 * WAD);
        assertLt(quoteAmount, 20_000 * WAD); // Due to slippage, received < 10 * 2000
        assertLt(priceAfter, 2000 * WAD); // Price decreases after sell
    }

    function test_ExecuteSwap_MutatesReserves() public {
        vm.prank(clearingHouse);
        (uint256 quoteTransferred, uint256 execPrice) = vamm.executeSwap(IHyperionTypes.Side.LONG, 10 * WAD);

        assertGt(quoteTransferred, 20_000 * WAD);
        assertGt(execPrice, 2000 * WAD);

        (uint256 vBase, uint256 vQuote) = vamm.getReserves();
        assertEq(vBase, 990 * WAD);
        assertEq(vQuote, INITIAL_QUOTE + quoteTransferred);
        assertGt(vamm.getSpotPrice(), 2000 * WAD);
    }

    function test_TWAP_Accumulation() public {
        // Step forward in time
        vm.warp(block.timestamp + 100);

        // Spot is $2000
        assertEq(vamm.getTWAP(100), 2000 * WAD);

        // Execute swap to push price
        vm.prank(clearingHouse);
        vamm.executeSwap(IHyperionTypes.Side.LONG, 50 * WAD);

        uint256 newSpot = vamm.getSpotPrice();
        assertGt(newSpot, 2000 * WAD);

        // Warp 100 seconds
        vm.warp(block.timestamp + 100);

        // 100s TWAP should reflect the new higher price
        uint256 twap = vamm.getTWAP(100);
        assertApproxEqRel(twap, newSpot, 1e15);
    }

    function test_RevertUnauthorizedSwap() public {
        vm.expectRevert(IHyperionTypes.UnauthorizedCaller.selector);
        vamm.executeSwap(IHyperionTypes.Side.LONG, 10 * WAD);
    }
}
