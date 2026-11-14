// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionLiquidator
 * @notice Interface for the multi-tier liquidation waterfall engine.
 * @dev Supports Tier 1 soft liquidation, Tier 2 continuous Dutch auction liquidation, and Tier 3 insurance takeover.
 */
interface IHyperionLiquidator is IHyperionTypes {
    event SoftLiquidationExecuted(
        address indexed keeper,
        address indexed trader,
        uint256 indexed marketId,
        uint256 liquidatedSize,
        uint256 executionPrice,
        uint256 penaltyPaid
    );

    event DutchAuctionStarted(
        uint256 indexed auctionId,
        address indexed trader,
        uint256 indexed marketId,
        uint256 size,
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration
    );

    event DutchAuctionBid(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 filledSize,
        uint256 executionPrice,
        uint256 remainingSize
    );

    event InsuranceTakeover(
        address indexed trader, uint256 indexed marketId, uint256 liquidatedSize, uint256 deficitCovered
    );

    /**
     * @notice Evaluates liquidation eligibility and tier for an account.
     * @param account Trader account address
     * @return tier Applicable liquidation tier
     * @return healthFactor Current health factor (Wad)
     */
    function checkLiquidationStatus(address account) external view returns (LiquidationTier tier, uint256 healthFactor);

    /**
     * @notice Executes a Tier 1 soft liquidation (partial close up to 50% of position).
     * @param trader Trader being liquidated
     * @param marketId Market identifier
     * @return liquidatedSize Quantity of base asset closed
     * @return penaltyFee Reward penalty distributed
     */
    function executeSoftLiquidation(address trader, uint256 marketId)
        external
        returns (uint256 liquidatedSize, uint256 penaltyFee);

    /**
     * @notice Initiates a Tier 2 Dutch auction liquidation for a dangerously insolvent account.
     * @param trader Insolvent trader address
     * @param marketId Market identifier
     * @return auctionId Unique identifier for the created Dutch auction
     */
    function startDutchAuction(address trader, uint256 marketId) external returns (uint256 auctionId);

    /**
     * @notice Places a bid to purchase underwater inventory from an active Dutch auction.
     * @param auctionId Identifier of active auction
     * @param sizeToBuy Quantity of base contracts bidder wishes to absorb
     * @param maxAcceptablePrice Worst-case execution price acceptable
     * @return executionPrice Actual Dutch auction clearing price attained
     */
    function bidDutchAuction(uint256 auctionId, uint256 sizeToBuy, uint256 maxAcceptablePrice)
        external
        returns (uint256 executionPrice);

    /**
     * @notice Computes current decaying price for a Dutch auction.
     * @param auctionId Auction identifier
     * @return currentPrice Decayed clearing price (Wad)
     */
    function getDutchAuctionCurrentPrice(uint256 auctionId) external view returns (uint256 currentPrice);

    /**
     * @notice Triggers Tier 3 insurance fund takeover for completely bankrupt positions.
     * @param trader Bankrupt trader address
     * @param marketId Market identifier
     * @return badDebtCovered Total deficit absorbed by insurance fund (Wad)
     */
    function executeInsuranceTakeover(address trader, uint256 marketId) external returns (uint256 badDebtCovered);
}
