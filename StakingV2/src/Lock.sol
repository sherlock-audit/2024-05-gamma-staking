// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ILock, LockedBalance, Balances, Reward, RewardData} from "./interfaces/ILock.sol";
import {ILockList} from "./interfaces/ILockList.sol";

/// @title Multi Fee Distribution Contract
/// @author Gamma
/// @dev All function calls are currently implemented without side effects

contract Lock is
    ILock,
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /********************** State Info ***********************/

    uint256 public basePenaltyPercentage; //  15% - Represents the fixed penalty amount for unlocking early
    uint256 public timePenaltyFraction; //  35% - Time-based penalty which decreases linearly with the passage of time
    uint256 public constant WHOLE = 100000; // 100%
    uint256 public defaultRelockTime;
    bool public isEarlyExitDisabled;

    /********************** Lock & Earn Info ***********************/

    // Private mappings for balance data
    mapping(address => Balances) private balances;

    uint256 public lockedSupply;
    uint256 public lockedSupplyWithMultiplier;

    /********************** Reward Info ***********************/

    address[] public rewardTokens;
    mapping(address => bool) public rewardTokenAdded;
    mapping(address => Reward) public rewardData;

    uint256[] internal lockPeriod;
    uint256[] internal rewardMultipliers;

    /// @notice user -> reward token -> amount; reward amount for users
    mapping(address => mapping(address => uint256)) public rewards;
    /// @notice user -> reward token -> amount; paid reward amount for users
    mapping(address => mapping(address => uint256)) public rewardPaid;
    /// @notice user -> reward token -> amount; reward debt amount
    mapping(address => mapping(address => uint256)) internal rewardDebt;


    /********************** Other Info ***********************/

    address public override stakingToken;
    address public treasury;

    /// @notice Users list
    ILockList public locklist;


    /// @notice Initializes contract with lock list, base penalty percentage, and time penalty fraction.
    /// @dev Sets up the contract with initial configuration necessary for operation. This function acts as a substitute for a constructor in upgradeable contracts and can only be called once.
    /// @param _locklist Address of the lock list contract, which manages lock details.
    /// @param _basePenaltyPercentage The base penalty percentage applied for early exits, scaled by 100000 for precision.
    /// @param _timePenaltyFraction The additional penalty fraction based on time, also scaled by 100000.

    function initialize(
        address _locklist,
        uint128 _basePenaltyPercentage,
        uint128 _timePenaltyFraction,
        address _owner
    ) public initializer {
        __Ownable_init(_owner);
        if (_locklist == address(0)) revert AddressZero();
        if (_basePenaltyPercentage > WHOLE || _timePenaltyFraction > WHOLE)
            revert WrongScaledPenaltyAmount();

        locklist = ILockList(_locklist);
        basePenaltyPercentage = _basePenaltyPercentage;
        timePenaltyFraction = _timePenaltyFraction;
        defaultRelockTime = 30 days;
    }

    /********************** Setters ***********************/


    /// @notice Sets the base penalty percentage and time penalty fraction for early exits.
    /// @dev This function can only be called by the owner of the contract and updates penalty attributes.
    /// @param _basePenaltyPercentage The new base penalty percentage, scaled by 100000 for precision.
    /// @param _timePenaltyFraction The new time penalty fraction, also scaled by 100000 for precision.
    function setPenaltyCalcAttributes(uint256 _basePenaltyPercentage, uint256 _timePenaltyFraction) external onlyOwner {
        if (_basePenaltyPercentage > WHOLE || _timePenaltyFraction > WHOLE)
            revert WrongScaledPenaltyAmount();
        basePenaltyPercentage = _basePenaltyPercentage;
        timePenaltyFraction = _timePenaltyFraction;
        emit SetPenaltyCalcAttribute(_basePenaltyPercentage, _timePenaltyFraction);
    }

    /// @notice Sets the minimum relock time after a late exit.
    /// @dev This function can only be called by the contract owner and updates the default relock time.
    /// @param _defaultRelockTime The new default relock time in seconds.
    function setDefaultRelockTime(uint256 _defaultRelockTime) external onlyOwner {
        defaultRelockTime = _defaultRelockTime;
    }


    /// @notice Enables or disables the ability for users to perform early exits from locks.
    /// @dev This function can only be called by the contract owner and updates the state that controls early exits.
    /// @param _isEarlyExitDisabled A boolean value indicating whether early exits should be disabled (`true` to disable, `false` to enable).
    function setIsEarlyExitDisabled(bool _isEarlyExitDisabled) external onlyOwner {
        isEarlyExitDisabled = _isEarlyExitDisabled;
    }


    /// @notice Configures lock periods and their corresponding reward multipliers for staking.
    /// @dev This function can only be called by the contract owner and is used to set or update the lock periods and reward multipliers arrays.
    /// @param _lockPeriod An array of lock periods in seconds.
    /// @param _rewardMultipliers An array of multipliers corresponding to each lock period; these multipliers enhance the rewards for longer lock periods.
    function setLockTypeInfo(
        uint256[] calldata _lockPeriod,
        uint256[] calldata _rewardMultipliers
    ) external onlyOwner {
        if (_lockPeriod.length != _rewardMultipliers.length)
            revert InvalidLockPeriod();
        delete lockPeriod;
        delete rewardMultipliers;
        uint256 length = _lockPeriod.length;
        for (uint256 i; i < length; ) {
            lockPeriod.push(_lockPeriod[i]);
            rewardMultipliers.push(_rewardMultipliers[i]);
            unchecked {
                i++;
            }
        }

        emit SetLockTypeInfo(lockPeriod, rewardMultipliers);
    }


    /// @notice Sets the token address that will be used for staking purposes.
    /// @dev This function can only be called by the contract owner and will set the staking token 
    /// @param _stakingToken The address of the token to be used as the staking token.
    function setStakingToken(address _stakingToken) external onlyOwner {
        if (_stakingToken == address(0) || stakingToken != address(0)) revert AddressZero();
        stakingToken = _stakingToken;

        emit SetStakingToken(_stakingToken);
    }


    /// @notice Assigns the specified address as the treasury for the contract.
    /// @dev This function can only be called by the contract owner to set the treasury address.
    /// @param _treasury The address to be designated as the treasury.
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }


    /// @notice Adds a new token to the list of reward tokens that will be distributed to stakers.
    /// @dev This function can only be called by the contract owner and checks for validity of the reward token before adding.
    /// @param _rewardToken The address of the token to be added as a reward token.
    function addReward(address _rewardToken) external override onlyOwner {
        if (_rewardToken == address(0)) revert InvalidBurn();
        if (rewardData[_rewardToken].lastUpdateTime != 0) revert AlreadyAdded();
        if (_rewardToken == stakingToken || rewardTokenAdded[_rewardToken]) revert InvalidRewardToken();
        rewardTokens.push(_rewardToken);
        rewardTokenAdded[_rewardToken] = true;

        Reward storage reward = rewardData[_rewardToken];
        reward.lastUpdateTime = block.timestamp;
        emit AddReward(_rewardToken);
    }

    /********************** View functions ***********************/

    /**
     * @notice Return lock duration.
     */
    function getLockDurations() external view returns (uint256[] memory) {
        return lockPeriod;
    }

    /**
     * @notice Return reward multipliers.
     */
    function getLockMultipliers() external view returns (uint256[] memory) {
        return rewardMultipliers;
    }
    /**
     * @notice Total balance of an account, including unlocked, locked and earned tokens.
     */
    function getBalances(
        address _user
    ) external view returns (Balances memory) {
        return balances[_user];
    }


    /// @notice Retrieves the address and claimable amount of all reward tokens for the specified account.
    /// @dev This function computes claimable rewards based on stored reward balances and newly earned amounts.
    /// @param account The address of the account for which reward information is being requested.
    /// @return rewardsData An array of RewardData structs, each containing a token address and the amount claimable by the account.
    function claimableRewards(
        address account
    )
        external
        view
        override
        returns (RewardData[] memory rewardsData)
    {
        uint256 length = rewardTokens.length;
        rewardsData = new RewardData[](length);
        for (uint256 i; i < length; ) {
            rewardsData[i].token = rewardTokens[i];

            rewardsData[i].amount = (_earned(
                account,
                rewardsData[i].token
            ) + rewards[account][rewardTokens[i]]) / 1e36;
            unchecked {
                i++;
            }
        }
        return rewardsData;
    }

    /********************** Operate functions ***********************/


    /// @notice Allows a user to stake tokens on behalf of another address, specifying the lock type to determine reward eligibility and lock duration.
    /// @dev Calls an internal function to handle the staking logic with `isRelock` set to `false`.
    /// @param amount The amount of tokens to be staked.
    /// @param onBehalfOf The address on behalf of which tokens are being staked. On frontend, this will be set to the msg.sender's address by default.
    /// @param typeIndex An index referring to the type of lock to be applied, which affects reward calculations and lock duration.
    function stake(
        uint256 amount,
        address onBehalfOf,
        uint256 typeIndex
    ) external override {
        _stake(amount, onBehalfOf, typeIndex, false);
    }

    /// @notice Handles the internal logic for staking tokens, applying specified lock types and managing reward eligibility.
    /// @dev This function updates rewards, manages balances, and logs the staking process through events.
    ///      It ensures the amount and lock type are valid, adjusts token balances, and optionally handles token transfers for re-staking.
    /// @param amount The amount of tokens to be staked.
    /// @param onBehalfOf The address for which tokens are being staked.
    /// @param typeIndex The index of the lock type to apply, affecting reward multipliers and lock durations.
    /// @param isRelock Specifies whether the staking is for relocking already staked tokens.
    function _stake(
        uint256 amount,
        address onBehalfOf,
        uint256 typeIndex,
        bool isRelock
    ) internal whenNotPaused {
        if (typeIndex >= lockPeriod.length || amount == 0) revert InvalidAmount();

        _updateReward(onBehalfOf);
        
        Balances storage bal = balances[onBehalfOf];

        bal.locked += amount;
        lockedSupply += amount;

        uint256 multiplier = rewardMultipliers[typeIndex];
        bal.lockedWithMultiplier += amount * multiplier;
        lockedSupplyWithMultiplier += amount * multiplier;
        _updateRewardDebt(onBehalfOf);


        locklist.addToList(
            onBehalfOf, 
            LockedBalance({
                lockId: 0, // This will be set inside the addToList function
                amount: amount,
                unlockTime: 0, 
                multiplier: multiplier,
                lockTime: block.timestamp,
                lockPeriod: lockPeriod[typeIndex],
                exitedLate: false
            })
        );

        if (!isRelock) {
            IERC20(stakingToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        emit Locked(
            onBehalfOf,
            amount,
            balances[onBehalfOf].locked
        );
    }


    /// @notice Allows a staker to perform an early exit from a locked position using the specified lock ID.
    /// @dev This function handles the early exit process, calculating penalties, updating balances, and transferring funds.
    /// @param lockId The unique identifier of the lock from which the user wishes to exit early.
    function earlyExitById(uint256 lockId) external whenNotPaused {
        if (isEarlyExitDisabled) {
            revert EarlyExitDisabled();
        }
        _updateReward(msg.sender);

        LockedBalance memory lock = locklist.getLockById(msg.sender, lockId);

        if (lock.unlockTime != 0)
            revert InvalidLockId();
        uint256 coolDownSecs = calcRemainUnlockPeriod(lock);
        lock.unlockTime = block.timestamp + coolDownSecs;
        uint256 penaltyAmount = calcPenaltyAmount(lock);
        locklist.removeFromList(msg.sender, lockId);
        Balances storage bal = balances[msg.sender];
        lockedSupplyWithMultiplier -= lock.amount * lock.multiplier;
        lockedSupply -= lock.amount;
        bal.locked -= lock.amount;
        bal.lockedWithMultiplier -= lock.amount * lock.multiplier;

        _updateRewardDebt(msg.sender);

        if (lock.amount > penaltyAmount) {
            IERC20(stakingToken).safeTransfer(msg.sender, lock.amount - penaltyAmount);
            IERC20(stakingToken).safeTransfer(treasury, penaltyAmount);
            emit EarlyExitById(lockId, msg.sender, lock.amount - penaltyAmount, penaltyAmount);
        } else {
            IERC20(stakingToken).safeTransfer(treasury, lock.amount);
        emit EarlyExitById(lockId, msg.sender, 0, penaltyAmount);
        }
    }


    /// @notice Allows a user to execute a late exit from a lock by specifying the lock ID, updating unlock times and reducing locked balances.
    /// @dev This function adjusts the unlock time based on the remaining cooldown period, updates the locked balances, flags the lock as exited late, and logs the exit.
    /// @param id The unique identifier of the lock from which the user wishes to exit late.
    function exitLateById(uint256 id) external {
        _updateReward(msg.sender); // Updates any pending rewards for the caller before proceeding.

        LockedBalance memory lockedBalance = locklist.getLockById(msg.sender, id); // Retrieves the lock details from the lock list as a storage reference to modify.

        // Calculate and set the new unlock time based on the remaining cooldown period.
        uint256 coolDownSecs = calcRemainUnlockPeriod(lockedBalance);
        locklist.updateUnlockTime(msg.sender, id, block.timestamp + coolDownSecs);

        // Reduce the locked supply and the user's locked balance with and without multiplier.
        uint256 multiplierBalance = lockedBalance.amount * lockedBalance.multiplier;
        lockedSupplyWithMultiplier -= multiplierBalance;
        lockedSupply -= lockedBalance.amount;
        Balances storage bal = balances[msg.sender];
        bal.lockedWithMultiplier -= multiplierBalance;
        bal.locked -= lockedBalance.amount;

        locklist.setExitedLateToTrue(msg.sender, id);

        _updateRewardDebt(msg.sender); // Recalculates reward debt after changing the locked balance.

        emit ExitLateById(id, msg.sender, lockedBalance.amount); // Emits an event logging the details of the late exit.
    }


    /// @notice Allows a user to restake funds after exiting late by mistake.
    /// @dev Enforces restrictions on the new lock period based on the current lock period and default relock time.
    /// @param id The ID of the lock that was exited late and needs to be re-staked.
    /// @param typeIndex The new lock type index to apply for the restake.
    function restakeAfterLateExit(uint256 id, uint256 typeIndex) external {
        // Retrieve the lock details for the specified ID.
        LockedBalance memory lockedBalance = locklist.getLockById(msg.sender, id);
        require(lockedBalance.exitedLate, "This lock was not exited late or is ineligible for restaking.");

        uint256 newLockPeriod = lockPeriod[typeIndex]; // Get the new lock period based on the type index.
        uint256 currentLockPeriod = lockedBalance.lockPeriod;

        // Enforce that the new lock period must be valid based on the current conditions.
        if (currentLockPeriod <= defaultRelockTime || (block.timestamp - lockedBalance.lockTime) < currentLockPeriod) {
            require(newLockPeriod >= currentLockPeriod, "New lock period must be greater than or equal to the current lock period");
        } else {
            require(newLockPeriod >= defaultRelockTime, "New lock period must be greater than or equal to the default relock time");
        }

        // Proceed to restake the funds using the new lock type.
        _stake(lockedBalance.amount, msg.sender, typeIndex, true);

        // Remove the old lock record to prevent any further operations on it.
        locklist.removeFromList(msg.sender, id);

        emit RestakedAfterLateExit(msg.sender, id, lockedBalance.amount, typeIndex);
    }






    /// @notice Withdraws all currently unlocked tokens where the unlock time has passed for the calling user.
    /// @dev Iterates through the list of all locks for the user, checks if the unlock time has passed, and withdraws the total unlocked amount.
    function withdrawAllUnlockedToken() external override nonReentrant {
        uint256 lockCount = locklist.lockCount(msg.sender); // Fetch the total number of locks for the caller.
        uint256 page;
        uint256 limit;
        uint256 totalUnlocked;
        
        while (limit < lockCount) {
            LockedBalance[] memory lockedBals = locklist.getLocks(msg.sender, page, lockCount); // Retrieves a page of locks for the user.
            for (uint256 i = 0; i < lockedBals.length; i++) {
                if (lockedBals[i].unlockTime != 0 && lockedBals[i].unlockTime < block.timestamp) {
                    totalUnlocked += lockedBals[i].amount; // Adds up the amount from all unlocked balances.
                    locklist.removeFromList(msg.sender, lockedBals[i].lockId); // Removes the lock from the list.
                }
            }

            limit += 10; // Moves to the next page of locks.
            page++;
        }

        IERC20(stakingToken).safeTransfer(msg.sender, totalUnlocked); // Transfers the total unlocked amount to the user.
        emit WithdrawAllUnlocked(msg.sender, totalUnlocked); // Emits an event logging the withdrawal.
    }



    /// @notice Withdraws a specific unlocked token amount using the given lock ID, if the unlock time has passed.
    /// @dev Retrieves the lock details by ID, checks if it is unlocked, and transfers the unlocked amount to the user.
    /// @param id The unique identifier of the lock to check for unlocked tokens.
    function withdrawUnlockedTokenById(uint256 id) external nonReentrant {
        LockedBalance memory lockedBal = locklist.getLockById(msg.sender, id); // Retrieves the lock details for the specified ID.
        if (lockedBal.unlockTime != 0 && lockedBal.unlockTime < block.timestamp) {
            IERC20(stakingToken).safeTransfer(msg.sender, lockedBal.amount); // Transfers the unlocked amount to the user.
            locklist.removeFromList(msg.sender, id); // Removes the lock from the lock list.
            emit WithdrawUnlockedById(id, msg.sender, lockedBal.amount); // Emits an event logging the withdrawal of the unlocked tokens.
        }
    }


    /********************** Reward functions ***********************/


    /// @notice Calculates the earnings accumulated for a given user and reward token.
    /// @dev Calculates the net earnings by multiplying the accumulated reward with the user’s locked multiplier and subtracting the reward debt.
    /// @param _user The address of the user for whom to calculate earnings.
    /// @param _rewardToken The token address for which earnings are calculated.
    /// @return earnings The calculated amount of earnings for the user in terms of the specified reward token.
    function _earned(
        address _user,
        address _rewardToken
    ) internal view returns (uint256 earnings) {
        Reward memory rewardInfo = rewardData[_rewardToken]; // Retrieves reward data for the specified token.
        Balances memory balance = balances[_user]; // Retrieves balance information for the user.
        earnings = rewardInfo.cumulatedReward * balance.lockedWithMultiplier - rewardDebt[_user][_rewardToken]; // Calculates earnings by considering the accumulated reward and the reward debt.
    }



    /// @notice Checks for and registers any rewards sent to the contract that have not yet been accounted for.
    /// @dev This function is used to update the contract's state with rewards received but not yet recorded, 
    ///      for example, tokens sent directly to the contract's address 
    ///      It should be called periodically, ideally every 24 hours, to ensure all external rewards are captured.
    /// @param token The address of the reward token to check for new, unseen rewards.
    function _notifyUnseenReward(address token) internal {
        if (token == address(0)) revert AddressZero(); // Ensures the token address is not zero.
        Reward storage r = rewardData[token]; // Accesses the reward data for the given token.
        uint256 unseen = IERC20(token).balanceOf(address(this)) - r.balance; // Calculates the amount of new, unseen rewards.

        if (unseen > 0) {
            _notifyReward(token, unseen); // Updates the reward data if there are new rewards.
        }

        emit NotifyUnseenReward(token, unseen); // Emits an event to log the notification of unseen rewards.
    }


    /// @notice Updates the reward data for a specific token with a new reward amount.
    /// @dev Adds the specified reward to the cumulative reward for the token, adjusting for the total locked supply with multiplier.
    /// @param _rewardToken The address of the reward token for which to update the reward data.
    /// @param reward The amount of the new reward to be added.
    function _notifyReward(address _rewardToken, uint256 reward) internal {
        if (lockedSupplyWithMultiplier == 0)
            return; // If there is no locked supply with multiplier, exit without adding rewards (prevents division by zero).

        Reward storage r = rewardData[_rewardToken]; // Accesses the reward structure for the specified token.
        uint256 newReward = reward * 1e36 / lockedSupplyWithMultiplier; // Calculates the reward per token, scaled up for precision.
        r.cumulatedReward += newReward; // Updates the cumulative reward for the token.
        r.lastUpdateTime = block.timestamp; // Sets the last update time to now.
        r.balance += reward; // Increments the balance of the token by the new reward amount.
    }



    /// @notice Checks and updates unseen rewards for a list of reward tokens.
    /// @dev Iterates through the provided list of reward tokens and triggers the _notifyUnseenReward function for each if it has been previously added to the contract.
    /// @param _rewardTokens An array of reward token addresses to check and update for unseen rewards.
    function notifyUnseenReward(address[] memory _rewardTokens) external {
        uint256 length = rewardTokens.length; // Gets the number of reward tokens currently recognized by the contract.
        for (uint256 i = 0; i < length; ++i) {
            if (rewardTokenAdded[_rewardTokens[i]]) {
                _notifyUnseenReward(_rewardTokens[i]); // Processes each token to update any unseen rewards.
            }
        }
    }



    /// @notice Retrieves and claims all pending staking rewards for the caller across all reward tokens.
    /// @dev This function serves as a convenience wrapper around the `getReward` function, applying it to all reward tokens currently recognized by the contract.
    function getAllRewards() external {
        getReward(rewardTokens); // Calls the getReward function with the list of all reward tokens to claim all pending rewards.
    }



    /// @notice Claims pending staking rewards for the caller for specified reward tokens.
    /// @dev Updates reward calculations for the caller, then processes claims for the provided list of reward tokens.
    /// @param _rewardTokens An array of reward token addresses from which rewards are to be claimed.
    function getReward(address[] memory _rewardTokens) public nonReentrant {
        _updateReward(msg.sender); // Updates any accrued rewards up to the current point for the caller.
        _getReward(msg.sender, _rewardTokens); // Calls the internal _getReward function to process the actual reward claim.
    }



    /// @notice Transfers accrued rewards for specified tokens to the user.
    /// @dev Iterates through the list of reward tokens and transfers each accrued reward to the user's address, provided the reward amount is greater than zero.
    ///      This function also updates the reward balances and logs the reward payments.
    /// @param _user The address of the user receiving the rewards.
    /// @param _rewardTokens An array of reward token addresses from which the user is claiming rewards.
    function _getReward(
        address _user,
        address[] memory _rewardTokens
    ) internal whenNotPaused {
        uint256 length = _rewardTokens.length; // Get the number of reward tokens to process.
        for (uint256 i = 0; i < length; ) {
            address token = _rewardTokens[i]; // Get the current token address.

            uint256 reward = rewards[_user][token]; // Retrieve the amount of reward due for the user and the token.
            if (reward > 0) {
                rewards[_user][token] = 0; // Reset the reward to zero after claiming.
                rewardData[token].balance -= reward / 1e36; // Deduct the reward from the stored balance, adjusting for decimals.

                IERC20(token).safeTransfer(_user, reward / 1e36); // Transfer the reward to the user.
                rewardPaid[_user][token] += reward / 1e36; // Update the total reward paid to the user for this token.
                emit RewardPaid(_user, token, reward / 1e36); // Emit an event documenting the reward payment.
            }
            unchecked {
                i++;
            }
        }
    }


    /********************** Eligibility + Disqualification ***********************/


    /// @notice Calculates the penalty amount for an early exit from a locked position based on the remaining time until the scheduled unlock.
    /// @dev The penalty is computed as a percentage of the locked amount, which is scaled by a base penalty percentage plus a time-dependent penalty fraction.
    /// @param userLock A struct containing details about the user's locked balance, including the amount, lock period, and unlock time.
    /// @return penaltyAmount The amount of penalty to be applied if the user decides to exit early from the lock.
    function calcPenaltyAmount(LockedBalance memory userLock) public view returns (uint256 penaltyAmount) {
        if (userLock.amount == 0) return 0; // Return zero if there is no amount locked to avoid unnecessary calculations.
        uint256 unlockTime = userLock.unlockTime;
        uint256 lockPeriod = userLock.lockPeriod;
        uint256 penaltyFactor;


        if (lockPeriod <= defaultRelockTime || (block.timestamp - userLock.lockTime) < lockPeriod) {

            penaltyFactor = (unlockTime - block.timestamp) * timePenaltyFraction / lockPeriod + basePenaltyPercentage;
        }
        else {
            penaltyFactor = (unlockTime - block.timestamp) * timePenaltyFraction / defaultRelockTime + basePenaltyPercentage;
        }

        // Apply the calculated penalty factor to the locked amount.
        penaltyAmount = userLock.amount * penaltyFactor / WHOLE;
    }



    /// @notice Determines the remaining time until a user's locked balance can be unlocked.
    /// @dev Calculates the remaining unlock period based on either the lock's specific period or the default relock time, depending on which is relevant.
    ///      The function checks if the lock period is still applicable, or if the default relock time should be used instead.
    ///      The lock period should always be the lesser of the user's own lock period or the default lock period.   
    /// @param userLock A struct containing the lock's details, including the lock period, multiplier, and the timestamp when the lock was initiated.
    /// @return uint256 of remaining time in seconds until the lock can be unlocked.
    function calcRemainUnlockPeriod(LockedBalance memory userLock) public view returns (uint256) {
        uint256 lockTime = userLock.lockTime;
        uint256 lockPeriod = userLock.lockPeriod;
        
        if (lockPeriod <= defaultRelockTime || (block.timestamp - lockTime) < lockPeriod) {
            // If the adjusted lock period is less than or equal to the default relock time, or if the current time is still within the adjusted lock period, return the remaining time based on the adjusted lock period.
            return lockPeriod - (block.timestamp - lockTime) % lockPeriod;
        } else {
            // If the current time exceeds the adjusted lock period, return the remaining time based on the default relock time.
            return defaultRelockTime - (block.timestamp - lockTime) % defaultRelockTime;
        }
    }



    /// @notice Updates the accumulated rewards and reward debts for all tokens for a specific user account.
    /// @dev Iterates over all reward tokens, updates each token's accrued rewards for the given account, and adjusts the reward debt accordingly.
    /// @param account The address of the user for whom rewards are being updated.
    function _updateReward(address account) internal {
        uint256 length = rewardTokens.length; // Determine the number of reward tokens.
        Balances storage bal = balances[account]; // Access the balance record for the user.

        for (uint256 i = 0; i < length; ) {
            address token = rewardTokens[i]; // Access each token.
            Reward memory rewardInfo = rewardData[token]; // Get the reward data for the token.

            rewards[account][token] += _earned(account, token); // Update the rewards for the user based on what has been earned so far.
            rewardDebt[account][token] = rewardInfo.cumulatedReward * bal.lockedWithMultiplier; // Update the reward debt based on the latest reward information.

            unchecked {
                i++;
            }
        }
    }



    /// @notice Updates the reward debt for all reward tokens based on the current cumulated rewards and the user's locked balances.
    /// @dev Iterates over all reward tokens and recalculates the reward debt for the specified user, based on their locked balances multiplied by the accumulated rewards for each token.
    /// @param _user The address of the user for whom the reward debt is being recalculated.
    function _updateRewardDebt(address _user) internal {
        Balances memory bal = balances[_user]; // Retrieve the current balance information for the user.

        for (uint i = 0; i < rewardTokens.length; ++i) {
            address rewardToken = rewardTokens[i]; // Access each reward token.
            Reward memory rewardInfo = rewardData[rewardToken]; // Get the current reward data for each token.

            // Recalculate the reward debt for the user based on their locked balances and the accumulated rewards for the token.
            rewardDebt[_user][rewardToken] = rewardInfo.cumulatedReward * bal.lockedWithMultiplier;
        }
    }



    /// @notice Allows the contract owner to recover ERC-20 tokens sent to the contract under specific conditions.
    /// @dev This function can only be executed by the contract owner and is meant for recovering tokens that are not actively being used as rewards or are not the staking token itself.
    ///      It checks if the token is currently active as a reward or if it's the staking token to prevent accidental or unauthorized recovery.
    /// @param tokenAddress The address of the ERC-20 token to be recovered.
    /// @param tokenAmount The amount of the token to be recovered.
    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        if (rewardData[tokenAddress].lastUpdateTime != 0) revert ActiveReward(); // Ensure the token is not currently active as a reward.
        if (tokenAddress == stakingToken) revert WrongRecoveryToken(); // Prevent recovery of the staking token.
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount); // Transfer the specified amount of the token to the contract owner.
        emit Recovered(tokenAddress, tokenAmount); // Emit an event to log the recovery operation.
    }



    /// @notice Pauses all modifiable functions in the contract, typically used in emergency situations.
    /// @dev This function can only be called by the contract owner and triggers the internal _pause function, which sets the paused state to true.
    function pause() public onlyOwner {
        _pause(); // Calls the internal _pause function which enforces the pause state across the contract.
    }



    /// @notice Resumes all paused functionalities of the contract, allowing normal operations to continue.
    /// @dev This function can only be called by the contract owner and triggers the internal _unpause function, which resets the paused state to false.
    function unpause() public onlyOwner {
        _unpause(); // Calls the internal _unpause function which deactivates the pause state across the contract.
    }

}
