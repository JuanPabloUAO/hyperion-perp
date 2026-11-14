// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionLiquidator} from "../interfaces/IHyperionLiquidator.sol";
import {IHyperionClearingHouse} from "../interfaces/IHyperionClearingHouse.sol";
import {IHyperionMargin} from "../interfaces/IHyperionMargin.sol";
import {IHyperionVAMM} from "../interfaces/IHyperionVAMM.sol";
import {IHyperionInsuranceFund} from "../interfaces/IHyperionInsuranceFund.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {SignedMath} from "../libraries/SignedMath.sol";
import {TransientStorage} from "../libraries/TransientStorage.sol";

/**
 * @title HyperionLiquidator
 * @notice Multi-tier liquidation engine safeguarding perpetual exchange solvency.
 * @dev Implements Tier 1 soft liquidation, Tier 2 continuous Dutch auctions, and Tier 3 insurance takeovers.
 */
contract HyperionLiquidator is IHyperionLiquidator {
    using WadRayMath for uint256;
    using SignedMath for int256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    address public immutable owner;
    address public clearingHouse;
    address public marginEngine;
    address public insuranceFund;

    uint256 internal constant WAD = 1e18;
    uint256 public constant TIER1_HEALTH_THRESHOLD = 1e18; // 100% (MMR threshold)
    uint256 public constant TIER2_HEALTH_THRESHOLD = 0.8e18; // 80% (Auction threshold)
    uint256 public constant DEFAULT_AUCTION_DURATION = 900; // 15 minutes

    // =========================================================================
    // STATE VARIABLES
    // =========================================================================

    // Auction ID counter
    uint256 public nextAuctionId = 1;

    // Auction storage: Auction ID => DutchAuction
    mapping(uint256 => DutchAuction) public dutchAuctions;

    // Active auction tracker: Account => Market ID => Auction ID (0 if none)
    mapping(address => mapping(uint256 => uint256)) public activeAuctionId;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier nonReentrant() {
        TransientStorage.lock();
        _;
        TransientStorage.unlock();
    }

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
    }

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    function setSystemAddresses(address _clearingHouse, address _marginEngine, address _insuranceFund)
        external
        onlyOwner
    {
        if (_clearingHouse == address(0) || _marginEngine == address(0) || _insuranceFund == address(0)) {
            revert ZeroAddress();
        }
        clearingHouse = _clearingHouse;
        marginEngine = _marginEngine;
        insuranceFund = _insuranceFund;
    }

    // =========================================================================
    // STATUS EVALUATION
    // =========================================================================

    /// @inheritdoc IHyperionLiquidator
    function checkLiquidationStatus(address account)
        public
        view
        override
        returns (LiquidationTier tier, uint256 healthFactor)
    {
        healthFactor = IHyperionMargin(marginEngine).getHealthFactor(account);
        int256 equity = IHyperionMargin(marginEngine).getAccountEquity(account);

        if (equity <= 0) {
            return (LiquidationTier.TIER3_INSURANCE_TAKEOVER, healthFactor);
        } else if (healthFactor < TIER2_HEALTH_THRESHOLD) {
            return (LiquidationTier.TIER2_DUTCH_AUCTION, healthFactor);
        } else if (healthFactor < TIER1_HEALTH_THRESHOLD) {
            return (LiquidationTier.TIER1_SOFT, healthFactor);
        } else {
            return (LiquidationTier.NONE, healthFactor);
        }
    }

    // =========================================================================
    // TIER 1: SOFT LIQUIDATION
    // =========================================================================

    /// @inheritdoc IHyperionLiquidator
    function executeSoftLiquidation(address trader, uint256 marketId)
        external
        override
        nonReentrant
        returns (uint256 liquidatedSize, uint256 penaltyFee)
    {
        (LiquidationTier tier,) = checkLiquidationStatus(trader);
        if (tier == LiquidationTier.NONE) revert AccountHealthy();

        Position memory pos = IHyperionClearingHouse(clearingHouse).getPosition(trader, marketId);
        if (pos.size == 0) revert PositionNotFound();

        // Liquidate 50% partial close factor
        liquidatedSize = pos.size / 2;
        if (liquidatedSize == 0) liquidatedSize = pos.size;

        MarketConfig memory cfg = IHyperionClearingHouse(clearingHouse).getMarketConfig(marketId);

        // Counter-swap on vAMM
        Side exitSide = pos.side == Side.LONG ? Side.SHORT : Side.LONG;
        (uint256 quoteReceived, uint256 executionPrice) = IHyperionVAMM(cfg.vamm).executeSwap(exitSide, liquidatedSize);

        // Calculate liquidation penalty
        penaltyFee = quoteReceived.wadMul(cfg.liquidationPenalty);
        uint256 insuranceSplit = penaltyFee.wadMul(cfg.liquidationFeeSplit);
        uint256 keeperReward = penaltyFee - insuranceSplit;

        // Apply penalty to margin engine
        IHyperionMargin(marginEngine).settleRealizedPnL(trader, -int256(penaltyFee));
        // Credit keeper reward
        IHyperionMargin(marginEngine).settleRealizedPnL(msg.sender, int256(keeperReward));

        // Reduce position in clearinghouse
        IHyperionClearingHouse(clearingHouse).reducePositionForLiquidation(trader, marketId, liquidatedSize);

        emit SoftLiquidationExecuted(msg.sender, trader, marketId, liquidatedSize, executionPrice, penaltyFee);
    }

    // =========================================================================
    // TIER 2: CONTINUOUS DUTCH AUCTION
    // =========================================================================

    /// @inheritdoc IHyperionLiquidator
    function startDutchAuction(address trader, uint256 marketId)
        external
        override
        nonReentrant
        returns (uint256 auctionId)
    {
        (LiquidationTier tier,) = checkLiquidationStatus(trader);
        if (tier != LiquidationTier.TIER2_DUTCH_AUCTION && tier != LiquidationTier.TIER3_INSURANCE_TAKEOVER) {
            revert AccountHealthy();
        }

        Position memory pos = IHyperionClearingHouse(clearingHouse).getPosition(trader, marketId);
        if (pos.size == 0) revert PositionNotFound();

        if (activeAuctionId[trader][marketId] != 0) {
            uint256 existingId = activeAuctionId[trader][marketId];
            if (!dutchAuctions[existingId].isSettled) revert AuctionAlreadySettled();
        }

        MarketConfig memory cfg = IHyperionClearingHouse(clearingHouse).getMarketConfig(marketId);
        uint256 spotPrice = IHyperionVAMM(cfg.vamm).getSpotPrice();

        // Dutch price decay:
        // For LONG position liquidation (selling base): start price = 105% spot, end price = 90% spot
        // For SHORT position liquidation (buying base): start price = 95% spot, end price = 110% spot
        uint256 startPrice;
        uint256 endPrice;

        if (pos.side == Side.LONG) {
            startPrice = spotPrice.wadMul(1.05e18);
            endPrice = spotPrice.wadMul(0.9e18);
        } else {
            startPrice = spotPrice.wadMul(0.95e18);
            endPrice = spotPrice.wadMul(1.1e18);
        }

        auctionId = nextAuctionId++;
        dutchAuctions[auctionId] = DutchAuction({
            auctionId: auctionId,
            marketId: marketId,
            trader: trader,
            side: pos.side,
            sizeToLiquidate: pos.size,
            bankruptPrice: pos.entryPrice,
            startPrice: startPrice,
            endPrice: endPrice,
            startTime: block.timestamp,
            duration: DEFAULT_AUCTION_DURATION,
            filledSize: 0,
            isSettled: false
        });

        activeAuctionId[trader][marketId] = auctionId;

        emit DutchAuctionStarted(auctionId, trader, marketId, pos.size, startPrice, endPrice, DEFAULT_AUCTION_DURATION);
    }

    /// @inheritdoc IHyperionLiquidator
    function getDutchAuctionCurrentPrice(uint256 auctionId) public view override returns (uint256) {
        DutchAuction memory auc = dutchAuctions[auctionId];
        if (auc.startTime == 0) revert AuctionExpired();
        if (auc.isSettled) return auc.endPrice;

        uint256 elapsed = block.timestamp - auc.startTime;
        if (elapsed >= auc.duration) {
            return auc.endPrice;
        }

        // Linear interpolation: P(t) = P_start + (elapsed / duration) * (P_end - P_start)
        if (auc.endPrice >= auc.startPrice) {
            uint256 delta = auc.endPrice - auc.startPrice;
            return auc.startPrice + (delta * elapsed) / auc.duration;
        } else {
            uint256 delta = auc.startPrice - auc.endPrice;
            return auc.startPrice - (delta * elapsed) / auc.duration;
        }
    }

    /// @inheritdoc IHyperionLiquidator
    function bidDutchAuction(uint256 auctionId, uint256 sizeToBuy, uint256 maxAcceptablePrice)
        external
        override
        nonReentrant
        returns (uint256 executionPrice)
    {
        DutchAuction storage auc = dutchAuctions[auctionId];
        if (auc.isSettled) revert AuctionAlreadySettled();
        if (sizeToBuy == 0) revert ZeroAmount();

        uint256 remaining = auc.sizeToLiquidate - auc.filledSize;
        if (sizeToBuy > remaining) {
            sizeToBuy = remaining;
        }

        executionPrice = getDutchAuctionCurrentPrice(auctionId);

        // Price check based on liquidation side
        if (auc.side == Side.LONG) {
            // Buyer is bidding to purchase base: wants low price
            if (executionPrice > maxAcceptablePrice) revert SlippageExceeded();
        } else {
            // Seller is bidding to sell base: wants high price
            if (executionPrice < maxAcceptablePrice) revert SlippageExceeded();
        }

        auc.filledSize += sizeToBuy;
        if (auc.filledSize >= auc.sizeToLiquidate) {
            auc.isSettled = true;
            activeAuctionId[auc.trader][auc.marketId] = 0;
        }

        // Reduce liquidated trader's position
        IHyperionClearingHouse(clearingHouse).reducePositionForLiquidation(auc.trader, auc.marketId, sizeToBuy);

        emit DutchAuctionBid(auctionId, msg.sender, sizeToBuy, executionPrice, auc.sizeToLiquidate - auc.filledSize);
    }

    // =========================================================================
    // TIER 3: INSURANCE TAKEOVER
    // =========================================================================

    /// @inheritdoc IHyperionLiquidator
    function executeInsuranceTakeover(address trader, uint256 marketId)
        external
        override
        nonReentrant
        returns (uint256 badDebtCovered)
    {
        (LiquidationTier tier,) = checkLiquidationStatus(trader);
        if (tier != LiquidationTier.TIER3_INSURANCE_TAKEOVER) revert AccountHealthy();

        Position memory pos = IHyperionClearingHouse(clearingHouse).getPosition(trader, marketId);
        if (pos.size == 0) revert PositionNotFound();

        int256 equity = IHyperionMargin(marginEngine).getAccountEquity(trader);
        if (equity < 0) {
            badDebtCovered = uint256(-equity);
            IHyperionInsuranceFund(insuranceFund).coverDeficit(trader, marketId, badDebtCovered);
            IHyperionMargin(marginEngine).settleRealizedPnL(trader, int256(badDebtCovered));
        }

        // Close out remaining position
        IHyperionClearingHouse(clearingHouse).reducePositionForLiquidation(trader, marketId, pos.size);

        emit InsuranceTakeover(trader, marketId, pos.size, badDebtCovered);
    }
}
