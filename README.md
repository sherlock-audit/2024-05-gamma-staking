
# Gamma Stacking contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Arbitrum, Optimism, Base, Polygon PoS, Polygon zkEVM
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of <a href="https://github.com/d-xo/weird-erc20" target="_blank" rel="noopener noreferrer">weird tokens</a> you want to integrate?
The tokens we expect to interact with would be standard ERC-20 tokens.  The staking token will be a standard ERC-20 token.  The reward tokens will also be standard ERC-20 tokens.  There is a whitelisting process for which reward tokens we would allow to be used as rewardTokens in function addReward, which is an admin function.  This process would only allow reward tokens that comply with the ERC-20 standard to be distributed to the stakers.  We would also include USDC and USDT on the chains we mentioned in the previous question.
___

### Q: Are the admins of the protocols your contracts integrate with (if any) TRUSTED or RESTRICTED? If these integrations are trusted, should auditors also assume they are always responsive, for example, are oracles trusted to provide non-stale information, or VRF providers to respond within a designated timeframe?
N/A - We don't interact with any external protocols.


___

### Q: Are there any protocol roles? Please list them and provide whether they are TRUSTED or RESTRICTED, or provide a more comprehensive description of what a role can and can't do/impact.
There would mainly be the owner role.  Any function that contains the onlyOwner modifier would be a fully trusted function.

The team multisig will control the ability to early exit from locks, the lock penalties, and defaultRelock periods.  
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
N/A
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
No
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
The reward tokens will be sent periodically to the staking contract and function notifyUnseenRewards() will be called.

It is acceptable for users to try and front-run the sending of the rewards and staking before hand.  Typically this will be taken care of via MEV-blockers, but even if not, it would still be considered acceptable given that the nature of the contract prevents deposits and withdraws in the same transaction.
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
Hardcoded values include basePenaltyPercentage (fixed % of staked amount if a user decides to unstaked prior to his unlock time) and a timePenaltyFraction (which is a time-based penalty which linearly reduces by the amount of time staked).

Min penalty = base penalty
Max penalty = base penalty + time penalty

These could change and are intended to be upgradeable by owner.  

The defaultRelockPeriod is also intended to be upgradeable by owner.
___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
Sherlock should assume that Sequencer won't misbehave, including going offline.
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
There could be an out of gas issue if it were the case that we were to add excessive numbers of reward tokens in the addReward function.  The assumption should be that we would not add so many reward tokens that such an issue would exist.

Additionally, re-adding a removed reward token would corrupt the reward data.  The assumption should be that once a reward token is removed, it would not be re-added in the future.

Lastly, there could be penalty calculations that could be inaccurate due to floating point.  I think if this causes any material exploitation beyond the intention of the function (ex. causing 100% penalty or 0% penalty when lowest lockPeriod >= 30 days), then we would like to have this issue reported.

___

### Q: Please discuss any design choices you made.
Each lock created by staker will have its own unlock time, which will automatically be relocked for the duration of the lesser of the user's current lockPeriod or defaultRelockTime so long as the user does not call exitLateById.  If a user decides that he wants to unlock at any point, he will need to call function exitLateById.  In such a case, it is intended that the user will no longer receive rewards until the end of this unlock time.  The unlock time is dictated by modulo logic in function calcRemainUnlockPeriod.  So if the lock time were 30 days, and the user staked for 50 days, he would have been deemed to lock for a full cycle of 30 days, followed by 20 days into the second cycle of 30 days, and thus will have 10 days left before he can withdraw his funds.  Upon expiry of any lock time, the positions are automatically relocked for the duration of the lesser of the original lock time or the default lock time.    

See  the  test for UnlockCalculation.t.sol to understand the behavior of this function.

It is also intended that we would like users who unstake earlier to be allowed to stake again for a time not less than his current lockPeriod unless he already waited throughout his entire lockPeriod and he's now in the defaultRelockPeriod.  For example a user who locks for 360 days, where the defaultLockPeriod = 30 days, should be relocked at intervals of 30 days after the completion of the entire 360 days.  If a user has not completed his initial 360 day lock prior to calling exitLateByIndex, he should only be able to relock at 360 days or more even if he decides to restake at 359 days.

___

### Q: Please list any known issues/acceptable risks that should not result in a valid finding.
Re-adding a removed token will corrupt the reward data.

Any MEV issues related to sending of the reward tokens are known risks.  For example if a user sees a large amount of rewards being sent to the contract in the mempool, it is acceptable that another user frontruns the sending of the rewards by staking ahead of the distribution.  This risk is intended to be acceptable due to the fact that we'll keep the lowest lock time at around 30 days.

It is also an acceptable risk for potential multisig compromises that result in setting the exitEarly penalties to 0.  
___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
No
___

### Q: Please provide links to previous audits (if any).
https://gist.github.com/guhu95/84b0cc9237fab81c9d64b385b0974e23

Here was an initial report by an independent auditor which was based on a prior version of the code that involved having a keeper relock positions.  In the prior version of the code, a user was by default unlocked at the end of the lock period and it was up to the keeper to relock the users' position.  

In the present version of the code, a user is by default auto relocked using modulo logic for the duration of the defaultRelockTime unless he calls exitLateById.

Additionally, in the new code, we use the enumerableSet library to create a unique ID for every locked position that a user creates

___

### Q: Please list any relevant protocol resources.
Project Links
Website: https://www.gamma.xyz/
Web App: https://app.gamma.xyz/
Documents: https://docs.gamma.xyz/ 
Twitter: https://twitter.com/GammaStrategies
Discord: https://discord.gg/gammastrategies
Medium: https://medium.com/gamma-strategies
Github: https://github.com/GammaStrategies
DeFiLlama: https://defillama.com/protocol/gamma
___

### Q: Additional audit information.
In the PenaltyCalculations, we use seconds for simplicity, but in reality, the minimum lock time will be 30 days and the defaultRelockTime should be equal to minimum lock time, but in case its not, the penalty should be based on the original lockPeriod.
___



# Audit scope


[StakingV2 @ 0fd03768dda3b15db32cc04269e1110aeb7f07cb](https://github.com/GammaStrategies/StakingV2/tree/0fd03768dda3b15db32cc04269e1110aeb7f07cb)
- [StakingV2/src/Lock.sol](StakingV2/src/Lock.sol)
- [StakingV2/src/interfaces/ILock.sol](StakingV2/src/interfaces/ILock.sol)
- [StakingV2/src/interfaces/ILockList.sol](StakingV2/src/interfaces/ILockList.sol)
- [StakingV2/src/libraries/AddressPagination.sol](StakingV2/src/libraries/AddressPagination.sol)
- [StakingV2/src/libraries/LockList.sol](StakingV2/src/libraries/LockList.sol)

