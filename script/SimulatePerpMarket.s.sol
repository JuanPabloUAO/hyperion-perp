// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockPriceFeed} from "../test/mocks/MockPriceFeed.sol";
import {HyperionAccessController} from "../src/governance/HyperionAccessController.sol";
import {HyperionFeeTreasury} from "../src/governance/HyperionFeeTreasury.sol";
import {HyperionOracleRelay} from "../src/oracle/HyperionOracleRelay.sol";
import {HyperionMargin} from "../src/core/HyperionMargin.sol";
import {HyperionClearingHouse} from "../src/core/HyperionClearingHouse.sol";
import {HyperionFundingController} from "../src/core/HyperionFundingController.sol";
import {HyperionInsuranceFund} from "../src/risk/HyperionInsuranceFund.sol";
import {HyperionLiquidator} from "../src/risk/HyperionLiquidator.sol";
import {HyperionVAMM} from "../src/core/HyperionVAMM.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

/**
 * @title SimulatePerpMarket
 * @notice Realistic life-cycle simulation exercising trades, funding, and liquidations.
 */
contract SimulatePerpMarket is Script {
    uint256 internal constant WAD = 1e18;

    function run() external {
        console2.log("=================================================");
        console2.log("Starting Hyperion Perp Market Lifecycle Simulation");
        console2.log("=================================================");

        address owner = address(0xAA11);
        address alice = address(0x1111);
        address keeper = address(0x9999);

        vm.startPrank(owner);

        // 1. Setup Environment
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockPriceFeed ethFeed = new MockPriceFeed(8, 2_000 * 1e8);

        HyperionAccessController access = new HyperionAccessController(owner);
        HyperionFeeTreasury treasury = new HyperionFeeTreasury(owner, address(1), address(2), address(3));
        HyperionOracleRelay oracle = new HyperionOracleRelay(owner, address(access));
        HyperionMargin margin = new HyperionMargin(owner);
        HyperionClearingHouse clearingHouse = new HyperionClearingHouse(owner);
        HyperionFundingController funding = new HyperionFundingController(owner, address(oracle));
        HyperionInsuranceFund insurance = new HyperionInsuranceFund(owner, address(usdc));
        HyperionLiquidator liquidator = new HyperionLiquidator(owner);

        clearingHouse.setSystemAddresses(address(margin), address(funding), address(oracle), address(treasury));
        clearingHouse.setLiquidator(address(liquidator));
        margin.setSystemAddresses(address(clearingHouse), address(liquidator), address(oracle));
        liquidator.setSystemAddresses(address(clearingHouse), address(margin), address(insurance));
        insurance.setSystemAddresses(address(liquidator), address(clearingHouse));

        HyperionVAMM ethVamm =
            new HyperionVAMM(1, address(clearingHouse), owner, 1000 * WAD, 2_000_000 * WAD, 0.0006e18, 0);
        ethVamm.setLiquidator(address(liquidator));
        funding.registerMarketVAMM(1, address(ethVamm));

        oracle.configureFeed(1, address(ethFeed), address(0), 3600);
        margin.configureCollateral(address(usdc), 6, 1.0e18, 50_000_000 * 1e6, true);

        funding.setPIDConfig(
            1,
            IHyperionTypes.PIDConfig({
                kp: 0.1e18,
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
            1, "ETH-PERP", address(ethVamm), 50 * WAD, 0.05e18, 0.02e18, 0.03e18, 0.0006e18, 0, 100_000 * WAD
        );
        usdc.mint(address(insurance), 250_000 * 1e6);
        vm.stopPrank();

        // 2. Fund Accounts
        usdc.mint(alice, 5_000 * 1e6); // $5,000

        // 3. Alice Deposits Margin & Opens 15 ETH Long (High Leverage)
        vm.startPrank(alice);
        usdc.approve(address(margin), type(uint256).max);
        margin.depositCollateral(address(usdc), 1_200 * 1e6);
        (uint256 posId, uint256 execPrice) = clearingHouse.openPosition(
            1, IHyperionTypes.Side.LONG, 15 * WAD, 2_150 * WAD, IHyperionTypes.MarginMode.CROSS
        );
        vm.stopPrank();

        console2.log("Alice Opened Position ID:", posId);
        console2.log("Execution Price ($/ETH):", execPrice / 1e18);
        console2.log("New Spot Price ($/ETH):", ethVamm.getSpotPrice() / 1e18);

        // 4. Time Passes: 8 hours
        vm.warp(block.timestamp + 28800);
        ethFeed.setUpdatedAt(block.timestamp);

        // 5. Update PID Funding Rate
        (int256 fundingRate,) = funding.updateFundingRate(1);
        console2.log("Accrued 8h Funding Rate (Ray):", fundingRate);

        // 6. Simulate Flash Crash: External Dump on vAMM
        vm.prank(address(clearingHouse));
        ethVamm.executeSwap(IHyperionTypes.Side.SHORT, 60 * WAD);

        uint256 crashedSpot = ethVamm.getSpotPrice();
        console2.log("Crashed Spot Price ($/ETH):", crashedSpot / 1e18);

        // 7. Check Alice's Margin Health
        (IHyperionTypes.LiquidationTier tier, uint256 healthRatio) = liquidator.checkLiquidationStatus(alice);
        console2.log("Alice Liquidation Tier:", uint256(tier));
        console2.log("Alice Health Ratio (Wad):", healthRatio);

        // 8. Keeper Executes Soft Liquidation
        vm.prank(keeper);
        (uint256 liquidatedSize, uint256 penalty) = liquidator.executeSoftLiquidation(alice, 1);
        console2.log("Keeper Executed Soft Liquidation!");
        console2.log("Liquidated ETH Size:", liquidatedSize / 1e18);
        console2.log("Penalty Extracted ($):", penalty / 1e18);

        console2.log("=================================================");
        console2.log("Hyperion Perp Market Simulation Completed Successfully");
        console2.log("=================================================");
    }
}
