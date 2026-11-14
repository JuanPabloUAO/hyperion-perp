// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionClearingHouse} from "../src/core/HyperionClearingHouse.sol";
import {HyperionMargin} from "../src/core/HyperionMargin.sol";
import {HyperionVAMM} from "../src/core/HyperionVAMM.sol";
import {HyperionFundingController} from "../src/core/HyperionFundingController.sol";
import {HyperionOracleRelay} from "../src/oracle/HyperionOracleRelay.sol";
import {HyperionLiquidator} from "../src/risk/HyperionLiquidator.sol";
import {HyperionInsuranceFund} from "../src/risk/HyperionInsuranceFund.sol";
import {HyperionFeeTreasury} from "../src/governance/HyperionFeeTreasury.sol";
import {TransientStorage} from "../src/libraries/TransientStorage.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";
import {WadRayMath} from "../src/libraries/WadRayMath.sol";
import {SignedMath} from "../src/libraries/SignedMath.sol";

contract HyperionInvariantsTest is Test {
    using WadRayMath for uint256;
    using SignedMath for int256;

    HyperionClearingHouse internal clearingHouse;
    HyperionMargin internal margin;
    HyperionVAMM internal vamm;
    HyperionFundingController internal funding;
    HyperionOracleRelay internal oracle;
    HyperionLiquidator internal liquidator;
    HyperionInsuranceFund internal insurance;
    HyperionFeeTreasury internal treasury;

    MockERC20 internal usdc;
    MockPriceFeed internal feed;

    address internal owner = address(0x044E);
    address internal traderA = address(0xAAAA);
    address internal traderB = address(0xBBBB);

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

        clearingHouse.setSystemAddresses(address(margin), address(funding), address(oracle), address(treasury));
        clearingHouse.setLiquidator(address(liquidator));
        margin.setSystemAddresses(address(clearingHouse), address(liquidator), address(oracle));
        liquidator.setSystemAddresses(address(clearingHouse), address(margin), address(insurance));
        insurance.setSystemAddresses(address(liquidator), address(clearingHouse));
        funding.registerMarketVAMM(MARKET_ID, address(vamm));

        oracle.configureFeed(MARKET_ID, address(feed), address(0), 3600);
        margin.configureCollateral(address(usdc), 6, 1.0e18, 50_000_000 * 1e6, true);

        funding.setPIDConfig(
            MARKET_ID,
            IHyperionTypes.PIDConfig({
                kp: 0.05e18,
                ki: 0.001e18,
                kd: 0.01e18,
                maxFundingVelocity: 0.0001e18,
                maxFundingRate: 0.01e18,
                integralError: 0,
                lastError: 0,
                lastTimestamp: block.timestamp
            })
        );

        clearingHouse.registerMarket(
            MARKET_ID, "ETH-PERP", address(vamm), 50e18, 0.05e18, 0.02e18, 0.03e18, 0.0006e18, 0, 1_000_000e18
        );

        vm.stopPrank();

        usdc.mint(traderA, 1_000_000 * 1e6);
        usdc.mint(traderB, 1_000_000 * 1e6);

        vm.prank(traderA);
        usdc.approve(address(margin), type(uint256).max);

        vm.prank(traderB);
        usdc.approve(address(margin), type(uint256).max);
    }

    /// @notice Invariant 1: Total protocol collateral balance must always equal or exceed active user balances.
    function testFuzz_Invariant_SolvencyConservation(uint32 depositA, uint32 depositB) public {
        vm.assume(depositA > 100 && depositA < 500_000);
        vm.assume(depositB > 100 && depositB < 500_000);

        uint256 amtA = uint256(depositA) * 1e6;
        uint256 amtB = uint256(depositB) * 1e6;

        vm.prank(traderA);
        margin.depositCollateral(address(usdc), amtA);

        vm.prank(traderB);
        margin.depositCollateral(address(usdc), amtB);

        uint256 totalVaultBalance = usdc.balanceOf(address(margin));
        uint256 recordA = margin.getCollateralBalance(traderA, address(usdc));
        uint256 recordB = margin.getCollateralBalance(traderB, address(usdc));

        assertEq(totalVaultBalance, recordA + recordB);
        assertGe(totalVaultBalance, amtA + amtB);
    }

    /// @notice Invariant 2: Open interest tracking integrity across randomized position entries.
    function testFuzz_Invariant_OpenInterestConsistency(uint16 longSizeInt, uint16 shortSizeInt) public {
        vm.assume(longSizeInt >= 1 && longSizeInt <= 50);
        vm.assume(shortSizeInt >= 1 && shortSizeInt <= 50);

        uint256 longSize = uint256(longSizeInt) * WAD;
        uint256 shortSize = uint256(shortSizeInt) * WAD;

        vm.prank(traderA);
        margin.depositCollateral(address(usdc), 200_000 * 1e6);

        vm.prank(traderB);
        margin.depositCollateral(address(usdc), 200_000 * 1e6);

        // Open Long on trader A
        vm.prank(traderA);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, longSize, type(uint256).max, IHyperionTypes.MarginMode.CROSS
        );

        // Open Short on trader B
        vm.prank(traderB);
        clearingHouse.openPosition(MARKET_ID, IHyperionTypes.Side.SHORT, shortSize, 0, IHyperionTypes.MarginMode.CROSS);

        (uint256 longOI, uint256 shortOI) = clearingHouse.getOpenInterest(MARKET_ID);
        assertEq(longOI, longSize);
        assertEq(shortOI, shortSize);
    }

    /// @notice Invariant 3: Dutch auction price must monotonically decay and remain non-negative.
    function testFuzz_Invariant_DutchAuctionMonotonicity(uint16 timeElapsed) public {
        vm.assume(timeElapsed <= 900); // within 15 min duration

        vm.prank(traderA);
        margin.depositCollateral(address(usdc), 2_000 * 1e6);

        vm.prank(traderA);
        clearingHouse.openPosition(
            MARKET_ID, IHyperionTypes.Side.LONG, 12 * WAD, 2200 * WAD, IHyperionTypes.MarginMode.CROSS
        );

        // Dump price to trigger liquidation
        vm.prank(address(clearingHouse));
        vamm.executeSwap(IHyperionTypes.Side.SHORT, 60 * WAD);

        uint256 auctionId = liquidator.startDutchAuction(traderA, MARKET_ID);
        uint256 price0 = liquidator.getDutchAuctionCurrentPrice(auctionId);

        vm.warp(block.timestamp + uint256(timeElapsed));
        uint256 priceT = liquidator.getDutchAuctionCurrentPrice(auctionId);

        // For long liquidation (selling base), price descends
        assertLe(priceT, price0);
        assertGt(priceT, 0); // Always strictly positive
    }

    /// @notice Invariant 4: Transient storage locks and states must reset cleanly between frames.
    function test_Invariant_ZeroResidualTransientStorage() public view {
        assertFalse(TransientStorage.isLocked());
        assertFalse(TransientStorage.isFlashActive());
        assertEq(TransientStorage.getTransientBalance(traderA, MARKET_ID), 0);
    }
}
