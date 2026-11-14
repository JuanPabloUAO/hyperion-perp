// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IHyperionTypes} from "../interfaces/IHyperionTypes.sol";

/**
 * @title TransientStorage
 * @notice Cancun EIP-1153 transient storage wrapper for gas-efficient reentrancy locks and flash margin accounting.
 * @dev Uses assembly tstore / tload opcodes to store state scoped strictly to the current transaction frame.
 */
library TransientStorage {
    // Keccak256 slot hashes for transient variables
    // keccak256("hyperion.transient.reentrancy.guard")
    bytes32 internal constant REENTRANCY_GUARD_SLOT =
        0x7896d859b3f3dc335431fa8efd9943fcf35fc2b7d4dcf9c82c68e00192d1a3c1;

    // keccak256("hyperion.transient.flash.active")
    bytes32 internal constant FLASH_ACTIVE_SLOT = 0xa9b33a5cfebec1ea74d3f3f9828e82ea36f7e02b740751e18d6e32f50bf93c99;

    /**
     * @notice Acquires transient reentrancy lock for the executing contract.
     * @dev Reverts if lock is already held.
     */
    function lock() internal {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        uint256 status;
        assembly {
            status := tload(slot)
        }
        if (status != 0) revert IHyperionTypes.ReentrancyGuardTriggered();
        assembly {
            tstore(slot, 1)
        }
    }

    /**
     * @notice Releases transient reentrancy lock.
     */
    function unlock() internal {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        assembly {
            tstore(slot, 0)
        }
    }

    /**
     * @notice Returns true if reentrancy lock is currently held.
     */
    function isLocked() internal view returns (bool locked) {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        uint256 status;
        assembly {
            status := tload(slot)
        }
        return status != 0;
    }

    /**
     * @notice Enters a flash-margin context allowing temporary undercollateralization within transaction.
     */
    function enterFlashContext() internal {
        bytes32 slot = FLASH_ACTIVE_SLOT;
        assembly {
            tstore(slot, 1)
        }
    }

    /**
     * @notice Exits flash-margin context.
     */
    function exitFlashContext() internal {
        bytes32 slot = FLASH_ACTIVE_SLOT;
        assembly {
            tstore(slot, 0)
        }
    }

    /**
     * @notice Checks whether currently executing within a flash-margin transaction context.
     */
    function isFlashActive() internal view returns (bool active) {
        bytes32 slot = FLASH_ACTIVE_SLOT;
        uint256 status;
        assembly {
            status := tload(slot)
        }
        return status != 0;
    }

    /**
     * @notice Sets transient balance credit/debit for an account.
     */
    function setTransientBalance(address account, uint256 marketId, int256 delta) internal {
        bytes32 slot = keccak256(abi.encodePacked("hyperion.transient.balance", account, marketId));
        assembly {
            tstore(slot, delta)
        }
    }

    /**
     * @notice Gets transient balance credit/debit for an account.
     */
    function getTransientBalance(address account, uint256 marketId) internal view returns (int256 delta) {
        bytes32 slot = keccak256(abi.encodePacked("hyperion.transient.balance", account, marketId));
        assembly {
            delta := tload(slot)
        }
    }

    /**
     * @notice Clears transient balance credit/debit for an account back to zero.
     */
    function clearTransientBalance(address account, uint256 marketId) internal {
        bytes32 slot = keccak256(abi.encodePacked("hyperion.transient.balance", account, marketId));
        assembly {
            tstore(slot, 0)
        }
    }
}
