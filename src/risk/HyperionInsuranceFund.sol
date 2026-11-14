// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHyperionInsuranceFund} from "../interfaces/IHyperionInsuranceFund.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {TransientStorage} from "../libraries/TransientStorage.sol";

/**
 * @title HyperionInsuranceFund
 * @notice Protocol capital backstop protecting exchange solvency against cascading bankruptcies.
 * @dev Collects liquidation fee splits, absorbs underwater bad debt, and monitors reserve stress levels.
 */
contract HyperionInsuranceFund is IHyperionInsuranceFund {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    address public immutable owner;
    address public immutable settlementToken; // Primary reserve asset (USDC)
    uint8 public immutable settlementDecimals;

    uint256 public constant MIN_STRESS_THRESHOLD = 50_000e18; // $50,000 Wad stress warning level

    // =========================================================================
    // STATE VARIABLES
    // =========================================================================

    address public liquidator;
    address public clearingHouse;

    uint256 public totalDeficitsCovered;
    uint256 public totalReservesDeposited;

    // =========================================================================
    // MODIFIERS
    // =========================================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert UnauthorizedCaller();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != liquidator && msg.sender != clearingHouse && msg.sender != owner) {
            revert UnauthorizedCaller();
        }
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

    constructor(address _owner, address _settlementToken) {
        if (_owner == address(0) || _settlementToken == address(0)) revert ZeroAddress();
        owner = _owner;
        settlementToken = _settlementToken;

        uint8 dec = 18;
        try IERC20Metadata(_settlementToken).decimals() returns (uint8 d) {
            dec = d;
        } catch {}
        settlementDecimals = dec;
    }

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    function setSystemAddresses(address _liquidator, address _clearingHouse) external onlyOwner {
        if (_liquidator == address(0) || _clearingHouse == address(0)) revert ZeroAddress();
        liquidator = _liquidator;
        clearingHouse = _clearingHouse;
    }

    // =========================================================================
    // DEFICIT COVERAGE
    // =========================================================================

    /// @inheritdoc IHyperionInsuranceFund
    function coverDeficit(address trader, uint256 marketId, uint256 deficitAmount)
        external
        override
        onlyAuthorized
        nonReentrant
    {
        if (deficitAmount == 0) revert ZeroAmount();

        uint256 rawDeficit = _toTokenAmount(deficitAmount);
        uint256 rawBalance = IERC20(settlementToken).balanceOf(address(this));
        uint256 amountToCoverRaw;
        uint256 amountToCoverWad;

        if (rawDeficit <= rawBalance) {
            amountToCoverRaw = rawDeficit;
            amountToCoverWad = deficitAmount;
        } else {
            amountToCoverRaw = rawBalance;
            amountToCoverWad = _toWad(rawBalance);
        }

        totalDeficitsCovered += amountToCoverWad;

        if (amountToCoverRaw > 0 && clearingHouse != address(0)) {
            IERC20(settlementToken).safeTransfer(clearingHouse, amountToCoverRaw);
        }

        emit DeficitCovered(trader, marketId, amountToCoverWad);
    }

    /// @inheritdoc IHyperionInsuranceFund
    function depositReserve(address token, uint256 amount) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalReservesDeposited += amount;

        emit ReserveReplenished(msg.sender, token, amount);
    }

    // =========================================================================
    // VIEWS & CONVERSIONS
    // =========================================================================

    function _toTokenAmount(uint256 wadAmount) internal view returns (uint256) {
        if (settlementDecimals < 18) {
            return wadAmount / (10 ** (18 - settlementDecimals));
        } else if (settlementDecimals > 18) {
            return wadAmount * (10 ** (settlementDecimals - 18));
        }
        return wadAmount;
    }

    function _toWad(uint256 tokenAmount) internal view returns (uint256) {
        if (settlementDecimals < 18) {
            return tokenAmount * (10 ** (18 - settlementDecimals));
        } else if (settlementDecimals > 18) {
            return tokenAmount / (10 ** (settlementDecimals - 18));
        }
        return tokenAmount;
    }

    /// @inheritdoc IHyperionInsuranceFund
    function getReserveBalance() public view override returns (uint256) {
        return _toWad(IERC20(settlementToken).balanceOf(address(this)));
    }

    /// @inheritdoc IHyperionInsuranceFund
    function isReserveStressed() external view override returns (bool) {
        return getReserveBalance() < MIN_STRESS_THRESHOLD;
    }
}
