// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionInsuranceFund
 * @notice Interface for the protocol backstop reserve and bad-debt resolution fund.
 * @dev Collects protocol fees, covers underwater trader deficits, and manages auto-deleveraging (ADL).
 */
interface IHyperionInsuranceFund is IHyperionTypes {
    event DeficitCovered(address indexed trader, uint256 indexed marketId, uint256 amountCovered);
    event ReserveReplenished(address indexed contributor, address indexed token, uint256 amount);
    event AutoDeleveragingTriggered(uint256 indexed marketId, Side side, uint256 targetSize);
    event YieldDistributed(address indexed recipient, uint256 amount);

    /**
     * @notice Absorbs bad debt incurred by a bankrupt trader after total collateral exhaustion.
     * @dev Only callable by authorized ClearingHouse or Liquidator.
     * @param trader Address of bankrupt trader
     * @param marketId Market where deficit occurred
     * @param deficitAmount Amount of deficit denominated in settlement quote asset (Wad)
     */
    function coverDeficit(address trader, uint256 marketId, uint256 deficitAmount) external;

    /**
     * @notice Deposits funds into insurance reserves.
     * @param token Address of reserve asset
     * @param amount Quantity of tokens deposited
     */
    function depositReserve(address token, uint256 amount) external;

    /**
     * @notice Returns total capital reserve valuation available in the insurance fund.
     * @return reserveValue Total reserve valuation in Wad (USD 18-decimals)
     */
    function getReserveBalance() external view returns (uint256 reserveValue);

    /**
     * @notice Checks if the insurance fund is in a stressed state (reserves below threshold).
     * @return isStressed True if insurance capacity is under strain
     */
    function isReserveStressed() external view returns (bool isStressed);
}
