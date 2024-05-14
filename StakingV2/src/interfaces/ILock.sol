// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

struct LockedBalance {
    uint256 lockId;
    uint256 amount;
    uint256 unlockTime;
    uint256 multiplier;
    uint256 lockTime;
    uint256 lockPeriod;
    bool exitedLate;
}

struct Reward {
    uint256 lastUpdateTime;
    uint256 cumulatedReward;
    // tracks already-added balances to handle accrued interest in aToken rewards
    // for the stakingToken this value is unused and will always be 0
    uint256 balance;
}

struct Balances {
    uint256 total; // sum of earnings and lockings;
    uint256 locked; 
    uint256 lockedWithMultiplier; // Multiplied locked amount
    uint256 earned; 
}

struct RewardData {
    address token;
    uint256 amount;
}

interface ILock {
    function stake(uint256 amount, address onBehalfOf, uint256 typeIndex) external;

    function withdrawAllUnlockedToken() external;

    function claimableRewards(address account) external view returns (RewardData[] memory rewards);

    function stakingToken() external view returns (address);

    function addReward(address rewardsToken) external;


    /********************** Events ***********************/
    event AddReward(address _rewardToken);
    event Locked(address indexed user, uint256 amount, uint256 lockedBalance);
    event Withdrawn(
        address indexed user,
        uint256 receivedAmount,
        uint256 lockedBalance,
        uint256 penalty,
        uint256 burn
    );
    event RewardPaid(
        address indexed user,
        address indexed rewardToken,
        uint256 reward
    );
    event Recovered(address indexed token, uint256 amount);
    event Relocked(address indexed user, uint256 amount, uint256 lockIndex);
    event EarlyExitById(uint256 id, address user, uint256 amount, uint256 penaltyAmount);
    event ExitLateById(uint256 id, address user, uint256 amount);
    event RestakedAfterLateExit(address user, uint256 id, uint256 amount, uint256 typeIndex);
    event NotifyUnseenReward(address token, uint256 amount);
    event SetPenaltyCalcAttribute(uint256 basePenaltyPercentage, uint256 timePenaltyFraction);
    event SetLockTypeInfo(uint256[] lockPeriod, uint256[] rewardMultipliers);
    event SetStakingToken(address stakingToken);
    event SetTreasury(address treasury);
    event WithdrawAllUnlocked(address user, uint256 amount);
    event WithdrawUnlockedById(uint256 id, address user, uint256 amount);


    /********************** Errors ***********************/
    error ActiveReward();
    error AddressZero();
    error AlreadyAdded();
    error InvalidBurn();
    error InvalidLockPeriod();
    error InvalidAmount();
    error InvalidLockId();
    error InvalidRewardToken();
    error WrongScaledPenaltyAmount();
    error WrongRecoveryToken();
    error EarlyExitDisabled();
}