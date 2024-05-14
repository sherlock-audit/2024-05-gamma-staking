// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "./Setup.sol";

/// @title Deposit Tests for Lock
/// @dev This contract implements tests using Foundry's test framework to simulate various deposit scenarios and reward distributions.
contract DepositTest is Test, Setup {

    /// @notice Tests simple deposit functionality and correct reward allocation
    /// @dev Simulates three users making deposits under different lock types and checks correct reward distribution after rewards are added.
    function testSimpleDeposit() public {
        // Simulating deposits by three different users
        vm.prank(user1);
        lock.stake(100e18, user1, 0);
        vm.prank(user2);
        lock.stake(100e18, user2, 1);
        vm.prank(user3);
        lock.stake(100e18, user3, 2);

        // Distributing rewards to the staking contract
        vm.prank(deployer);
        _rewardToken.transfer(address(lock), 600e18);
        vm.prank(deployer);
        lock.notifyUnseenReward(rewardTokens);

        // Checking that rewards are allocated correctly
        vm.prank(user1);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user1), 100e18);
        vm.prank(user2);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user2), 200e18);
        vm.prank(user3);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user3), 300e18);
    }

    /// @notice Tests deposit functionality with multiple stakes and reward distributions
    /// @dev Simulates multiple stakes and reward distributions to ensure correct calculations of incremental rewards.
    function testDeposit() public {
        // Initial staking by three users
        vm.prank(user1);
        lock.stake(100e18, user1, 0);
        vm.prank(user2);
        lock.stake(100e18, user2, 1);
        vm.prank(user3);
        lock.stake(100e18, user3, 2);

        // First reward distribution
        vm.prank(deployer);
        _rewardToken.transfer(address(lock), 600e18);
        vm.prank(deployer);
        lock.notifyUnseenReward(rewardTokens);

        // Checking initial rewards
        vm.prank(user1);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user1), 100e18);
        vm.prank(user2);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user2), 200e18);
        vm.prank(user3);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user3), 300e18);

        // Additional stakes by user1
        vm.prank(user1);
        lock.stake(100e18, user1, 1);
        vm.prank(user1);
        lock.stake(100e18, user1, 1);

        // Second reward distribution
        vm.prank(deployer);
        _rewardToken.transfer(address(lock), 600e18);
        vm.prank(deployer);
        lock.notifyUnseenReward(rewardTokens);

        // Checking rewards after additional stakes and reward distribution
        vm.prank(user1);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user1), 400e18);
        vm.prank(user2);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user2), 320e18);
        vm.prank(user3);
        lock.getAllRewards();
        assertEq(_rewardToken.balanceOf(user3), 480e18);
    }
}
