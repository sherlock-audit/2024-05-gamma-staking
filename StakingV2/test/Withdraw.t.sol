// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "./Setup.sol";

/// @title Tests for Withdrawal and Exit Functions in the Lock System
/// @dev This contract tests the withdrawal functionalities for early exits.
contract WithdrawTest is Test, Setup {

    /// @notice Test late exit functionality and the reward accrual when one exits late
    /// @dev Stakes tokens for three users, performs a late exit for user1, ensures that user 1 is able to withdraw after elapsed time, performs late exit for user2, sends reward tokens to the contract, and
    ///      ensures that user2 no longer earns rewards following the late exit
    function testExitLateAndRewards() public {
        // Users stake tokens
        vm.prank(user1);
        lock.stake(100e18, user1, 0);
        vm.prank(user2);
        lock.stake(100e18, user2, 1);
        vm.prank(user3);
        lock.stake(100e18, user3, 2);
        
        // Fetch the first lock for user1 and perform a late exit
        LockedBalance[] memory user1Locks = lockList.getLocks(user1, 0, 10);
        LockedBalance memory user1Lock = lockList.getLockById(user1, user1Locks[0].lockId);
        vm.prank(user1);
        lock.exitLateById(user1Lock.lockId);
        vm.warp(block.timestamp + 30); // Simulate time passage
        
        // Verify if the tokens are correctly unlocked and can be withdrawn
        uint256 user1BalanceBefore = _stakingToken.balanceOf(user1);
        vm.prank(user1);
        lock.withdrawAllUnlockedToken();
        uint256 user1BalanceAfter = _stakingToken.balanceOf(user1);
        assertEq(user1BalanceBefore + 100e18, user1BalanceAfter);


        LockedBalance[] memory user2Locks = lockList.getLocks(user2, 0, 10);
        LockedBalance memory user2Lock = lockList.getLockById(user2, user2Locks[0].lockId);
        vm.prank(user2);
        lock.exitLateById(user2Lock.lockId);

        // Reward distribution
        vm.prank(deployer);
        _rewardToken.transfer(address(lock), 300e18);
        vm.prank(deployer);
        lock.notifyUnseenReward(rewardTokens);

        // Checking initial rewards to ensure late exiter does NOT receive rewards
        vm.prank(user2);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user2), 0, "user2 should no longer accrue rewards after late exit");
        vm.prank(user3);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user3), 300e18, "user3 should receive the entirety of the rewards");
    }
}
