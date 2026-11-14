// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionFundingController} from "../src/core/HyperionFundingController.sol";
import {HyperionVAMM} from "../src/core/HyperionVAMM.sol";
import {HyperionOracleRelay} from "../src/oracle/HyperionOracleRelay.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";
import {SignedMath} from "../src/libraries/SignedMath.sol";

contract HyperionFundingControllerTest is Test {
    using SignedMath for int256;

    HyperionFundingController internal controller;
    HyperionOracleRelay internal oracle;
    HyperionVAMM internal vamm;
    MockPriceFeed internal feed;

    address internal owner = address(0x044E);
    uint256 internal constant MARKET_ID = 1;
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        vm.startPrank(owner);

        oracle = new HyperionOracleRelay(owner, owner);
        controller = new HyperionFundingController(owner, address(oracle));

        feed = new MockPriceFeed(8, 2000e8); // $2,000 index
        oracle.configureFeed(MARKET_ID, address(feed), address(0), 3600);

        // Deploy vAMM with mark price $2,000 (1000 base, 2,000,000 quote)
        vamm = new HyperionVAMM(MARKET_ID, address(this), owner, 1000 * WAD, 2_000_000 * WAD, 0, 0);
        controller.registerMarketVAMM(MARKET_ID, address(vamm));

        controller.setPIDConfig(
            MARKET_ID,
            IHyperionTypes.PIDConfig({
                kp: 0.1e18, // Kp = 0.10
                ki: 0.001e18, // Ki = 0.001
                kd: 0.01e18, // Kd = 0.01
                maxFundingVelocity: 0.0001e18,
                maxFundingRate: 0.01e18, // 1% max per 8h
                integralError: 0,
                lastError: 0,
                lastTimestamp: block.timestamp
            })
        );

        vm.stopPrank();
    }

    function test_InitialFundingRate_ZeroPremium() public {
        // When mark == index ($2000 == $2000), error = 0 => funding rate = 0
        (int256 currentRate, int256 cumulativeRate) = controller.updateFundingRate(MARKET_ID);
        assertEq(currentRate, 0);
        assertEq(cumulativeRate, 0);
    }

    function test_PositiveFundingRate_WhenMarkAboveIndex() public {
        // Push mark price to $2,100 by executing swap on vAMM
        vamm.executeSwap(IHyperionTypes.Side.LONG, 47 * WAD);

        // Warp time forward 1 hour (3600 seconds)
        vm.warp(block.timestamp + 3600);

        (int256 rate, int256 cumRate) = controller.updateFundingRate(MARKET_ID);

        // Mark > Index => Longs pay shorts (rate > 0)
        assertGt(rate, 0);
        assertGt(cumRate, 0);
    }

    function test_NegativeFundingRate_WhenMarkBelowIndex() public {
        // Push mark price below index ($2000) by selling base
        vamm.executeSwap(IHyperionTypes.Side.SHORT, 50 * WAD);

        vm.warp(block.timestamp + 3600);

        (int256 rate, int256 cumRate) = controller.updateFundingRate(MARKET_ID);

        // Mark < Index => Shorts pay longs (rate < 0)
        assertLt(rate, 0);
        assertLt(cumRate, 0);
    }

    function test_FundingRateClamp_MaxBound() public {
        // Huge premium: set index price low ($1,000) while mark is $2,000
        feed.setAnswer(1000e8);

        vm.warp(block.timestamp + 3600);

        (int256 rate,) = controller.updateFundingRate(MARKET_ID);

        // Should be clamped by maxFundingRate (0.01e18)
        assertLe(rate, 0.01e18);
    }
}
