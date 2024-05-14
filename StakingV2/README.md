# Locking and Staking System Documentation

## Overview

This system is designed to facilitate token locking and staking with various lock periods and associated rewards. It includes mechanisms for early and late exits, penalty calculations, and restaking options. The system is implemented using several Solidity contracts, each serving a specific purpose and interacting with each other to ensure smooth functionality.

In practice, the staking token will be our governance token that will only have one visible option on frontend for a 30-day lock with defaultLockPeriod also equal to 30 days.  The ability to earlyExit will be toggled off by default.  On the backend, longer lock periods will be reserved for team and investors who will be staked at the same multiplier as the public.  This allows team and investors to lock their tokens and earn revenues from locking without the ability to unstake tokens until they reach the end of their lockPeriods or defaultLock periods.  

In the future, we may turn on the ability to earlyExit and introduce longer periods to the public with higher multipliers.

## Contracts

### 1. `Lock.sol`

**Purpose:**
The `Lock` contract is the core contract responsible for handling token staking, locking, and rewards distribution. It manages users' locked balances, calculates penalties for early exits, and allows restaking of tokens under certain conditions.

**Key Functions:**

#### Public Functions:
- `initialize(address _locklist, uint128 _basePenaltyPercentage, uint128 _timePenaltyFraction, address _owner)`: Initializes the contract with essential parameters.
- `stake(uint256 amount, address onBehalfOf, uint256 typeIndex)`: Allows users to stake tokens.
- `earlyExitById(uint256 lockId)`: Enables users to exit their lock early, with penalties.
- `exitLateById(uint256 id)`: Allows users to exit their lock after the lock period has passed.
- `restakeAfterLateExit(uint256 id, uint256 typeIndex)`: Allows users to restake tokens after exiting late.
- `withdrawAllUnlockedToken()`: Withdraws all unlocked tokens for a user.
- `withdrawUnlockedTokenById(uint256 id)`: Withdraws a specific unlocked token amount using the given lock ID.
- `getAllRewards()`: Claims all pending staking rewards for the caller.

#### Owner-Only Functions:
- `setPenaltyCalcAttributes(uint256 _basePenaltyPercentage, uint256 _timePenaltyFraction)`: Sets the base penalty percentage and time penalty fraction for early exits.
- `setDefaultRelockTime(uint256 _defaultRelockTime)`: Sets the minimum relock time after a late exit.
- `setIsEarlyExitDisabled(bool _isEarlyExitDisabled)`: Enables or disables the ability for users to perform early exits from locks.
- `setLockTypeInfo(uint256[] calldata _lockPeriod, uint256[] calldata _rewardMultipliers)`: Configures lock periods and their corresponding reward multipliers for staking.
- `setStakingToken(address _stakingToken)`: Sets the token address that will be used for staking purposes.
- `setTreasury(address _treasury)`: Assigns the specified address as the treasury for the contract.
- `addReward(address _rewardToken)`: Adds a new token to the list of reward tokens that will be distributed to stakers.
- `recoverERC20(address tokenAddress, uint256 tokenAmount)`: Allows the contract owner to recover ERC-20 tokens sent to the contract under specific conditions.
- `pause()`: Pauses all modifiable functions in the contract, typically used in emergency situations.
- `unpause()`: Resumes all paused functionalities of the contract, allowing normal operations to continue.

**Events:**
- `Locked(address indexed user, uint256 amount, uint256 total)`: Emitted when tokens are locked.
- `EarlyExitById(uint256 indexed lockId, address indexed user, uint256 amount, uint256 penalty)`: Emitted when a user exits early.
- `ExitLateById(uint256 indexed id, address indexed user, uint256 amount)`: Emitted when a user exits late.
- `RestakedAfterLateExit(address indexed user, uint256 indexed id, uint256 amount, uint256 typeIndex)`: Emitted when a user restakes after a late exit.

### 2. `LockList.sol`

**Purpose:**
The `LockList` contract manages the list of locks for each user. It stores the details of each lock, including the amount, lock period, multiplier, and unlock time. It also facilitates adding and removing locks and updating their statuses.

**Key Functions:**
- `addToList(address user, LockedBalance memory lock)`: Adds a new lock to the user's list.
- `removeFromList(address user, uint256 lockId)`: Removes a lock from the user's list.
- `getLockById(address user, uint256 lockId)`: Retrieves lock details by ID.
- `lockCount(address user)`: Returns the number of locks for a user.
- `getLocks(address user, uint256 page, uint256 limit)`: Returns a paginated list of locks for a user.

**Events:**
- `LockAdded(address indexed user, uint256 lockId, uint256 amount, uint256 lockPeriod)`: Emitted when a lock is added.
- `LockRemoved(address indexed user, uint256 lockId)`: Emitted when a lock is removed.

### 3. `ILock.sol`

**Purpose:**
The `ILock` interface defines the required functions for the `Lock` contract. It ensures that the `Lock` contract adheres to a specific structure, facilitating interaction with other contracts.

**Key Functions:**
- `claimableRewards(address account)`: Returns the claimable rewards for a specific account.
- `stake(uint256 amount, address onBehalfOf, uint256 typeIndex)`: Allows users to stake tokens.
- `withdrawAllUnlockedToken()`: Withdraws all unlocked tokens for a user.

### 4. `ILockList.sol`

**Purpose:**
The `ILockList` interface defines the required functions for the `LockList` contract. It ensures that the `LockList` contract adheres to a specific structure, facilitating interaction with other contracts.

**Key Functions:**
- `addToList(address user, LockedBalance memory lock)`: Adds a new lock to the user's list.
- `removeFromList(address user, uint256 lockId)`: Removes a lock from the user's list.
- `getLockById(address user, uint256 lockId)`: Retrieves lock details by ID.

## Relationships Between Contracts

1. **`Lock` and `LockList`**: 
   - The `Lock` contract interacts with the `LockList` contract to manage users' locked balances. It calls functions from `LockList` to add, remove, and retrieve lock details.
   - The `LockList` contract maintains the state of each user's locks, ensuring that the `Lock` contract can perform its operations effectively.

2. **`Lock` and `ILock` / `ILockList`**:
   - The `ILock` and `ILockList` interfaces define the standard functions that the `Lock` and `LockList` contracts must implement. This ensures consistency and facilitates integration with other contracts or systems that might interact with the `Lock` and `LockList` contracts.

## Test Suite

The test suite is designed to verify the correct functionality of the system. It includes various scenarios to ensure the system behaves as expected under different conditions.

**Key Test Cases and Commands:**
- **Initialization**: Verify that the `Lock` contract initializes correctly with the specified parameters.
- **Staking**: Ensure users can stake tokens and that their balances are updated accordingly.
  - Command: `forge test --match-contract DepositTest -vvvv`
- **Early Exit & Penalty Calculations**: Test the early exit functionality, including penalty calculations and balance updates.
  - Command: `forge test --match-contract PenaltyCalculations -vvvv`
- **Late Exit**: Verify the late exit process, ensuring that unlock times and balances are managed correctly.
  - Command: `forge test --match-contract WithdrawTest -vvvv`
- **Restake After Late Exit**: Check that users can restake tokens after a late exit, with appropriate restrictions on lock periods.
  - Command: `forge test --match-contract RestakeAfterLateExit -vvvv`
- **Reward Distribution**: Ensure that rewards are distributed correctly based on the staking and locking periods. (Tested in `DepositTest` and `WithdrawTest`)
  - Command: `forge test --match-contract DepositTest -vvvv`
  - Command: `forge test --match-contract WithdrawTest -vvvv`

## Conclusion

This documentation provides an overview of the locking and staking system, detailing the purpose and functionality of each contract, their relationships, and the key test cases. Auditors can use this information to understand the system's architecture and verify its correctness and security.
