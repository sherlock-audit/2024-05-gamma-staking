pragma solidity 0.8.23;

import "../interfaces/ILock.sol";

interface ILockList {
    function addToList(address, LockedBalance memory) external returns (uint256);
    function removeFromList(address, uint256) external;
    function lockCount(address) external returns (uint256);
    function getLock(address, uint256) external returns (LockedBalance memory);
    function getLocks(address, uint256, uint256) external returns (LockedBalance[] memory);
    function getLockById(address user, uint256 lockId) external view returns (LockedBalance memory);
    function updateUnlockTime(
        address user,
        uint256 lockId,
        uint256 unlockTime
    ) external;
    function setExitedLateToTrue(
        address user,
        uint256 lockId
    ) external;
}