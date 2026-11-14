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
import {HyperionRouter} from "../src/periphery/HyperionRouter.sol";
import {HyperionPositionToken} from "../src/periphery/HyperionPositionToken.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

/**
 * @title DeployHyperionPerp
 * @notice Production-grade deployment script for Hyperion Perpetual Protocol.
 * @dev Deploys collateral, oracles, state machines, liquidation waterfalls, and vAMM markets.
 */
contract DeployHyperionPerp is Script {
    uint256 internal constant WAD = 1e18;

    // Protocol Deployments
    MockERC20 public usdc;
    MockERC20 public weth;
    MockPriceFeed public ethPriceFeed;
    MockPriceFeed public btcPriceFeed;

    HyperionAccessController public accessController;
    HyperionFeeTreasury public treasury;
    HyperionOracleRelay public oracleRelay;
    HyperionMargin public margin;
    HyperionClearingHouse public clearingHouse;
    HyperionFundingController public fundingController;
    HyperionInsuranceFund public insuranceFund;
    HyperionLiquidator public liquidator;
    HyperionVAMM public ethVamm;
    HyperionVAMM public btcVamm;
    HyperionRouter public router;
    HyperionPositionToken public positionToken;

    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=================================================");
        console2.log("Hyperion Protocol Deployment Initiated");
        console2.log("Deployer:", deployer);
        console2.log("=================================================");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Testnet Mock Tokens & Price Feeds
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // $2,000 ETH feed (8 decimals), $60,000 BTC feed (8 decimals)
        ethPriceFeed = new MockPriceFeed(8, 2_000 * 1e8);
        btcPriceFeed = new MockPriceFeed(8, 60_000 * 1e8);

        // 2. Deploy Access Control & Governance
        accessController = new HyperionAccessController(deployer);
        treasury = new HyperionFeeTreasury(
            deployer,
            address(0x1111111111111111111111111111111111111111), // buyback
            address(0x2222222222222222222222222222222222222222), // stakers
            address(0x3333333333333333333333333333333333333333) // safety fund
        );

        // 3. Deploy Oracle Relay & Risk Engines
        oracleRelay = new HyperionOracleRelay(deployer, address(accessController));
        margin = new HyperionMargin(deployer);
        clearingHouse = new HyperionClearingHouse(deployer);
        fundingController = new HyperionFundingController(deployer, address(oracleRelay));
        insuranceFund = new HyperionInsuranceFund(deployer, address(usdc));
        liquidator = new HyperionLiquidator(deployer);

        // 4. Deploy Periphery & NFT Position Tracking
        router = new HyperionRouter(address(clearingHouse), address(margin));
        positionToken = new HyperionPositionToken(deployer, address(clearingHouse));

        // 5. Inter-contract Wiring
        clearingHouse.setSystemAddresses(
            address(margin), address(fundingController), address(oracleRelay), address(treasury)
        );
        clearingHouse.setLiquidator(address(liquidator));

        margin.setSystemAddresses(address(clearingHouse), address(liquidator), address(oracleRelay));
        liquidator.setSystemAddresses(address(clearingHouse), address(margin), address(insuranceFund));
        insuranceFund.setSystemAddresses(address(liquidator), address(clearingHouse));

        // 6. Deploy Market 1: ETH-PERP vAMM
        // Base: 1,000 ETH, Quote: 2,000,000 USDC -> Initial Spot: $2,000
        ethVamm = new HyperionVAMM(1, address(clearingHouse), deployer, 1_000 * WAD, 2_000_000 * WAD, 0.0006e18, 0);
        ethVamm.setLiquidator(address(liquidator));

        // 7. Deploy Market 2: BTC-PERP vAMM
        // Base: 100 BTC, Quote: 6,000,000 USDC -> Initial Spot: $60,000
        btcVamm = new HyperionVAMM(2, address(clearingHouse), deployer, 100 * WAD, 6_000_000 * WAD, 0.0006e18, 0);
        btcVamm.setLiquidator(address(liquidator));

        // Register vAMMs to funding controller
        fundingController.registerMarketVAMM(1, address(ethVamm));
        fundingController.registerMarketVAMM(2, address(btcVamm));

        // 8. Configure Oracle Price Feeds
        oracleRelay.configureFeed(1, address(ethPriceFeed), address(0), 3600);
        oracleRelay.configureFeed(2, address(btcPriceFeed), address(0), 3600);

        // 9. Configure Collateral Assets in Margin Engine
        // USDC: 100% credit factor, 6 decimals, $50M supply ceiling
        margin.configureCollateral(address(usdc), 6, 1.0e18, 50_000_000 * 1e6, true);
        // WETH: 80% credit factor (20% haircut), 18 decimals, 25,000 WETH ceiling
        margin.configureCollateral(address(weth), 18, 0.8e18, 25_000 * WAD, true);

        // 10. Configure PID Funding Rates
        fundingController.setPIDConfig(
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

        fundingController.setPIDConfig(
            2,
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

        // 11. Register Markets in ClearingHouse
        // ETH-PERP: Max leverage 50x, IMR 5%, MMR 2%, Liq Penalty 3%
        clearingHouse.registerMarket(
            1, "ETH-PERP", address(ethVamm), 50 * WAD, 0.05e18, 0.02e18, 0.03e18, 0.0006e18, 0, 100_000 * WAD
        );
        // BTC-PERP: Max leverage 50x, IMR 5%, MMR 2%, Liq Penalty 3%
        clearingHouse.registerMarket(
            2, "BTC-PERP", address(btcVamm), 50 * WAD, 0.05e18, 0.02e18, 0.03e18, 0.0006e18, 0, 10_000 * WAD
        );

        // 12. Seed Insurance Fund
        usdc.mint(address(insuranceFund), 500_000 * 1e6); // $500,000 backstop reserve

        vm.stopBroadcast();

        console2.log("Deployment Complete!");
        console2.log("USDC:", address(usdc));
        console2.log("WETH:", address(weth));
        console2.log("ClearingHouse:", address(clearingHouse));
        console2.log("MarginEngine:", address(margin));
        console2.log("Liquidator:", address(liquidator));
        console2.log("InsuranceFund:", address(insuranceFund));
        console2.log("ETH-PERP vAMM:", address(ethVamm));
        console2.log("BTC-PERP vAMM:", address(btcVamm));
        console2.log("Router:", address(router));
    }
}
