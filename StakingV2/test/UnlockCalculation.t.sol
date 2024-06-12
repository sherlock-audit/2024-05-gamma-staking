// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/Lock.sol";
import "../src/mock/MockToken.sol";
import "../src/libraries/LockList.sol";

/// @title Tests for Unlock Calculation of Lock
/// @notice This suite of tests checks the unlock time calculation functionality for various staking scenarios.
/// @dev The tests simulate different staking durations and calculate remaining unlock periods.
contract UnlockCalculation is Test {
    Lock lock;
    LockList lockList;
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
        lockList = new LockList(deployer);
        // transfer ownership of locklist 
        lock.initialize(address(lockList), 15000, 35000, deployer);
        _stakingToken = new MockToken("stakingToken", "stkToken", 18);
        _rewardToken = new MockToken("rewardToken", "reward", 18);
        rewardTokens.push(address(_rewardToken));

        lock.setStakingToken(address(_stakingToken));
        lock.addReward(address(_rewardToken));
        lockPeriod.push(30 days);
        lockPeriod.push(60 days);
        lockPeriod.push(360 days);
        lockMultiplier.push(1);
        lockMultiplier.push(2);
        lockMultiplier.push(3);
        lock.setLockTypeInfo(lockPeriod, lockMultiplier);
        _stakingToken.mint(user1, 1000e18);
        _stakingToken.mint(user2, 1000e18);
        _stakingToken.mint(user3, 1000e18);
        _stakingToken.mint(user4, 1000e18);
        _stakingToken.mint(user5, 1000e18);
        _rewardToken.mint(deployer, 10000e18);
        lock.setTreasury(address(0x4));
        lockList.transferOwnership(address(lock));
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

/**
 User A:
- lockPeriodByMultiplier = 30 days
- Staked = 15 days
- remainTime = 30 - (15) % 30 = 30 - 15 = 15 days left

User B:
- lockPeriodByMultiplier = 60 days
- Staked = 60 days
- remainTime = 30 - (60) % 30 = 30 days left

User C:
- lockPeriodByMultiplier = 60 days
- Staked = 59 days
- remainTime = 60 - (59) % 60 = 60 - 59 = 1 day left

User D:
- lockPeriodByMultiplier = 360 days
- Staked = 349 days
- remainTime = 360  - (349) % 360 = 360 - 349 = 11 days left

User E:
- lockPeriodByMultiplier = 360 days
- Staked = 400 days
- remainTime = 30 - (400) % 30 = 10 = 20 days left
 */

  /// @notice Tests the unlock period calculation for User A who staked for half the minimum lock period.
  function testUserACase() public {
      vm.prank(user1);
      lock.stake(100e18, 0); // User A stakes with the first lock type

      vm.warp(block.timestamp + 15 days); // Simulate passing 15 days
      LockedBalance memory lockedBalance = lock.locklist().getLock(user1, 0);
      uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
      assertEq(remainPeriod, 15 days, "Remaining unlock period should be 15 days for User A.");
  }

  /// @notice Tests the unlock period calculation for User B who completes an exact lock cycle.
  function testUserBCase() public {
      vm.prank(user2);
      lock.stake(100e18, 1); // User B stakes with the second lock type

      vm.warp(block.timestamp + 60 days); // Simulate passing the entire lock period
      LockedBalance memory lockedBalance = lock.locklist().getLock(user2, 0);
      uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
      assertEq(remainPeriod, 30 days, "Remaining unlock period should reset to 30 days for User B.");
  }


  /// @notice Tests unlock period calculation for User C, who is one day short of completing the lock cycle.
  function testUserCCase() public {
      vm.prank(user3);
      lock.stake(100e18, 1); // User C stakes like User B

      vm.warp(block.timestamp + 59 days); // One day less than the lock period
      LockedBalance memory lockedBalance = lock.locklist().getLock(user3, 0);
      uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
      assertEq(remainPeriod, 1 days, "Remaining unlock period should be 1 day for User C.");
  }

    /// @notice Tests the unlock period calculation for User D who is close to completing a long lock cycle.
    /// @dev User D has staked for 349 days with a 360-day lock period, testing the calculation of remaining days.
    function testUserDCase() public {
        vm.prank(user4);
        lock.stake(100e18, 2); // User D stakes with the third lock type for the longest period

        vm.warp(block.timestamp + 349 days); // Warp to one day short of a full year minus 11 days
        LockedBalance memory lockedBalance = lock.locklist().getLock(user4, 0);
        uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
        assertEq(remainPeriod, 11 days, "Remaining unlock period should be 11 days for User D.");
    }

    /// @notice Tests the unlock period calculation for User E who has exceeded the lock period by a full cycle.
    /// @dev User E's scenario tests the system's handling of lock periods when the staking duration surpasses the designated lock period and should cycle back to a default relock period of 30 days.
    function testUserECase() public {
        vm.prank(user5);
        lock.stake(100e18, 2); // User E also stakes with the longest lock period option

        vm.warp(block.timestamp + 400 days); // Exceed the 360-day lock by 40 days
        LockedBalance memory lockedBalance = lock.locklist().getLock(user5, 0);
        uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
        assertEq(remainPeriod, 20 days, "Remaining unlock period should be reset to 20 days for User E after exceeding lock cycle because he completed a full 360 day cycle, followed by a full default 30-day cycle, and he's 10 days into the next 30-day cycle.  Thus he has 20 days left");
    }

    /// @notice Tests the unlock period calculation mentioned in audit
    function testForAuditFix() public {
        delete lockPeriod;
        vm.startPrank(deployer);
        lock.setDefaultRelockTime(7 days);
        lockPeriod.push(10 days);
        lockPeriod.push(20 days);
        lockPeriod.push(30 days);
        lock.setLockTypeInfo(lockPeriod, lockMultiplier);
        vm.stopPrank();

        vm.prank(user1);
        lock.stake(100e18, 0); // User A stakes with the first lock type

        vm.warp(block.timestamp + 12 days); // Simulate passing 15 days
        LockedBalance memory lockedBalance = lock.locklist().getLock(user1, 0);
        uint256 remainPeriod = lock.calcRemainUnlockPeriod(lockedBalance);
        assertEq(remainPeriod, 5 days, "Remaining unlock period should be 15 days for User A.");
    }
}