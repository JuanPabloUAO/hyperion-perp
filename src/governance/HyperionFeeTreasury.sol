// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";
import {WadRayMath} from "../libraries/WadRayMath.sol";
import {TransientStorage} from "../libraries/TransientStorage.sol";

/**
 * @title HyperionFeeTreasury
 * @notice Protocol revenue distribution vault splitting fees between stakers, insurance, and growth.
 * @dev Enforces automated multi-recipient yield waterfalls and tracks cumulative distributions.
 */
contract HyperionFeeTreasury is IHyperionTypes {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    // =========================================================================
    // IMMUTABLES & CONSTANTS
    // =========================================================================

    address public immutable owner;
    uint256 internal constant WAD = 1e18;

    // Split shares (in Wad: 1e18 = 100%)
    uint256 public constant STAKER_SHARE = 0.5e18; // 50%
    uint256 public constant INSURANCE_SHARE = 0.3e18; // 30%
    uint256 public constant DEV_SHARE = 0.2e18; // 20%

    // =========================================================================
    // STATE
    // =========================================================================

    address public stakerVault;
    address public insuranceFund;
    address public devTreasury;

    // Token => Total fees collected
    mapping(address => uint256) public totalFeesCollected;
    // Token => Total fees distributed
    mapping(address => uint256) public totalFeesDistributed;

    // =========================================================================
    // EVENTS
    // =========================================================================

    event FeeReceived(address indexed token, address indexed from, uint256 amount);
    event FeesDistributed(address indexed token, uint256 stakerAmount, uint256 insuranceAmount, uint256 devAmount);
    event RecipientsUpdated(address stakerVault, address insuranceFund, address devTreasury);

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

    constructor(address _owner, address _stakerVault, address _insuranceFund, address _devTreasury) {
        if (_owner == address(0)) revert ZeroAddress();
        owner = _owner;
        stakerVault = _stakerVault;
        insuranceFund = _insuranceFund;
        devTreasury = _devTreasury;
    }

    // =========================================================================
    // CONFIGURATION
    // =========================================================================

    function setRecipients(address _stakerVault, address _insuranceFund, address _devTreasury) external onlyOwner {
        if (_stakerVault == address(0) || _insuranceFund == address(0) || _devTreasury == address(0)) {
            revert ZeroAddress();
        }
        stakerVault = _stakerVault;
        insuranceFund = _insuranceFund;
        devTreasury = _devTreasury;

        emit RecipientsUpdated(_stakerVault, _insuranceFund, _devTreasury);
    }

    // =========================================================================
    // REVENUE DISTRIBUTION
    // =========================================================================

    /**
     * @notice Receives fee tokens from protocol components.
     */
    function recordFee(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        totalFeesCollected[token] += amount;
        emit FeeReceived(token, msg.sender, amount);
    }

    /**
     * @notice Distributes accumulated balance of a fee token according to fixed waterfall ratios.
     */
    function distributeFees(address token) external nonReentrant {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();

        uint256 stakerAmount = balance.wadMul(STAKER_SHARE);
        uint256 insuranceAmount = balance.wadMul(INSURANCE_SHARE);
        uint256 devAmount = balance - stakerAmount - insuranceAmount;

        totalFeesDistributed[token] += balance;

        if (stakerAmount > 0 && stakerVault != address(0)) {
            IERC20(token).safeTransfer(stakerVault, stakerAmount);
        }
        if (insuranceAmount > 0 && insuranceFund != address(0)) {
            IERC20(token).safeTransfer(insuranceFund, insuranceAmount);
        }
        if (devAmount > 0 && devTreasury != address(0)) {
            IERC20(token).safeTransfer(devTreasury, devAmount);
        }

        emit FeesDistributed(token, stakerAmount, insuranceAmount, devAmount);
    }
}
