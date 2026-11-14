// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionVAMM
 * @notice Interface for the Virtual Automated Market Maker (vAMM) module.
 * @dev Manages virtual reserves, simulated swap pricing, price impact, and TWAP accumulation.
 */
interface IHyperionVAMM is IHyperionTypes {
    /// @notice Emitted when a virtual swap occurs
    event VirtualSwap(
        address indexed caller, Side side, uint256 baseAmount, uint256 quoteAmount, uint256 spotPriceAfter
    );

    /// @notice Emitted when virtual liquidity is adjusted
    event VirtualLiquidityUpdated(
        uint256 oldVirtualBase, uint256 oldVirtualQuote, uint256 newVirtualBase, uint256 newVirtualQuote
    );

    /// @notice Emitted when fee coefficients are updated
    event FeeTiersUpdated(uint256 takerFee, uint256 makerRebate);

    /**
     * @notice Simulates executing a swap on virtual reserves without altering state.
     * @param side Side of the swap (LONG buys base with quote; SHORT sells base for quote)
     * @param amount Size of base or quote amount according to isExactInput
     * @param isExactInput True if amount is input; false if amount is desired output
     * @return quoteAmount Calculated quote asset quantity transferred
     * @return baseAmount Calculated base asset quantity transferred
     * @return priceAfter Price after hypothetical swap execution (Wad)
     */
    function quoteSwap(Side side, uint256 amount, bool isExactInput)
        external
        view
        returns (uint256 quoteAmount, uint256 baseAmount, uint256 priceAfter);

    /**
     * @notice Executes a virtual swap against the vAMM curve, mutating reserves.
     * @dev Only callable by the authorized ClearingHouse.
     * @param side Side of the swap
     * @param baseAmount Quantity of base asset traded (Wad)
     * @return quoteTransferred Actual quote asset value transacted (Wad)
     * @return executionPrice Volume-weighted execution price (Wad)
     */
    function executeSwap(Side side, uint256 baseAmount)
        external
        returns (uint256 quoteTransferred, uint256 executionPrice);

    /**
     * @notice Returns the current spot price of the base asset in quote asset units.
     * @return spotPrice Wad representation (18 decimals)
     */
    function getSpotPrice() external view returns (uint256 spotPrice);

    /**
     * @notice Calculates the time-weighted average price (TWAP) over a historical lookback interval.
     * @param lookbackWindow Duration in seconds over which to compute TWAP
     * @return twapPrice Wad representation
     */
    function getTWAP(uint32 lookbackWindow) external view returns (uint256 twapPrice);

    /**
     * @notice Adjusts the virtual reserves to align mark price with a target index price or update depth.
     * @dev Only callable by authorized governance or risk controller.
     * @param newBaseReserve New virtual base asset depth (Wad)
     * @param newQuoteReserve New virtual quote asset depth (Wad)
     */
    function setVirtualReserves(uint256 newBaseReserve, uint256 newQuoteReserve) external;

    /**
     * @notice Returns the virtual base and quote reserves.
     */
    function getReserves() external view returns (uint256 virtualBase, uint256 virtualQuote);

    /**
     * @notice Market identifier associated with this vAMM.
     */
    function marketId() external view returns (uint256);
}
