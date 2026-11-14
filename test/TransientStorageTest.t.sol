// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransientStorage} from "../src/libraries/TransientStorage.sol";
import {IHyperionTypes} from "../src/interfaces/IHyperionTypes.sol";

contract TransientStorageHarness {
    function testLockCycle() external returns (bool lockedDuring, bool unlockedAfter) {
        TransientStorage.lock();
        lockedDuring = TransientStorage.isLocked();
        TransientStorage.unlock();
        unlockedAfter = !TransientStorage.isLocked();
    }

    function reentrantCall() external {
        TransientStorage.lock();
        this.reentrantStep();
    }

    function reentrantStep() external {
        TransientStorage.lock();
    }

    function testFlashCycle() external returns (bool activeDuring, bool inactiveAfter) {
        TransientStorage.enterFlashContext();
        activeDuring = TransientStorage.isFlashActive();
        TransientStorage.exitFlashContext();
        inactiveAfter = !TransientStorage.isFlashActive();
    }

    function testTransientBalanceCycle(address account, uint256 marketId, int256 delta) external returns (bool ok) {
        TransientStorage.setTransientBalance(account, marketId, delta);
        int256 stored = TransientStorage.getTransientBalance(account, marketId);
        TransientStorage.clearTransientBalance(account, marketId);
        int256 cleared = TransientStorage.getTransientBalance(account, marketId);
        ok = (stored == delta && cleared == 0);
    }
}

contract TransientStorageTest is Test {
    TransientStorageHarness internal harness;

    function setUp() public {
        harness = new TransientStorageHarness();
    }

    function test_TransientLock_NormalCycle() public {
        (bool lockedDuring, bool unlockedAfter) = harness.testLockCycle();
        assertTrue(lockedDuring);
        assertTrue(unlockedAfter);
    }

    function test_TransientLock_RevertOnReentrancy() public {
        vm.expectRevert(IHyperionTypes.ReentrancyGuardTriggered.selector);
        harness.reentrantCall();
    }

    function test_FlashContextCycle() public {
        (bool activeDuring, bool inactiveAfter) = harness.testFlashCycle();
        assertTrue(activeDuring);
        assertTrue(inactiveAfter);
    }

    function test_TransientBalance_ReadWrite() public {
        address user = address(0xCAFE);
        uint256 marketId = 1;
        bool ok = harness.testTransientBalanceCycle(user, marketId, -500e18);
        assertTrue(ok);
    }
}
