// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionLiquidator} from "../src/risk/HyperionLiquidator.sol";
import {HyperionInsuranceFund} from "../src/risk/HyperionInsuranceFund.sol";
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

contract HyperionLiquidatorTest is Test {
    using WadRayMath for uint256;

    HyperionLiquidator internal liquidator;
    HyperionInsuranceFund internal insurance;
    HyperionClearingHouse internal clearingHouse;
    HyperionMargin internal margin;
    HyperionVAMM internal vamm;
    HyperionFundingController internal funding;
    HyperionOracleRelay internal oracle;
    HyperionFeeTreasury internal treasury;

    MockERC20 internal usdc;
    MockPriceFeed internal feed;

    address internal owner = address(0x044E);
    address internal trader = address(0x78AD);
    address internal keeper = address(0xDEED);

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MARKET_ID = 1;

    function setUp() public {
        vm.startPrank(owner);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        feed = new MockPriceFeed(8, 2000e8);

        oracle = new HyperionOracleRelay(owner, owner);
        margin = new HyperionMargin(owner);
        clearingHouse = new HyperionClearingHouse(owner);
        funding = new HyperionFundingController(owner, address(oracle));
        treasury = new HyperionFeeTreasury(owner, address(0x1), address(0x2), address(0x3));

        insurance = new HyperionInsuranceFund(owner, address(usdc));
        liquidator = new HyperionLiquidator(owner);

        vamm = new HyperionVAMM(MARKET_ID, address(clearingHouse), owner, 1000 * WAD, 2_000_000 * WAD, 0.0006e18, 0);

        // Link addresses
        clearingHouse.setSystemAddresses(address(margin), address(funding), address(oracle), address(treasury));
        clearingHouse.setLiquidator(address(liquidator));
        margin.setSystemAddresses(address(clearingHouse), address(liquidator), address(oracle));
        liquidator.setSystemAddresses(address(clearingHouse), address(margin), address(insurance));
        insurance.setSystemAddresses(address(liquidator), address(clearingHouse));
        vamm.setLiquidator(address(liquidator));
        funding.registerMarketVAMM(MARKET_ID, address(vamm));

        oracle.configureFeed(MARKET_ID, address(feed), address(0), 3600);
        margin.configureCollateral(address(usdc), 6, 1.0e18, 10_000_000 * 1e6, true);

        funding.setPIDConfig(
            MARKET_ID,
            IHyperionTypes.PIDConfig({
                kp: 0.05e18,
                ki: 0,
                kd: 0,
                maxFundingVelocity: 0.0001e18,
                maxFundingRate: 0.01e18,
                integralError: 0,
                lastError: 0,
                lastTimestamp: block.timestamp
            })
        );

        clearingHouse.registerMarket(
            MARKET_ID, "ETH-PERP", address(vamm), 50e18, 0.05e18, 0.02e18, 0.03e18, 0.0006e18, 0, 100_000e18
        );

        vm.stopPrank();

        usdc.mint(trader, 5_000 * 1e6);
        usdc.mint(address(insurance), 100_000 * 1e6); // Seed insurance fund with $100k

        vm.prank(trader);
        usdc.approve(address(margin), type(uint256).max);
    }

    function test_SoftLiquidation_WhenHealthBelowMMR() public {
        // Trader deposits $2,000 and opens 15 ETH Long (value $30,000, 15x leverage)
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 2_000 * 1e6);

        vm.prank(trader);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 15 * WAD, 2100 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Push market price down sharply by dumping on vAMM
        vm.prank(address(clearingHouse));
        vamm.executeSwap(IHyperionTypes.Side.SHORT, 80 * WAD);

        // Check trader liquidation status
        (IHyperionTypes.LiquidationTier tier, uint256 hf) = liquidator.checkLiquidationStatus(trader);
        assertTrue(tier != IHyperionTypes.LiquidationTier.NONE);
        assertLt(hf, 1.0e18);

        // Keeper executes soft liquidation
        vm.prank(keeper);
        (uint256 liquidatedSize, uint256 penalty) = liquidator.executeSoftLiquidation(trader, MARKET_ID);

        assertGt(liquidatedSize, 0);
        assertGt(penalty, 0);

        IHyperionTypes.Position memory pos = clearingHouse.getPosition(trader, MARKET_ID);
        assertEq(pos.size, 15 * WAD - liquidatedSize);
    }

    function test_DutchAuction_LinearDecay() public {
        // Setup underwater trader
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 1_500 * 1e6);

        vm.prank(trader);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 10 * WAD, 2100 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Dump price
        vm.prank(address(clearingHouse));
        vamm.executeSwap(IHyperionTypes.Side.SHORT, 60 * WAD);

        // Start Dutch auction
        uint256 auctionId = liquidator.startDutchAuction(trader, MARKET_ID);
        assertEq(auctionId, 1);

        uint256 startTs = block.timestamp;
        uint256 priceAtStart = liquidator.getDutchAuctionCurrentPrice(auctionId);

        // Warp forward half of auction duration (450 seconds)
        vm.warp(startTs + 450);
        uint256 priceAtMid = liquidator.getDutchAuctionCurrentPrice(auctionId);

        // For long liquidation (selling base), price descends linearly
        assertLt(priceAtMid, priceAtStart);

        // Warp to end (900 seconds total)
        vm.warp(startTs + 900);
        uint256 priceAtEnd = liquidator.getDutchAuctionCurrentPrice(auctionId);
        assertLt(priceAtEnd, priceAtMid);

        // Keeper bids to buy 5 ETH of auction inventory
        vm.prank(keeper);
        uint256 execPrice = liquidator.bidDutchAuction(auctionId, 5 * WAD, priceAtEnd + 10 * WAD);
        assertEq(execPrice, priceAtEnd);
    }

    function test_InsuranceFundTakeover_BadDebtAbsorbed() public {
        // Trader with catastrophic loss where equity < 0
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 1_200 * 1e6);

        vm.prank(trader);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 10 * WAD, 2100 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Massive price collapse on vAMM: push equity deeply negative
        vm.prank(address(clearingHouse));
        vamm.executeSwap(IHyperionTypes.Side.SHORT, 250 * WAD);

        (IHyperionTypes.LiquidationTier tier,) = liquidator.checkLiquidationStatus(trader);
        assertEq(uint256(tier), uint256(IHyperionTypes.LiquidationTier.TIER3_INSURANCE_TAKEOVER));

        uint256 reserveBefore = insurance.getReserveBalance();

        // Trigger Tier 3 insurance takeover
        uint256 badDebt = liquidator.executeInsuranceTakeover(trader, MARKET_ID);
        assertGt(badDebt, 0);

        // Insurance fund absorbed the deficit
        assertEq(insurance.totalDeficitsCovered(), badDebt);
        assertLt(insurance.getReserveBalance(), reserveBefore);
    }
}
