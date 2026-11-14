// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {HyperionMargin} from "../src/core/HyperionMargin.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract HyperionMarginTest is Test {
    HyperionMargin internal margin;
    MockERC20 internal usdc;
    MockERC20 internal weth;

    address internal owner = address(0x044E);
    address internal trader = address(0x78AD);
    address internal clearingHouse = address(0xC1EA);
    address internal liquidator = address(0x1100);
    address internal oracleRelay = address(0x08AC);

    uint256 internal constant WAD = 1e18;

    function setUp() public {
        vm.startPrank(owner);
        margin = new HyperionMargin(owner);

        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        margin.setSystemAddresses(clearingHouse, liquidator, oracleRelay);

        // Configure USDC with 100% haircut (1.0 Wad), 10M cap
        margin.configureCollateral(address(usdc), 6, 1.0e18, 10_000_000 * 1e6, true);
        // Configure WETH with 90% haircut (0.9 Wad), 10K cap
        margin.configureCollateral(address(weth), 18, 0.9e18, 10_000 * 1e18, true);

        vm.stopPrank();

        // Mint tokens to trader
        usdc.mint(trader, 50_000 * 1e6); // 50,000 USDC
        weth.mint(trader, 10 * 1e18); // 10 WETH

        vm.prank(trader);
        usdc.approve(address(margin), type(uint256).max);

        vm.prank(trader);
        weth.approve(address(margin), type(uint256).max);
    }

    function test_DepositCollateral_USDC() public {
        vm.prank(trader);
        uint256 credit = margin.depositCollateral(address(usdc), 10_000 * 1e6);

        // 10,000 USDC * 100% haircut = 10,000 Wad
        assertEq(credit, 10_000 * WAD);
        assertEq(margin.getCollateralBalance(trader, address(usdc)), 10_000 * 1e6);
        assertEq(margin.getTotalCollateralValue(trader), 10_000 * WAD);
    }

    function test_DepositCollateral_WETH_Haircut() public {
        vm.prank(trader);
        uint256 credit = margin.depositCollateral(address(weth), 10 * 1e18);

        // 10 WETH * 90% haircut = 9 Wad
        assertEq(credit, 9 * WAD);
        assertEq(margin.getTotalCollateralValue(trader), 9 * WAD);
    }

    function test_WithdrawCollateral_SufficientMargin() public {
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 10_000 * 1e6);

        vm.prank(trader);
        margin.withdrawCollateral(address(usdc), 4_000 * 1e6);

        assertEq(margin.getCollateralBalance(trader, address(usdc)), 6_000 * 1e6);
        assertEq(margin.getTotalCollateralValue(trader), 6_000 * WAD);
    }

    function test_WithdrawCollateral_RevertInsufficientBalance() public {
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 1_000 * 1e6);

        vm.prank(trader);
        vm.expectRevert(IHyperionTypes.InsufficientCollateral.selector);
        margin.withdrawCollateral(address(usdc), 2_000 * 1e6);
    }

    function test_SettleRealizedPnL() public {
        vm.prank(trader);
        margin.depositCollateral(address(usdc), 10_000 * 1e6);

        // ClearingHouse settles a $2,000 profit
        vm.prank(clearingHouse);
        margin.settleRealizedPnL(trader, 2000 * int256(WAD));

        assertEq(margin.getAccountEquity(trader), 12_000 * int256(WAD));

        // ClearingHouse settles a $5,000 loss
        vm.prank(clearingHouse);
        margin.settleRealizedPnL(trader, -5000 * int256(WAD));

        assertEq(margin.getAccountEquity(trader), 7_000 * int256(WAD));
    }
}
