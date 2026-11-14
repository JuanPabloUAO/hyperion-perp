// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionClearingHouse} from "../src/core/HyperionClearingHouse.sol";
import {HyperionMargin} from "../src/core/HyperionMargin.sol";
import {HyperionVAMM} from "../src/core/HyperionVAMM.sol";
import {HyperionFundingController} from "../src/core/HyperionFundingController.sol";
import {HyperionOracleRelay} from "../src/oracle/HyperionOracleRelay.sol";
import {HyperionFeeTreasury} from "../src/governance/HyperionFeeTreasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";

contract HyperionClearingHouseTest is Test {
    using WadRayMath for uint256;

    HyperionClearingHouse internal clearingHouse;
    HyperionMargin internal margin;
    HyperionVAMM internal vamm;
    HyperionFundingController internal funding;
    HyperionOracleRelay internal oracle;
    HyperionFeeTreasury internal treasury;

    MockERC20 internal usdc;
    MockPriceFeed internal ethFeed;

    address internal owner = address(0x044E);
    address internal trader = address(0x78AD);
    address internal trader2 = address(0x8888);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MARKET_ID = 1;

    function setUp() public {
        vm.startPrank(owner);

        margin = new HyperionMargin(owner);
        clearingHouse = new HyperionClearingHouse(owner);
        oracle = new HyperionOracleRelay(owner, owner);
        funding = new HyperionFundingController(owner, address(oracle));
        treasury = new HyperionFeeTreasury(owner, address(0x1), address(0x2), address(0x3));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        ethFeed = new MockPriceFeed(8, 2000e8); // $2,000 ETH price (8 decimals)

        // Deploy vAMM: 1000 ETH base, 2,000,000 USD quote ($2000 spot)
        vamm = new HyperionVAMM(
            MARKET_ID,
            address(clearingHouse),
            owner,
            1000 * WAD,
            2_000_000 * WAD,
            0.0006e18, // 6 bps taker fee
            0.0002e18 // 2 bps maker
        );

        // Wire system addresses
        clearingHouse.setSystemAddresses(address(margin), address(funding), address(oracle), address(treasury));
        margin.setSystemAddresses(address(clearingHouse), address(0x99), address(oracle));
        funding.registerMarketVAMM(MARKET_ID, address(vamm));

        // Configure oracle feed
        oracle.configureFeed(MARKET_ID, address(ethFeed), address(0), 3600);

        // Configure collateral USDC
        margin.configureCollateral(address(usdc), 6, 1.0e18, 10_000_000 * 1e6, true);

        // Configure PID
        funding.setPIDConfig(
            MARKET_ID,
            IHyperionTypes.PIDConfig({
                kp: 0.05e18,
                ki: 0.001e18,
                kd: 0.01e18,
                maxFundingVelocity: 0.0001e18,
                maxFundingRate: 0.01e18, // 1% max per 8h
                integralError: 0,
                lastError: 0,
                lastTimestamp: block.timestamp
            })
        );

        // Register market in clearinghouse
        clearingHouse.registerMarket(
            MARKET_ID,
            "ETH-PERP",
            address(vamm),
            50e18, // 50x max leverage
            0.05e18, // 5% IMR (up to 20x entry)
            0.02e18, // 2% MMR
            0.03e18, // 3% liquidation penalty
            0.0006e18, // 6 bps taker fee
            0.0002e18, // 2 bps maker fee
            100_000e18 // 100k max open interest
        );

        vm.stopPrank();

        // Mint USDC to traders
        usdc.mint(trader, 100_000 * 1e6);
        usdc.mint(trader2, 100_000 * 1e6);

        vm.prank(trader);
        usdc.approve(address(margin), type(uint256).max);

        vm.prank(trader2);
        usdc.approve(address(margin), type(uint256).max);
    }

    function test_OpenPosition_Long() public {
        // Trader deposits 10,000 USDC
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 10_000 * 1e6);

        // Open 5 ETH Long
        vm.prank(trader);
        (uint256 posId, uint256 execPrice) = clearingHouse.openPosition(
            MARKET_ID,
            IHyperionTypes.Side.LONG,
            5 * WAD,
            2100 * WAD, // Max slippage
            IHyperionTypes.MarginMode.CROSS
        );

        assertGt(posId, 0);
        assertGt(execPrice, 2000 * WAD);

        IHyperionTypes.Position memory pos = clearingHouse.getPosition(trader, MARKET_ID);
        assertEq(pos.size, 5 * WAD);
        assertEq(uint256(pos.side), uint256(IHyperionTypes.Side.LONG));
        assertEq(pos.entryPrice, execPrice);

        (uint256 longOI, uint256 shortOI) = clearingHouse.getOpenInterest(MARKET_ID);
        assertEq(longOI, 5 * WAD);
        assertEq(shortOI, 0);
    }

    function test_OpenAndClosePosition_RealizedProfit() public {
        // Trader 1 deposits collateral and opens 10 ETH Long
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 20_000 * 1e6);

        vm.prank(trader);
        (, uint256 entryPrice) = clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 10 * WAD, 2200 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Trader 2 pushes price up by opening another big Long
        vm.prank(trader2);
        margin.depositCollateral(address(usdc), 50_000 * 1e6);

        vm.prank(trader2);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 30 * WAD, 2500 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Now spot price is higher
        uint256 newSpot = vamm.getSpotPrice();
        assertGt(newSpot, entryPrice);

        // Trader 1 closes position
        vm.prank(trader);
        (int256 pnl, uint256 closePrice) =
            clearingHouse.closePosition(
                MARKET_ID,
                10 * WAD,
                2000 * WAD // Min slippage
            );

        assertGt(closePrice, entryPrice);
        assertGt(pnl, 0); // Realized profit

        IHyperionTypes.Position memory posAfter = clearingHouse.getPosition(trader, MARKET_ID);
        assertEq(posAfter.size, 0);
    }

    function test_RevertOnExceedsSlippage() public {
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 10_000 * 1e6);

        vm.prank(trader);
        // Expect price around $2010, set limit to $2000 => revert
        vm.expectRevert(IHyperionTypes.SlippageExceeded.selector);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 5 * WAD, 2000 * WAD, IHyperionTypes.MarginMode.CROSS
        );
    }
}
