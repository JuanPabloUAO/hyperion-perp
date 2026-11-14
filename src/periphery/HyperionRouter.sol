// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHyperionRouter} from "../interfaces/IHyperionRouter.sol";
import {IHyperionClearingHouse} from "../interfaces/IHyperionClearingHouse.sol";
import {IHyperionMargin} from "../interfaces/IHyperionMargin.sol";
import {TransientStorage} from "../libraries/TransientStorage.sol";

/**
 * @title HyperionRouter
 * @notice Periphery multicall router coordinating atomic deposits, position openings, and execution bundles.
 * @dev Provides multicall execution framing and simplifies frontend/keeper integrations.
 */
contract HyperionRouter is IHyperionRouter {
    using SafeERC20 for IERC20;

    // =========================================================================
    // IMMUTABLES
    // =========================================================================

    address public immutable clearingHouse;
    address public immutable marginEngine;

    // =========================================================================
    // CONSTRUCTOR
    // =========================================================================

    constructor(address _clearingHouse, address _marginEngine) {
        if (_clearingHouse == address(0) || _marginEngine == address(0)) revert ZeroAddress();
        clearingHouse = _clearingHouse;
        marginEngine = _marginEngine;
    }

    // =========================================================================
    // ATOMIC ENTRY
    // =========================================================================

    /// @inheritdoc IHyperionRouter
    function depositAndOpenPosition(DepositAndTradeParams calldata params)
        external
        override
        returns (uint256 positionId, uint256 executionPrice)
    {
        if (params.depositAmount > 0) {
            // Pull collateral token from user to this contract
            IERC20(params.collateralToken).safeTransferFrom(msg.sender, address(this), params.depositAmount);
            // Approve margin engine
            IERC20(params.collateralToken).forceApprove(marginEngine, params.depositAmount);
            // Deposit on behalf of trader (note: margin credit will be assigned to msg.sender)
            IHyperionMargin(marginEngine).depositCollateral(params.collateralToken, params.depositAmount);
        }

        // Open position directly via ClearingHouse
        (positionId, executionPrice) = IHyperionClearingHouse(clearingHouse)
            .openPosition(params.marketId, params.side, params.baseAmount, params.maxSlippagePrice, params.mode);
    }

    // =========================================================================
    // MULTICALL
    // =========================================================================

    /// @inheritdoc IHyperionRouter
    function multicall(bytes[] calldata data) external payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            if (!success) {
                if (result.length > 0) {
                    assembly {
                        let returndata_size := mload(result)
                        revert(add(32, result), returndata_size)
                    }
                } else {
                    revert UnauthorizedCaller();
                }
            }
            results[i] = result;
        }
    }
}
