// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionMargin
 * @notice Interface for the collateral and margin management subsystem.
 * @dev Tracks multi-collateral user balances, applies asset haircuts, and computes account solvency.
 */
interface IHyperionMargin is IHyperionTypes {
    event CollateralDeposited(address indexed account, address indexed token, uint256 rawAmount, uint256 creditWad);
    event CollateralWithdrawn(address indexed account, address indexed token, uint256 rawAmount, uint256 creditWad);
    event CollateralAssetConfigured(address indexed token, uint256 haircut, uint256 depositCap, bool isAllowed);
    event MarginAllocated(address indexed account, uint256 indexed marketId, uint256 amountWad);
    event MarginDeallocated(address indexed account, uint256 indexed marketId, uint256 amountWad);

    /**
     * @notice Deposits approved collateral into the margin bank.
     * @param token Address of the ERC-20 token being deposited
     * @param amount Raw amount of tokens deposited
     * @return creditValue Wad equivalent valuation after applying asset haircut
     */
    function depositCollateral(address token, uint256 amount) external returns (uint256 creditValue);

    /**
     * @notice Withdraws collateral from the margin bank if account maintains sufficient free margin.
     * @param token Address of token to withdraw
     * @param amount Raw token amount to withdraw
     */
    function withdrawCollateral(address token, uint256 amount) external;

    /**
     * @notice Returns total raw deposited collateral for an account and token.
     */
    function getCollateralBalance(address account, address token) external view returns (uint256);

    /**
     * @notice Computes total haircut-adjusted collateral value across all deposited assets.
     * @param account Trader account address
     * @return totalCredit Total credit in Wad (USD 18-decimals)
     */
    function getTotalCollateralValue(address account) external view returns (uint256 totalCredit);

    /**
     * @notice Calculates account net equity, accounting for haircut collateral, unrealized PnL, and unsettled funding.
     * @param account Trader account address
     * @return equity Signed equity in Wad (positive = solvent, negative = bankrupt)
     */
    function getAccountEquity(address account) external view returns (int256 equity);

    /**
     * @notice Computes total initial margin requirement (IMR) across all active positions for an account.
     * @param account Trader account address
     * @return totalIMR Total required initial margin in Wad
     */
    function getTotalInitialMargin(address account) external view returns (uint256 totalIMR);

    /**
     * @notice Computes total maintenance margin requirement (MMR) across all active positions for an account.
     * @param account Trader account address
     * @return totalMMR Total required maintenance margin in Wad
     */
    function getTotalMaintenanceMargin(address account) external view returns (uint256 totalMMR);

    /**
     * @notice Computes account free margin available to open new positions or withdraw collateral.
     * @param account Trader account address
     * @return freeMargin Free margin in Wad (0 if equity <= totalIMR)
     */
    function getFreeMargin(address account) external view returns (uint256 freeMargin);

    /**
     * @notice Returns health factor scaled by Wad (1e18 = 100% solvency threshold).
     * @dev HF = Net Equity / Maintenance Margin. HF < 1e18 means position is subject to liquidation.
     * @param account Trader account address
     * @return healthFactor Health factor in Wad (type(uint256).max if no maintenance requirement)
     */
    function getHealthFactor(address account) external view returns (uint256 healthFactor);

    /**
     * @notice Seizes collateral during liquidation or deficit resolution.
     * @dev Only callable by authorized Liquidator or ClearingHouse.
     * @param account Trader losing collateral
     * @param recipient Target address receiving seized collateral
     * @param token Collateral token address
     * @param amount Amount to seize
     */
    function seizeCollateral(address account, address recipient, address token, uint256 amount) external;

    /**
     * @notice Deducts realized loss or funding liability from margin balances.
     * @dev Only callable by ClearingHouse.
     */
    function settleRealizedPnL(address account, int256 pnlDelta) external;
}
