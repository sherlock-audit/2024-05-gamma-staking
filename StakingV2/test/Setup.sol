// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/Lock.sol";
import "../src/mock/MockToken.sol";
import "../src/libraries/LockList.sol";

/// @title Setup Contract for Lock Testing
/// @dev Sets up the testing environment for Lock, including all necessary contracts and configurations.
contract Setup is Test {
    Lock lock;
    LockList lockList;
    address deployer;
    address user1;
    address user2;
    address user3;
    MockToken _stakingToken;
    MockToken _rewardToken;

    uint256[] lockPeriod;
    uint256[] lockMultiplier;
    address[] rewardTokens;

    /// @notice Initializes the testing environment by setting up contracts, minting tokens, and configuring roles and permissions.
    /// @dev Deploy Lock and related contracts, set initial conditions, and provide necessary token allowances.
    function setUp() public {
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        user3 = vm.addr(3);
        deployer = vm.addr(9999999);
        uint256 forkId = vm.createFork("https://eth-mainnet.g.alchemy.com/v2/VZH1EtzO3RVWYSXs523zfhFzlO6KHnr6");
        vm.selectFork(forkId);

        vm.startPrank(deployer);
        lock = new Lock();
        lockList = new LockList(deployer);
        
        // Initialize the Lock contract with necessary configurations
        lock.initialize(address(lockList), 15000, 35000, deployer);
        _stakingToken = new MockToken("stakingToken", "stkToken", 18);
        _rewardToken = new MockToken("rewardToken", "reward", 18);
        rewardTokens.push(address(_rewardToken));

        // Configure staking token and reward token settings
        lock.setStakingToken(address(_stakingToken));
        lock.addReward(address(_rewardToken));
        lockPeriod.push(10);
        lockPeriod.push(20);
        lockPeriod.push(30);
        lockMultiplier.push(1);
        lockMultiplier.push(2);
        lockMultiplier.push(3);
        lock.setLockTypeInfo(lockPeriod, lockMultiplier);

        // Transfer ownership of locker lists to Lock contract
        _stakingToken.mint(user1, 1000e18);
        _stakingToken.mint(user2, 1000e18);
        _stakingToken.mint(user3, 1000e18);
        _rewardToken.mint(deployer, 10000e18);
        lock.setTreasury(address(0x4));
        lockList.transferOwnership(address(lock));
        vm.stopPrank();

        // Approve the Lock to manage staking tokens on behalf of users
        vm.prank(user1);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user2);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(user3);
        _stakingToken.approve(address(lock), 10000e18);
        vm.prank(deployer);
        lock.setDefaultRelockTime(10);
    }
}
