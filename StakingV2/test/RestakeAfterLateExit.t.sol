// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/Lock.sol";
import "../src/mock/MockToken.sol";
import "../src/libraries/locklist.sol";

/// @title Tests for Unlock Calculation of Lock
/// @notice This suite of tests checks the unlock time calculation functionality for various staking scenarios.
/// @dev The tests simulate different staking durations and calculate remaining unlock periods.
contract RestakeAfterLateExit is Test {
    Lock lock;
    LockList locklist;
    address deployer;
    address user1;
    address user2;
    address user3;
    address user4;
    address user5;
    MockToken _stakingToken;
    MockToken _rewardToken;

    uint256[] lockPeriod;
    uint256[] lockMultiplier;
    address[] rewardTokens;

    function setUp() public {
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);
        user4 = vm.addr(4);
        user5 = vm.addr(5);
        deployer = vm.addr(9999999);
        uint256 forkId = vm.createFork("https://eth-mainnet.g.alchemy.com/v2/VZH1EtzO3RVWYSXs523zfhFzlO6KHnr6");
        vm.selectFork(forkId);

        vm.startPrank(deployer);
        lock = new Lock();
        locklist = new LockList(deployer);
        // transfer ownership of locklist
        lock.initialize(address(locklist), 15000, 35000, deployer);
        _stakingToken = new MockToken("stakingToken", "stkToken", 18);
        _rewardToken = new MockToken("rewardToken", "reward", 18);
        rewardTokens.push(address(_rewardToken));

        lock.setStakingToken(address(_stakingToken));
        lock.addReward(address(_rewardToken));
        lockPeriod.push(30 days);
        lockPeriod.push(60 days);
        lockPeriod.push(360 days);
        lockMultiplier.push(1);
        lockMultiplier.push(1);
        lockMultiplier.push(1);
        lock.setLockTypeInfo(lockPeriod, lockMultiplier);
        _stakingToken.mint(user1, 1000e18);
        _stakingToken.mint(user2, 1000e18);
        _stakingToken.mint(user3, 1000e18);
        _stakingToken.mint(user4, 1000e18);
        _stakingToken.mint(user5, 1000e18);
        _rewardToken.mint(deployer, 10000e18);
        lock.setTreasury(address(0x4));
        locklist.transferOwnership(address(lock));
        vm.stopPrank();

        vm.prank(user1);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user2);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user3);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user4);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user5);
        _stakingToken.approve(address(lock), 10000e18);
    }


/// @notice Tests the restakeAfterLateExit function when User A calls exitLateById halfway through his lock period, then regrets his decision, and wants to restake again for 30 days.
/// @dev Additionally tests revert case to ensure that old lock is deleted
function testUserARestakeAfterLateExit() public {
    // User A stakes initially
    vm.prank(user1);
    lock.stake(100e18, user1, 0); // User A stakes with the first lock type

    uint256 initialLockId = 0; // Assuming lockId starts at 0 and increments

    // Advance time to simulate a late exit scenario
    vm.warp(block.timestamp + 15 days); // Simulate passing 15 days

    vm.prank(user1);    
    lock.exitLateById(initialLockId);
    
    // Fetch the lock details after late exit
    LockedBalance memory lockedBalanceAfterExit = lock.locklist().getLockById(user1, initialLockId);
    console.log("exitedLate flag:  ", lockedBalanceAfterExit.exitedLate);
    assertTrue(lockedBalanceAfterExit.exitedLate, "exitLateById should have changed exitedLate to true");

    // Now User A wants to restake the same amount for a new lock period
    vm.prank(user1);
    lock.restakeAfterLateExit(initialLockId, 0); // Restake with the same type index for simplicity in this test

    // Verify the new lock details
    LockedBalance memory newLock = lock.locklist().getLockById(user1, initialLockId + 1); // Assuming new lockId is the next integer
    assertEq(newLock.amount, 100e18, "Restaked amount should match the original staked amount");
    assertEq(newLock.multiplier, 1, "Multiplier should match the original");
    assertFalse(newLock.exitedLate, "New lock should not be marked as exited late");
    assertEq(newLock.lockPeriod, 30 days, "Lock period for the new lock should be reset to 30 days");

    // Check whether old lock removed.  It should revert with WrongLockId().
    vm.expectRevert();
    locklist.getLockById(user1,initialLockId);
}
/// @notice Tests the restakeAfterLateExit function when User 2 tries to restake for a lock period shorter than his current lock period.
function testUserBRestakeAfterLateExit() public {
    // User 2 stakes initially
    vm.prank(deployer);
    lock.setDefaultRelockTime(5 days);
    vm.startPrank(user2);
    lock.stake(100e18, user2, 1); // User 2 stakes with the second lock type which is 60 days

    // Advance time to simulate a late exit scenario
    vm.warp(block.timestamp + 15 days); // Simulate passing 15 days

    lock.exitLateById(0);

    // Now User 2 wants to restake the same amount for a lesser lock period which should revert
    vm.expectRevert("New lock period must be greater than or equal to the current lock period");
    lock.restakeAfterLateExit(0, 0); 
}
/// @notice Tests the restakeAfterLateExit function - whether User 3 can restake for a lock period of 30 days after lateExiting after 400 days.
function testUserCRestakeAfterLateExit() public {
    // User 2 stakes initially
    vm.prank(deployer);
    lock.setDefaultRelockTime(30 days);
    vm.startPrank(user3);
    lock.stake(100e18, user3, 2); // User 2 stakes with the 3rd lock type which is 360 days

    // Advance time to simulate a late exit scenario
    vm.warp(block.timestamp + 400 days); // Simulate passing 400 days

    lock.exitLateById(0);

    // Now User 3 wants to restake the same amount for a lesser lock period which should not revert because he locked for the entirety of his original lockPeriod and the newLockPeriod >= defaultRelockTime
    lock.restakeAfterLateExit(0, 0); 
}
/// @notice Tests the restakeAfterLateExit function - should revert when User 3 tries restake for a lock period of 30 days after lateExiting after 400 days, but default relock time is 45 days.
function testUserCRestakeAfterLateExitForTimeLessThanDefaultRelockPeriod() public {
    // User 3 stakes initially
    vm.prank(deployer);
    lock.setDefaultRelockTime(45 days);
    vm.startPrank(user3);
    lock.stake(100e18, user3, 2); // User 3 stakes with the 3rd lock type which is 360 days

    // Advance time to simulate a late exit scenario
    vm.warp(block.timestamp + 400 days); // Simulate passing 400 days.  There should be 5 days left of the default 45 relock period.

    lock.exitLateById(0);

    // Now User 3 wants to restake the same amount for a lesser lock period which should revert because he's trying to restake for 30 days which is less than the default 45-day relock period
    vm.expectRevert("New lock period must be greater than or equal to the default relock time");
    lock.restakeAfterLateExit(0, 0); 
}



}