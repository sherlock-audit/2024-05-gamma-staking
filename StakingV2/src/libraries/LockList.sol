// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/ILock.sol";
import "../interfaces/ILockList.sol";

contract LockList is Ownable, ILockList {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public globalLockId;

    mapping(address => EnumerableSet.UintSet) internal lockIndexesByUser;
    mapping(uint256 => LockedBalance) public lockById; 

    event LockBalanceAdded(address indexed user, uint256 amount, uint256 lockId);
    event LockRemoved(address indexed user, uint256 lockId);
    event AddToList(address user, uint256 lockId);

    error WrongLockId();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
    * @dev Adds a user's locked balance to the list of locked balances.
    * @param user The address of the user whose balance is being locked.
    * @param lockedBalance The locked balance information.
    * @return lockId The unique identifier assigned to the lock.
    */
    function addToList(
        address user, 
        LockedBalance memory lockedBalance
    ) public override onlyOwner returns (uint256 lockId) {
        lockId = globalLockId;
        lockedBalance.lockId = globalLockId;
        lockById[globalLockId] = lockedBalance;
        lockIndexesByUser[user].add(globalLockId);
        globalLockId ++;
        emit AddToList(user, lockId);
    }
    /**
    * @dev Removes a user's locked balance from the list of locked balances.
    * @param user The address of the user whose balance is being unlocked.
    * @param lockId The unique identifier of the lock to be removed.
    */
    function removeFromList(
        address user,
        uint256 lockId
    ) public override onlyOwner {
        delete lockById[lockId];

        lockIndexesByUser[user].remove(lockId);
        emit LockRemoved(user, lockId);
    }
    
    /**
    * @dev Updates the unlock time of a user's locked balance.
    * @param user The address of the user whose lock is being updated.
    * @param lockId The unique identifier of the lock to be updated.
    * @param unlockTime The new unlock time for the lock.
    * @notice This function can only be called by the contract owner.
    */
    function updateUnlockTime(
        address user,
        uint256 lockId,
        uint256 unlockTime
    ) public override onlyOwner {
        if (!lockIndexesByUser[user].contains(lockId))
            revert WrongLockId();
        lockById[lockId].unlockTime = unlockTime;
    }

    function setExitedLateToTrue(
        address user,
        uint256 lockId
    ) public override onlyOwner {
        if (!lockIndexesByUser[user].contains(lockId))
            revert WrongLockId();
        lockById[lockId].exitedLate = true;
    }

    function lockCount(address user) external view override returns (uint256) {
        return lockIndexesByUser[user].length();
    }

    function getLock(address user, uint256 index) external view override returns (LockedBalance memory) {
        return lockById[lockIndexesByUser[user].at(index)];
    }
    
    function getLockById(address user, uint256 lockId) external override view returns (LockedBalance memory) {
        if (!lockIndexesByUser[user].contains(lockId))
            revert WrongLockId();
        return lockById[lockId];
    }

    function getLocks(
        address user,
        uint256 page,
        uint256 limit
    ) public view override returns (LockedBalance[] memory) {
        LockedBalance[] memory locks = new LockedBalance[](limit);
        uint256 lockIdsLength = lockIndexesByUser[user].length();

        uint256 i = page * limit;
        for (;i < (page + 1) * limit && i < lockIdsLength; i ++) {
            locks[i - page * limit]= lockById[lockIndexesByUser[user].at(i)];
        }
        return locks;
    }

    function lockedBalances(
        address user,
        uint256 page,
        uint256 limit
    ) 
        external 
        view 
        returns (
            uint256 locked,
            uint256 unlockable,
            uint256 lockWithMultiplier
        )
    {
        LockedBalance[] memory locks = getLocks(user, page, limit);
        uint256 length = locks.length;
        for (uint256 i; i < length; i ++) {
            if (locks[i].unlockTime == 0) {
                locked += locks[i].amount;
                lockWithMultiplier += locks[i].amount * locks[i].multiplier;
            } else {
                unlockable += locks[i].amount;
            }
        }
    }
}