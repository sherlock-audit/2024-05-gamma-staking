// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "./Setup.sol";

contract PenaltyCalculations is Test, Setup {


    function testPenaltyCalculationWithinLockPeriod() public {
        vm.prank(user1);
        lock.stake(100e18, user1, 0);
        vm.prank(deployer);
        lock.setDefaultRelockTime(5);
        vm.warp(block.timestamp + 9); // warp 9 seconds into the future.  Time remaining on user1's stake = 10 - (9) % 10 = 1 seconds
        // user1's lock duration is 10 secs and 9 seconds passed
        // timePenaltyFraction: 35%
        // basePenaltyPercentage: 15%
        // Formula: remainSecs / durationSecs * timePenaltyFraction + basePenaltyPercentage
        // 1 / 10 * 35% + 15% = 18.5%
        // penaltyAmount = 100 * 18.5% = 18.5% of 100 = 18.5
        LockedBalance memory lockedBalance = lock.locklist().getLock(user1, 0);
        uint256 user1BalanceBefore = _stakingToken.balanceOf(user1);
        vm.prank(user1);
        lock.earlyExitById(lockedBalance.lockId);
        uint256 user1BalanceAfter = _stakingToken.balanceOf(user1);
        assertEq(user1BalanceBefore + (100e18 - 185e17), user1BalanceAfter);

        // lock penalty reward for exact amount of time passed.  User should have been relocked at the default rate given that the default rate is 5 seconds and lockTime is 10 seconds. He should take the max penalty of 50%.
        vm.prank(user1);
        lock.stake(50e18, user1, 0);
        vm.warp(block.timestamp + 10); 
        lockedBalance = lock.locklist().getLock(user1, 0);
        user1BalanceBefore = _stakingToken.balanceOf(user1);
        vm.prank(user1);
        // Formula: remainSecs / defaultLockTime * timePenaltyFraction + basePenaltyPercentage
        // remainSecs should be defaultRelockTime
        // 5 / 5 * 35% + 15% = 50% * 50e18 = 25e18
        lock.earlyExitById(lockedBalance.lockId);
        user1BalanceAfter = _stakingToken.balanceOf(user1);
        assertEq(user1BalanceBefore + (50e18 - 25e18), user1BalanceAfter);

        // lock penalty when more than the original lock time has passed and the default relock time is less than the original.  User should have been relocked at the default rate of 5 seconds.  He should take 1/5 of the time penalty given that he's 4/5 of the way thru the default lock period.
        vm.prank(user1);
        lock.stake(50e18, user1, 0);
        vm.warp(block.timestamp + 14); 
        lockedBalance = lock.locklist().getLock(user1, 0);
        user1BalanceBefore = _stakingToken.balanceOf(user1);
        vm.prank(user1);
        // when unlock time overpassed, remainSec = (5 - (unlockTime - block.timestamp)) % duration = 1
        // Formula: remainSecs / defaultRelockTime * timePenaltyFraction + basePenaltyPercentage
        // remainSecs should be defaultRelockTime
        // (5-4) / 5 * 35% + 15% = 36% * 50e18 = 11e18
        lock.earlyExitById(lockedBalance.lockId);
        user1BalanceAfter = _stakingToken.balanceOf(user1);
        assertEq(user1BalanceBefore + (50e18 - 11e18), user1BalanceAfter);

        // lock penalty when more than the original lock time has passed and the default relock time is greater than the original.  User should have been relocked at his own relock time of 10 seconds.
        vm.prank(deployer);
        lock.setDefaultRelockTime(30); // 30 seconds default relockTime is greater than the users 10 seconds.  User should always be relocked at the lesser of his own time or relockTime.  
        vm.prank(user1);
        lock.stake(100e18, user1, 0);
        vm.warp(block.timestamp + 14); //14 seconds have passed
        lockedBalance = lock.locklist().getLock(user1, 0);
        user1BalanceBefore = _stakingToken.balanceOf(user1);
        vm.prank(user1);
        // when unlock time overpassed, remainSec = (10 - (unlockTime - block.timestamp)) % 10 = 6
        // Formula: remainSecs / defaultRelockTime * timePenaltyFraction + basePenaltyPercentage
        // remainSecs should be defaultRelockTime
        // (6) / 10 * 35% + 15% = 36% * 100e18 = 36e18
        lock.earlyExitById(lockedBalance.lockId);
        user1BalanceAfter = _stakingToken.balanceOf(user1);
        assertEq(user1BalanceBefore + (100e18 - 36e18), user1BalanceAfter);




    }


}
