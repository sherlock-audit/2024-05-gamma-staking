// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import {LockedBalance} from '../src/interfaces/ILock.sol';
import {LockList} from "../src/libraries/LockList.sol";

/// @title Test suite for the LockList library
/// @dev Provides comprehensive tests for adding and removing locks in the LockList library.
contract LockListTest is Test {
    LockList lockList;
    address deployer;
    address user1;
    address user2;
    address user3;

    /// @notice Sets up the test by deploying the LockList and initializing test addresses
    function setUp() public {
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);
        deployer = vm.addr(9999999);
        uint256 forkId = vm.createFork("https://eth-mainnet.g.alchemy.com/v2/VZH1EtzO3RVWYSXs523zfhFzlO6KHnr6");
        vm.selectFork(forkId);

        vm.startPrank(deployer);
        lockList = new LockList(deployer);
        // Ownership and additional setups could be detailed here if necessary
        vm.stopPrank();
    }

    /// @notice Tests the addition of multiple locks to the LockList for a single user
    /// @dev Iterates through a loop to add locks and then checks that all locks were added correctly
    function testAddAndUpdate() public {
        vm.startPrank(deployer);
        uint256 i;
        for (i; i < 10; i++) {
            LockedBalance memory lockedBalance = LockedBalance({
                lockId: 0, // Note: Lock ID should typically be handled inside the addToList to ensure uniqueness
                amount: 100,
                unlockTime: i,
                multiplier: i + 1,
                lockTime: i + 2,
                lockPeriod: 0,
                exitedLate: false
            });
            lockList.addToList(user1, lockedBalance);
        }

        LockedBalance[] memory locks = lockList.getLocks(user1, 0, 10);
        assertEq(locks.length, 10);
        for (i = 0; i < 10; i++) {
            assertEq(locks[i].lockId, i); 
            assertEq(locks[i].amount, 100);
            assertEq(locks[i].unlockTime, i);
            assertEq(locks[i].multiplier, i + 1);
            assertEq(locks[i].lockTime, i + 2);
        }

        (uint256 lockedAmount, ,) = lockList.lockedBalances(user1, 0, 10);
        assertEq(lockedAmount, 100);
        uint256 lockCount = lockList.lockCount(user1);
        assertEq(lockCount, 10);

        lockList.updateUnlockTime(user1, 0, 1000);
        LockedBalance memory lock = lockList.getLockById(user1, 0);
        assertEq(lock.unlockTime, 1000);

        vm.expectRevert();
        lockList.updateUnlockTime(user1, 100, 0);
    }

    /// @notice Tests the removal of a lock from the LockList and checks the integrity of the list post-removal
    /// @dev Adds locks to two users, removes a lock from one user, and checks that the removal was processed correctly. 
    ///      lockId's 0 - 19 should be created where user1 has 10 even numbers and user 2 has 10 odd numbers.
    function testRemove() public {
        vm.startPrank(deployer);
        uint256 i;
        for (i; i < 10; i++) {
            LockedBalance memory lockedBalance = LockedBalance({
                lockId: 0, 
                amount: 100,
                unlockTime: i,
                multiplier: i + 1,
                lockTime: i + 2,
                lockPeriod: 0,
                exitedLate: false
            });
            LockedBalance memory lockedBalanceForUser2 = LockedBalance({
                lockId: 0, 
                amount: 100,
                unlockTime: i,
                multiplier: i + 1,
                lockTime: i + 2,
                lockPeriod: 0,
                exitedLate: false
            });
            lockList.addToList(user1, lockedBalance);
            lockList.addToList(user2, lockedBalanceForUser2);
        }

        lockList.removeFromList(user2, 15); // Remove lock 15 from user2
        uint256 lockCount = lockList.lockCount(user2);
        assertEq(lockCount, 9); // This assumes lock 15 was correctly indexed 
        LockedBalance memory lockForUser2 = lockList.getLock(user2, 7); // Checking if locks still align post-removal
        assertEq(lockForUser2.lockId, 19);
    }
}
