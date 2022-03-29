// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./LoopToken.sol";

contract LoopStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        address user;
        uint256 amount; //staked amount
        uint256 lastDepositTime;
        uint256 accRewards;
        uint256 accUnlockRewards;
        uint256 rewardDebt; //RewardDebt used to signify all rewards that have been claimed by a user
        uint256 rewardUnlockDebt; //The unlocked version of RewardDebt
        uint256 rewardDebtAtTime;
        uint256 lastLoopPerShare;
    }
    struct ClaimHistory {
        address user;
        uint256 totalAmount;
        uint256 releasedUnlockAmount;
        uint256 releasedLockAmount;
        uint256 datetime;
    }

    ClaimHistory[] public claimHistory;

    LoopToken public govToken;

    uint256 immutable LOCK_PERIOD; //seconds

    uint256 REWARD_PER_BLOCK;
    uint256 ONE_BLOCK_TIME;
    uint256[] public REWARD_MULTIPLIER; // init in constructor function. 
    uint256[] HALVING_AT_TIME; // init in constructor function
    uint256[] unstakingPeriodStage;
    uint256[] public userFeePerPeriodStage;
    uint256 public FINISH_BONUS_AT_TIME;

    uint256 HALVING_AFTER_TIME;
    uint256 public totalStaked;
    uint256 accLoopPerShare; // Accumulated LOOP per share, times 1e18 to cater for small stakes
    uint256 lastRewardTime;
    uint256 public START_TIME;

    uint256[] public PERCENT_LOCK_BONUS_REWARD; // lock xx% of bonus reward
    address communityPool;
    address ecosystemPool;
    address reservePool;
    address foundersPool;
    address advisorsPool;

    UserInfo[] public userInfo;
    mapping(address => uint256) public userId; //Maps 0x address to staking user's internal user id

    struct _LockInfo {
        uint256 lockedTime;
        uint256 lockedAmount;
    }

    mapping(address => _LockInfo[]) public _lockInfo;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event SendGovernanceTokenReward(
        address indexed user,
        uint256 pendingUnlock,
        uint256 availableLockedAmount
    );

    constructor(
        LoopToken _govToken,
        uint256 _rewardPerBlock,
        uint256 _rewardStartTimestamp,
        uint256 _halvingAfterBlock,
        uint256 _oneblocktime,
        uint256 _lockPeriod,
        uint256[] memory _rewardMultiplier,
        uint256[] memory _percentLockReward,
        uint256[] memory _unstakingPeriodStage,
        uint256[] memory _userFeePerPeriodStage
    ) {
        require(
            address(_govToken) != address(0),
            "constructor: LoopToken must not be zero address"
        );

        require(
            _rewardStartTimestamp > block.timestamp,
            "constructor: _rewardStartTimestamp must be after block.timestamp!"
        );
        
        require(
            _rewardPerBlock > 0,
            "constructor: _rewardPerBlock must be greater than 0"
        );

        require(
            _oneblocktime > 0,
            "constructor: _oneblocktime must be greater than 0"
        );

        require(
            _lockPeriod > 0,
            "constructor: _lockPeriod must be greater than 0"
        );

        require(
            _rewardMultiplier.length > 0,
            "constructor: _rewardMultiplier is empty"
        );

        require(
            _rewardMultiplier.length == _percentLockReward.length,
            "constructor: _rewardMultiplier and _percentLockReward are incorrect length"
        );

        require(
            _unstakingPeriodStage.length > 0,
            "constructor: _unstakingPeriodStage is empty"
        );

        require(
            (_unstakingPeriodStage.length + 2) == _userFeePerPeriodStage.length,
            "constructor: _unstakingPeriodStage and _userFeePerPeriodStage are incorrect length"
        );

        bool isValid = true;

        for (uint256 i = 0; i < _percentLockReward.length; i++) {
            if (_percentLockReward[i] > 100) {
                isValid = false;
                break;
            }
        }

        require(
            isValid == true,
            "constructor: _percentLockReward has invalid percentage"
        );

        isValid = true;
        for (uint256 i = 0; i < _unstakingPeriodStage.length - 1; i++) {
            if (_userFeePerPeriodStage[i] > 10000) {
                isValid = false;
                break;
            }
        }

        require(
            isValid == true,
            "constructor: _userFeePerPeriodStage has invalid percentage"
        );

        isValid = true;
        for (uint256 i = 0; i < _unstakingPeriodStage.length - 1; i++) {
            if (_unstakingPeriodStage[i] >= _unstakingPeriodStage[i + 1]) {
                isValid = false;
                break;
            }
        }

        require(
            isValid == true,
            "constructor: _unstakingPeriodStage must be ascending"
        );

        govToken = _govToken;

        REWARD_PER_BLOCK = _rewardPerBlock.mul(10**govToken.decimals());
        REWARD_MULTIPLIER = _rewardMultiplier;
        PERCENT_LOCK_BONUS_REWARD = _percentLockReward;
        LOCK_PERIOD = _lockPeriod;
        unstakingPeriodStage = _unstakingPeriodStage;
        userFeePerPeriodStage = _userFeePerPeriodStage;

        ONE_BLOCK_TIME = _oneblocktime;

        HALVING_AFTER_TIME = _halvingAfterBlock * ONE_BLOCK_TIME;

        START_TIME = _rewardStartTimestamp;

        for (uint256 i = 0; i < REWARD_MULTIPLIER.length; i++) {
            uint256 halvingAtTime = HALVING_AFTER_TIME.mul(i + 1).add(
                START_TIME
            );
            HALVING_AT_TIME.push(halvingAtTime);
        }

        FINISH_BONUS_AT_TIME = HALVING_AFTER_TIME
            .mul(REWARD_MULTIPLIER.length)
            .add(START_TIME);

        lastRewardTime = START_TIME;
        accLoopPerShare = 0;
    }

    function setOwner(address _new) public onlyOwner {
        transferOwnership(_new);
    }

    function setDistributionAddress(
        address _communityPool,
        address _ecosystemPool,
        address _reservePool,
        address _foundersPool,
        address _advisorsPool
    ) public onlyOwner {
        communityPool = _communityPool;
        ecosystemPool = _ecosystemPool;
        reservePool = _reservePool;
        foundersPool = _foundersPool;
        advisorsPool = _advisorsPool;
    }

    //Update Staking Reward Start Time
    function setRewardStartTimestamp(uint256 _rewardStartTimestamp)
        external
        onlyOwner
    {
        require(
            _rewardStartTimestamp > block.timestamp,
            "_rewardStartTimestamp must be after block.timestamp!"
        );

        START_TIME = _rewardStartTimestamp;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length; i++) {
            uint256 halvingAtTime = HALVING_AFTER_TIME.mul(i + 1).add(
                START_TIME
            );
            HALVING_AT_TIME[i] = halvingAtTime;
        }
        FINISH_BONUS_AT_TIME = HALVING_AFTER_TIME
            .mul(REWARD_MULTIPLIER.length)
            .add(START_TIME);

        lastRewardTime = START_TIME;
    }

    //set LOOP Token only by owner
    function setLOOPToken(LoopToken _govToken) external onlyOwner {
        govToken = _govToken;
    }

    //update Multiplier only by owner
    function setRewardMultiplier(uint256[] memory _rewardMultiplier) external onlyOwner {
        require(
            _rewardMultiplier.length > 0,
            "updating Multiplier: _rewardMultiplier is empty"
        );
        require(
            _rewardMultiplier.length == PERCENT_LOCK_BONUS_REWARD.length,
            "updating Multiplier: _rewardMultiplier has wrong length"
        );

        update();

        REWARD_MULTIPLIER = _rewardMultiplier;
    }

    //update Reward Per Block
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        require(
            _rewardPerBlock > 0,
            "updating Reward Per Block: _rewardPerBlock must be greater than 0"
        );
        
        update();
        
        REWARD_PER_BLOCK = _rewardPerBlock.mul(10**govToken.decimals());
    }

    //update user unstaking Fees
    function setUnstakingFees(uint256[] memory _userFeePerPeriodStage) external onlyOwner {
        require(
            (unstakingPeriodStage.length + 2) == _userFeePerPeriodStage.length,
            "updating unstakingFees: _userFeePerPeriodStage has wrong length"
        );
        
        bool isValid = true;
        for (uint256 i = 0; i < unstakingPeriodStage.length - 1; i++) {
            if (_userFeePerPeriodStage[i] > 10000) {
                isValid = false;
                break;
            }
        }

        require(
            isValid == true,
            "updating unstakingFees: _userFeePerPeriodStage has invalid percentage"
        );

        userFeePerPeriodStage = _userFeePerPeriodStage;
    }

    //Return the total reward tokens accrued from _from timestamp to _to timestamp in seconds
    function getReward(uint256 _from, uint256 _to)
        private
        view
        returns (uint256)
    {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount = multiplier * REWARD_PER_BLOCK;
        amount = amount.div(ONE_BLOCK_TIME);

        return amount;
    }

    function getClaimHistory() external view returns (ClaimHistory[] memory) {
        return claimHistory;
    }

    //View function to see total amount of locked LOOP rewards on frontend
    function getLockedRewards(address user) public view returns (uint256) {
        _LockInfo[] memory _info = _lockInfo[user];
        uint256 amount = 0;

        for (uint256 i = 0; i < _info.length; i++) {
            amount = amount.add(_info[i].lockedAmount);
        }
        return amount;
    }

    // View function to see pending LOOP on frontend.
    function pendingReward(address _user)
        external
        view
        returns (
            uint256 pendingUnlocked,
            uint256 pendingLocked,
            uint256 availableLockedAmount
        )
    {
        uint256 uid = userId[_user];
        if (uid == 0) {
            pendingUnlocked = 0;
            pendingLocked = 0;
            availableLockedAmount = 0;
            return (pendingUnlocked, pendingLocked, availableLockedAmount);
        } else {
            UserInfo memory user = userInfo[uid - 1];
            uint256 accAmount = user.accRewards;
            uint256 accUnlockAmount = user.accUnlockRewards;
            uint256 lockPercentage = getLockPercentage(block.timestamp);
            uint256 _accLoopPerShare = accLoopPerShare;
            if (block.timestamp > lastRewardTime && user.amount > 0) {
                uint256 LoopRewards = getReward(
                    lastRewardTime,
                    block.timestamp
                );
                _accLoopPerShare = accLoopPerShare.add(
                    LoopRewards.mul(1e18).div(totalStaked)
                );
                uint256 pending = user
                    .amount
                    .mul(_accLoopPerShare.sub(user.lastLoopPerShare))
                    .div(1e18);
                accAmount = accAmount.add(pending);
                uint256 lockAmount = pending.mul(lockPercentage).div(100);                
                accUnlockAmount = accUnlockAmount.add(pending.sub(lockAmount));
            }

            availableLockedAmount = pendingAvailableLockedReward(uid - 1);
            
            uint256 pendingRewards = accAmount.sub(user.rewardDebt);
            pendingUnlocked = accUnlockAmount.sub(user.rewardUnlockDebt);
            pendingLocked = pendingRewards.sub(pendingUnlocked);

            return (pendingUnlocked, pendingLocked, availableLockedAmount);
        }
    }

    //Total Locked Rewards Available for Unlocking
    function pendingAvailableLockedReward(uint256 _uid)
        private
        view
        returns (uint256)
    {
        UserInfo memory _userInfo = userInfo[_uid];

        _LockInfo[] memory _info = _lockInfo[_userInfo.user];
        
        uint256 availableLockedAmount = 0;

        for (uint256 i = 0; i < _info.length; i++) {
            if (block.timestamp >= _info[i].lockedTime + LOCK_PERIOD) {
                availableLockedAmount = availableLockedAmount.add(
                    _info[i].lockedAmount
                );
            }
        }

        return availableLockedAmount;
    }

    //Adds any locked token that is ready for claim into user's availableLockedAmount
    function unlock(uint256 _uid) private returns (uint256) {
        UserInfo storage _userInfo = userInfo[_uid];
        uint256 availableLockedAmount = 0;
        _LockInfo[] storage _info = _lockInfo[_userInfo.user];        

        for (uint256 i = 0; i < _info.length; i++) {
            if (block.timestamp >= _info[i].lockedTime + LOCK_PERIOD) {
                availableLockedAmount = availableLockedAmount.add(
                    _info[i].lockedAmount
                );
                _info[i].lockedAmount = 0;
            }
        }

        return availableLockedAmount;
    }

    // Return reward multiplier over the given _from to _to block.
    // This multiplier is the product of the Block Multiplier * # of Blocks

    function getMultiplier(uint256 _from, uint256 _to)
        private
        view
        returns (uint256)
    {
        uint256 result = 0;
        if (_from < START_TIME) return 0; //0 reward multiplier if staking before START_TIME. This probably should never happen.

        for (uint256 i = 0; i < HALVING_AT_TIME.length; i++) {
            uint256 endTime = HALVING_AT_TIME[i];

            if (_to <= endTime) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endTime) {
                uint256 m = endTime.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endTime;
                result = result.add(m);
            }
        }

        return result;
    }

    function getLockPercentage(uint256 _to) private view returns (uint256) {
        uint256 result = 0;

        for (uint256 i = 0; i < HALVING_AT_TIME.length; i++) {
            uint256 endTime = HALVING_AT_TIME[i];

            if (_to <= endTime) {
                return PERCENT_LOCK_BONUS_REWARD[i];
            }
        }

        return result;
    }


    /**
     * Update reward accrual state.
     *
     * @dev update() must be called every time the token balances
     *      or REWARD_PER_BLOCK or REWARD_MULTIPLIER change
     */

    function update() private {
        if (totalStaked == 0) {
            //Initialize
            lastRewardTime = START_TIME;
            return;
        }
        
        if (block.timestamp <= lastRewardTime) {
            //No time has passed or staking contract START_TIME has not passed
            return;
        }

        uint256 LoopRewards = getReward(lastRewardTime, block.timestamp);
        accLoopPerShare = accLoopPerShare.add(
            LoopRewards.mul(1e18).div(totalStaked)
        );
        lastRewardTime = block.timestamp;
    }

    function claimReward() external {
        uint256 uid = userId[address(msg.sender)];
        require(uid > 0, "Not a staker");
        require(START_TIME < block.timestamp, "Reward not started!");

        claimPendingRewards(uid);
    }

    function claimPendingRewards(uint256 _uid) internal {
        UserInfo storage user = userInfo[_uid - 1];
        
        require(user.amount>0, "You have no amounts staked");

        _updateUserReward(_uid);

        uint256 pendingUnlock = user.accUnlockRewards.sub(
            user.rewardUnlockDebt
        );

        if (pendingUnlock > 0) {

            //Add any locked amounts that are due and available for unlock
            uint256 availableLockedAmount = unlock(_uid - 1);

            uint256 pending = pendingUnlock.add(availableLockedAmount);

            govToken.mint(msg.sender, pending);

            claimHistory.push(
                ClaimHistory({
                    user: msg.sender,
                    totalAmount: pending,
                    releasedUnlockAmount: pendingUnlock,
                    releasedLockAmount: availableLockedAmount,
                    datetime: block.timestamp
                })
            );

            user.rewardDebtAtTime = block.timestamp;

            emit SendGovernanceTokenReward(
                msg.sender,
                pendingUnlock,
                availableLockedAmount
            );
        }

        user.rewardDebt = user.accRewards;
        user.rewardUnlockDebt = user.accUnlockRewards;
    }

    //Locking of rewards happen here
    //Locking is such that if user claims after the lock percentage stage changes, he is able to unlock more rewards
    //This is based on the same method used by DefiKingdoms
    //Every time the user claims, he pushes a locked portion of rewards into his locked rewards records
    function _updateUserReward(uint256 _uid) internal {
        update();
        if (_uid == 0) return;
        UserInfo storage user = userInfo[_uid - 1]; //The User Info array index is always at user_id - 1

        uint256 pending = user
            .amount
            .mul(accLoopPerShare.sub(user.lastLoopPerShare))
            .div(1e18);

        user.accRewards = user.accRewards.add(pending); //Total rewards due to the user

        uint256 lockPercentage = 0;

        if (user.rewardDebtAtTime <= FINISH_BONUS_AT_TIME) {
            lockPercentage = getLockPercentage(block.timestamp);
        }

        uint256 lockAmount = pending.mul(lockPercentage).div(100);

        user.accUnlockRewards = user.accUnlockRewards.add(
            pending.sub(lockAmount)
        );

        if (lockAmount > 0) {
            _LockInfo[] storage _info = _lockInfo[user.user];
            _info.push(
                _LockInfo({
                    lockedTime: block.timestamp,
                    lockedAmount: lockAmount
                })
            );
        }

        user.lastLoopPerShare = accLoopPerShare;
    }

    function staking(uint256 _amount) external nonReentrant {
        require(_amount > 0, "deposit: amount must be greater than 0");

        uint256 uid = userId[address(msg.sender)];

        _updateUserReward(uid);

        totalStaked = totalStaked.add(_amount);
        
        if (uid == 0) { //If user doesn't exist, add new user
            uid = userInfo.length + 1;
            userId[address(msg.sender)] = uid;
            userInfo.push(
                UserInfo({
                    user: msg.sender,
                    amount: 0,
                    rewardDebt: 0,
                    rewardUnlockDebt: 0,
                    rewardDebtAtTime: block.timestamp,
                    lastDepositTime: 0,
                    accRewards: 0,
                    accUnlockRewards: 0,
                    lastLoopPerShare: accLoopPerShare
                })
            );
        }

        UserInfo storage user = userInfo[uid - 1];
        user.amount = user.amount.add(_amount);
        user.lastDepositTime = block.timestamp;

        IERC20(govToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        emit Staked(msg.sender, _amount);
    }

    function unstaking(uint256 _amount) external nonReentrant {
        uint256 uid = userId[address(msg.sender)];
        require(uid > 0, "Not a staker");

        UserInfo storage user = userInfo[uid - 1];
        require(
            user.amount.sub(_amount) > 0,
            "withdraw amount exceeds your staked amount"
        );

        _updateUserReward(uid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalStaked = totalStaked.sub(_amount);

            uint256 timeDelta;
            timeDelta = block.timestamp - user.lastDepositTime;

            uint256 userAmount = 0;
            uint256 treasuryAmount = 0;

            if (timeDelta == 0) {
                //same block
                //25% slashing fee if a user withdraws during the same block
                treasuryAmount = _amount.mul(userFeePerPeriodStage[0]).div(
                    10000
                );
            } else {
                if (timeDelta <= unstakingPeriodStage[0]) {
                    //8% fee if a user withdraws in less than 1 day
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[1]).div(
                        10000
                    );
                }
                if (
                    timeDelta > unstakingPeriodStage[0] &&
                    timeDelta <= unstakingPeriodStage[1]
                ) {
                    //4% fee if a user withdraws after 1 day
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[2]).div(
                        10000
                    );
                }
                if (
                    timeDelta > unstakingPeriodStage[1] &&
                    timeDelta <= unstakingPeriodStage[2]
                ) {
                    //2% fee if a user withdraws after 5 days
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[3]).div(
                        10000
                    );
                }
                if (
                    timeDelta > unstakingPeriodStage[2] &&
                    timeDelta <= unstakingPeriodStage[3]
                ) {
                    //1% fee if a user withdraws after 7 days
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[4]).div(
                        10000
                    );
                }
                if (
                    timeDelta > unstakingPeriodStage[3] &&
                    timeDelta <= unstakingPeriodStage[4]
                ) {
                    //0.25% fee if a user withdraws after 14 days
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[5]).div(
                        100
                    );
                }
                if (timeDelta > unstakingPeriodStage[4]) {
                    //0.01% fee if a user withdraws after 30 days
                    treasuryAmount = _amount.mul(userFeePerPeriodStage[6]).div(
                        10000
                    );
                }
            }

            userAmount = _amount.sub(treasuryAmount);

            IERC20(govToken).safeTransfer(address(msg.sender), userAmount);

            uint256 burnAmount = treasuryAmount.div(100);
            treasuryAmount = treasuryAmount.sub(burnAmount);

            IERC20(govToken).safeTransfer(
                address(communityPool),
                treasuryAmount.mul(45).div(100)
            );
            IERC20(govToken).safeTransfer(
                address(ecosystemPool),
                treasuryAmount.mul(20).div(100)
            );
            IERC20(govToken).safeTransfer(
                address(reservePool),
                treasuryAmount.mul(15).div(100)
            );
            IERC20(govToken).safeTransfer(
                address(foundersPool),
                treasuryAmount.mul(15).div(100)
            );
            IERC20(govToken).safeTransfer(
                address(advisorsPool),
                treasuryAmount.mul(5).div(100)
            );

            govToken.burn(burnAmount);

            emit Unstaked(msg.sender, _amount);
        }
    }

    //Withdraw without caring about rewards. EMERGENCY ONLY.
    //This has a 25% fee to prevent abuse

    function emergencyWithdraw() public nonReentrant {
        uint256 uid = userId[address(msg.sender)];
        require(uid > 0, "Not a staker");
        UserInfo storage user = userInfo[uid - 1];
        uint256 amount = user.amount;
        user.amount = 0;
        user.lastLoopPerShare = 0;
        user.accRewards = 0;
        user.accUnlockRewards = 0;
        user.rewardDebt = 0;
        user.rewardUnlockDebt = 0;
        uint256 amountForEcoPool = amount.mul(25).div(100);
        IERC20(govToken).safeTransfer(address(msg.sender), amount.sub(amountForEcoPool));
        IERC20(govToken).safeTransfer(ecosystemPool, amountForEcoPool);

        emit EmergencyWithdraw(msg.sender, amount);
    }
}
