// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "./IHyperionTypes.sol";

/**
 * @title IHyperionRouter
 * @notice Periphery multicall router interface for atomic trading and account operations.
 * @dev Bundles collateral deposit, trade execution, position adjustments, and stop triggers.
 */
interface IHyperionRouter is IHyperionTypes {
    struct DepositAndTradeParams {
        address collateralToken;
        uint256 depositAmount;
        uint256 marketId;
        Side side;
        uint256 baseAmount;
        uint256 maxSlippagePrice;
        MarginMode mode;
    }

    /**
     * @notice Atomically deposits collateral and executes an opening position trade.
     * @param params Parameter struct specifying deposit asset, amount, and order parameters
     * @return positionId Resulting position identifier
     * @return executionPrice Actual execution price attained on vAMM
     */
    function depositAndOpenPosition(DepositAndTradeParams calldata params)
        external
        returns (uint256 positionId, uint256 executionPrice);

    /**
     * @notice Executes multiple calls in a single transaction frame.
     * @param data Array of encoded function call data
     * @return results Array of call result byte responses
     */
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}
