// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionOracleRelay} from "../src/oracle/HyperionOracleRelay.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract HyperionOracleTest is Test {
    HyperionOracleRelay internal oracle;
    MockPriceFeed internal primaryFeed;
    MockPriceFeed internal secondaryFeed;

    address internal owner = address(0x044E);
    address internal guardian = address(0x60A2);
    uint256 internal constant MARKET_ID = 1;
    uint256 internal constant WAD = 1e18;

    function setUp() public {
        vm.startPrank(owner);
        oracle = new HyperionOracleRelay(owner, guardian);

        primaryFeed = new MockPriceFeed(8, 2000e8); // $2,000 (8 decimals)
        secondaryFeed = new MockPriceFeed(8, 2005e8); // $2,005 (0.25% deviation)

        oracle.configureFeed(MARKET_ID, address(primaryFeed), address(secondaryFeed), 3600);
        vm.stopPrank();
    }

    function test_IndexPrice_Averaging() public view {
        (uint256 price, uint256 confidence) = oracle.getIndexPrice(MARKET_ID);
        // Average of 2000 and 2005 is 2002.5 Wad
        assertEq(price, 2002.5e18);
        assertEq(confidence, 5e18); // 5 Wad difference
    }

    function test_StalenessRevert() public {
        // Warp time beyond heartbeat window (3600s)
        vm.warp(block.timestamp + 4000);

        vm.expectRevert(IHyperionTypes.OracleStale.selector);
        oracle.getIndexPrice(MARKET_ID);
    }

    function test_CircuitBreaker_TrippedOnExcessiveDeviation() public {
        // Create 10% divergence: primary = $2,000, secondary = $2,250
        secondaryFeed.setAnswer(2250e8);

        // Volatility circuit breaker trips
        vm.prank(guardian);
        oracle.tripCircuitBreaker(MARKET_ID);

        assertTrue(oracle.isCircuitBreakerTripped(MARKET_ID));

        // Guardian resets circuit breaker
        vm.prank(guardian);
        oracle.resetCircuitBreaker(MARKET_ID);

        assertFalse(oracle.isCircuitBreakerTripped(MARKET_ID));
    }
}
