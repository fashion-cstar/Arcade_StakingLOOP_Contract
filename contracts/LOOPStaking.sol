// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

contract TestLOOP is ERC20, Ownable {

    address private _stakingContract;

    function setstakingContract(address _staking) public {
        _stakingContract = _staking;
    }
    function preMint(address account, uint256 amount) public {
        require(account == _stakingContract, "Can't premint");

        _mint(account, amount);
    }

    constructor ( string memory _name, string memory _symbol) ERC20(_name, _symbol) {
   
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
    
    function burn(uint256 _amount) external  {
        _burn(msg.sender, _amount);
    }
}

contract LOOPStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        address user;
        uint256 amount; //stacked amount
        uint256 rewardDebt; //return backed total rewards
        uint256 rewardUnlockDebt; //return backed unlock rewards
        uint256 rewardDebtAtTime;
        uint256 lastWithdrawTime;
        uint256 firstDepositTime;
        uint256 lastDepositTime;
        uint256 lastRewardTime;
        uint256 accRewards;
        uint256 accUnlockRewards;     
    }
    struct ClaimHistory {
        address user;
        uint256 amount;
        uint256 datetime;
    }
    ClaimHistory[] public claimHistory;
    
    TestLOOP public govToken;
    uint256 public REWARD_PER_BLOCK; 
    uint256[] public REWARD_MULTIPLIER; // init in constructor function
    uint256[] public HALVING_AT_TIME; // init in constructor function
    uint256[] public unstakingPeriodStage;    
    uint256[] public userFeePerPeriodStage;
    uint256 public FINISH_BONUS_AT_TIME;

    uint256 public HALVING_AFTER_TIME;
    uint256 public totalStacked;
    uint256 public CAP;
    uint256 public START_TIME;

    uint256[] public PERCENT_LOCK_BONUS_REWARD; // lock xx% of bounus reward
    address public communityPool;
    address public ecosystemPool;
    address public reservePool;
    address public foundersPool;
    address public advisorsPool;

    UserInfo[] public userInfo;
    mapping(address => uint256) public userId;

    // struct LockInfo {
    //     address user;
    //     uint256 amount;
    // }
    // LockInfo[] public lockInfo;
    // mapping(address => uint256) public lockId;

    struct _LockInfo{
        uint256 lockedTime;
        uint256 lockedAmount;
    }

    mapping(address => _LockInfo[]) public _lockInfo;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    event SendGovernanceTokenReward(
        address indexed user,
        uint256 amount,
        uint256 lockAmount
    );

    constructor(
        TestLOOP _govToken,
        uint256 _cap,
        uint256 _rewardPerBlock,
        uint256 _rewardStartTimestamp,
        uint256 _halvingAfterBlock,
        uint256[] memory _rewardMultiplier,
        uint256[] memory _percentLockReward,
        uint256[] memory _unstakingPeriodStage,        
        uint256[] memory _userFeePerPeriodStage
    ) {
        require(_rewardStartTimestamp > block.timestamp, "_rewardStartTimestamp must be after block.timestamp!");
        
        govToken = _govToken;
        CAP = _cap;
        REWARD_PER_BLOCK = _rewardPerBlock.mul(10 ** govToken.decimals());
        REWARD_MULTIPLIER = _rewardMultiplier;
        PERCENT_LOCK_BONUS_REWARD = _percentLockReward;
        unstakingPeriodStage = _unstakingPeriodStage;        
        userFeePerPeriodStage = _userFeePerPeriodStage;
        
        HALVING_AFTER_TIME = _halvingAfterBlock * 2;

        START_TIME = _rewardStartTimestamp;

        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtTime = HALVING_AFTER_TIME.mul(i+1).add(START_TIME).add(1);
            HALVING_AT_TIME.push(halvingAtTime);
        }
        FINISH_BONUS_AT_TIME = HALVING_AFTER_TIME
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(START_TIME);
        HALVING_AT_TIME.push(uint256(0));

        govToken.setstakingContract(address(this));
        govToken.preMint(address(this), CAP);
        setOwner(address(0x0806929584025F523Db3F6d80ae7FCAe01220262));
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
    ) public onlyOwner{
        communityPool = _communityPool;
        ecosystemPool = _ecosystemPool;
        reservePool = _reservePool;
        foundersPool = _foundersPool;
        advisorsPool = _advisorsPool;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdate() public {
        uint256 length = userInfo.length;
        for (uint256 i = 0; i < length; ++i) {
            updateInfo(i);
        }
    }

    function setRewardStartTimestamp(uint256 _rewardStartTimestamp) external onlyOwner{
        require(_rewardStartTimestamp > block.timestamp, "_rewardStartTimestamp must be after block.timestamp!");

        START_TIME = _rewardStartTimestamp;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtTime = HALVING_AFTER_TIME.mul(i+1).add(START_TIME).add(1);
            HALVING_AT_TIME[i]=halvingAtTime;
        }
        FINISH_BONUS_AT_TIME = HALVING_AFTER_TIME
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(START_TIME);
        HALVING_AT_TIME[HALVING_AT_TIME.length-1]=(uint256(0));
    }

    //set LOOP Token only by owner
    function setLOOPToken(TestLOOP _govToken) external onlyOwner {
        govToken = _govToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) private view returns (uint256) {
        uint256 result = 0;
        if (_from < START_TIME) return 0;

        for (uint256 i = 0; i < HALVING_AT_TIME.length; i++) {
            uint256 endTime = HALVING_AT_TIME[i];
            if (i > REWARD_MULTIPLIER.length-1) return 0;

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

    function getLockPercentage(uint256 _from, uint256 _to) private view returns (uint256) {
        uint256 result = 0;
        if (_from < START_TIME) return 100;

        for (uint256 i = 0; i < HALVING_AT_TIME.length; i++) {
            uint256 endTime = HALVING_AT_TIME[i];
            if (i > PERCENT_LOCK_BONUS_REWARD.length-1) return 0;

            if (_to <= endTime) {
                return PERCENT_LOCK_BONUS_REWARD[i];
            }
        }

        return result;
    }

    function getReward( uint256 _from, uint256 _to ) private view returns ( uint256 ){
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount = multiplier * REWARD_PER_BLOCK;
        amount = amount.div(2);

        uint256 GovernanceTokenCanMint = CAP - totalStacked;

        if (GovernanceTokenCanMint < amount) 
            return GovernanceTokenCanMint;
        else
            return amount;
    }

    function getClaimHistory() external view returns( ClaimHistory[] memory){
        return claimHistory;
    }

    function getLockedRewards(address user) private view returns(uint256){
        _LockInfo[] memory _info  = _lockInfo[user];
        uint256 amount = 0;

        for(uint256 i=0; i<_info.length; i++){
            amount = amount.add(_info[i].lockedAmount);
        }
        return amount;
    }

    // View function to see pending LOOP on frontend.
    function pendingReward(address _user) external view returns (uint256 pendingUnlocked, uint256 pendingLocked, uint256 availableLockedAmount) {
        uint256 uid = userId[_user];
        if (uid==0){
            pending = 0;
            locked = 0;
            return(pending, locked);
        }
        else { 
            UserInfo memory user = userInfo[uid-1];
            uint256 accAmount = user.accRewards;
            uint256 accUnlockAmount = user.accUnlockRewards;
            uint256 lockPercentage = getLockPercentage(block.timestamp - 1, block.timestamp);
            if (block.timestamp > user.lastRewardTime && user.amount > 0) {
                uint256 GovTokenForFarmer = getReward(
                    user.lastRewardTime,
                    block.timestamp
                );
                accAmount = accAmount.add(
                    GovTokenForFarmer.mul(user.amount).div(totalStacked)
                );
            }            

            uint256 availableLockedAmount = pendingAvailableLockedReward(uid);

            pendingUnlocked = accAmount.sub(user.rewardDebt);
            pendingLocked = pendingUnlocked.mul(lockPercentage).div(100);
            pendingUnlocked = pending.sub(pendingLocked);

            locked = locked.add(getLockedRewards(user.user));
            return (pendingUnlocked, pendingLocked, availableLockedAmount);
        }
    }

    function claimReward() external {
        uint256 uid = userId[address(msg.sender)];
        require(uid > 0, "Not a staker");      
        require(START_TIME < block.timestamp, "Reward not started!");

        updateInfo(uid-1);
        _harvest(uid-1);
    }

    // Update reward variables to be up-to-date.
    function updateInfo(uint256 _uid) private {
        UserInfo storage user = userInfo[_uid];        

        if (block.timestamp <= user.lastRewardTime) {
            return;
        }
        if (user.amount == 0) {
            user.lastRewardTime = block.timestamp;
            return;
        }
        uint256 GovTokenForFarmer  = getReward(user.lastRewardTime, block.timestamp);
        uint256 userNewAccRewards = user.amount.mul(GovTokenForFarmer).div(totalStacked)
        user.accRewards += userNewAccRewards;

        uint256 lockPercentage = 0;
        if (user.rewardDebtAtTime <= FINISH_BONUS_AT_TIME) {
            lockPercentage = getLockPercentage(block.timestamp - 1, block.timestamp);
        }
        uint256 lockAmount = userNewAccRewards.mul(lockPercentage).div(100);

        _LockInfo[] storage _info = _lockInfo[msg.sender];
        _info.push(
            _LockInfo({
                lockedTime: block.timestamp,
                lockedAmount: lockAmount
            })
        );
                    
        user.lastRewardTime = block.timestamp;
    }
    
    function pendingAvailableLockedReward(uint256 _uid) private return (uint256) {
        UserInfo memory _userInfo = userInfo[_uid];

        _LockInfo[] memory _info = _lockInfo[_userInfo.user];
        uint256 lockPeriod = 60*60*24*30*6; //ss*mm*hh*dd*6 months
        uint256 availableLockedAmount = 0;

        for(uint256 i = 0; i < _info.length;){
            if(_info[i].lockedTime > block.timestamp + lockPeriod){
                availableLockedAmount.add(_info[i].lockedAmount);                
            }            
        }

        return availableLockedAmount;
    }

    function unlock(uint256 _uid) private return (uint256) {
        UserInfo storage _userInfo = userInfo[_uid];
        uint256 availableLockedAmount = 0;
        _LockInfo[] storage _info = _lockInfo[_userInfo.user];
        uint256 lockPeriod = 60*60*24*30*6; //ss*mm*hh*dd*6 months

        for(uint256 i = 0; i < _info.length;){
            if(_info[i].lockedTime > block.timestamp + lockPeriod){                
                availableLockedAmount = availableLockedAmount.add(_info[i].lockedAmount);
                _info[i].lockedAmount = 0;                
            }            
        }

        return availableLockedAmount;
    }

    // lock a % of reward if it comes from bonus time.
    function _harvest(uint256 _uid) internal {
        UserInfo storage user = userInfo[_uid];

        if (user.amount > 0) {
            uint256 pending =
                user.accRewards.sub( user.rewardDebt );

            if (pending > 0) {
                uint256 lockPercentage = 0;
                if (user.rewardDebtAtTime <= FINISH_BONUS_AT_TIME) {
                    lockPercentage = getLockPercentage(block.timestamp - 1, block.timestamp);
                }

                uint256 lockAmount = pending.mul(lockPercentage).div(100);

                pending = pending.sub(lockAmount);

                uint256 availableLockedAmount = unlock(_uid);

                pending = pending.add(availableLockedAmount);

                if (pending.sub(lockAmount) > 0){
                    govToken.transfer(msg.sender, pending);
                    claimHistory.push(
                        ClaimHistory({
                        user: msg.sender,
                        amount: pending.sub(lockAmount),
                        datetime: block.timestamp
                    }));
                }                
                user.rewardDebtAtTime = block.timestamp;
                emit SendGovernanceTokenReward(msg.sender, pending, lockAmount);
            }

            // Recalculate the rewardDebt for the user.
            user.rewardDebt = user.accRewards;
        }
    }

    function staking(uint256 _amount) external nonReentrant {    
        require(
            _amount > 0,
            "MasterGardener::deposit: amount must be greater than 0"
        );
        massUpdate();

        uint256 uid = userId[address(msg.sender)];
        uint256 lastRewardTime =
            block.timestamp > START_TIME ? block.timestamp : START_TIME;
        totalStacked = totalStacked.add(_amount);
        if(uid == 0){
            uid = userInfo.length+1;
            userId[address(msg.sender)] = uid;
            userInfo.push(
                UserInfo({
                    user: msg.sender,
                    amount: 0,
                    rewardDebt: 0,
                    rewardDebtAtTime: block.timestamp,
                    lastWithdrawTime: 0,
                    firstDepositTime: 0,
                    lastDepositTime: 0,
                    lastRewardTime: lastRewardTime,
                    accRewards: 0
                })
            );
        }

        UserInfo storage user = userInfo[uid-1];
        user.amount = user.amount.add(_amount);
        if (user.firstDepositTime <= 0)
            user.firstDepositTime = block.timestamp;
        user.lastDepositTime = block.timestamp;

        govToken.transferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        emit Staked(msg.sender, _amount);
    }

    function unstaking(uint256 _amount) external nonReentrant {    
        uint256 uid = userId[address(msg.sender)];
        require(uid>0, "Not a staker");

        massUpdate();

        UserInfo storage user = userInfo[uid-1];
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            totalStacked = totalStacked.sub(_amount);

            uint256 timeDelta;
            if (user.lastWithdrawTime > 0) {
                timeDelta = block.timestamp - user.lastWithdrawTime;
            } else {
                timeDelta = block.timestamp - user.firstDepositTime;
            }

            uint256 userAmount = 0;
            uint256 treasuryAmount = 0;
            
            if (timeDelta <= unstakingPeriodStage[0]) {
                //25% slashing fee if a user withdraws during the same block
                treasuryAmount = _amount.mul(userFeePerPeriodStage[0]).div(10000);
            }
            if (timeDelta>unstakingPeriodStage[0] && timeDelta<=unstakingPeriodStage[1]){
                //8% fee if a user withdraws in less than 1 day
                treasuryAmount = _amount.mul(userFeePerPeriodStage[1]).div(10000);
            }
            if (timeDelta>unstakingPeriodStage[1] && timeDelta<=unstakingPeriodStage[2]){
                //4% fee if a user withdraws after 1 day
                treasuryAmount = _amount.mul(userFeePerPeriodStage[2]).div(10000);
            }
            if (timeDelta>unstakingPeriodStage[2] && timeDelta<=unstakingPeriodStage[3]){
                //2% fee if a user withdraws after 5 days
                treasuryAmount = _amount.mul(userFeePerPeriodStage[3]).div(10000);
            }
            if (timeDelta>unstakingPeriodStage[3] && timeDelta<=unstakingPeriodStage[4]){
                //1% fee if a user deposits and withdraws after 3 days but before 5 days.
                treasuryAmount = _amount.mul(userFeePerPeriodStage[4]).div(10000);
            }
            if (timeDelta>unstakingPeriodStage[4] && timeDelta<=unstakingPeriodStage[5]){
                //0.25% fee if a user deposits and withdraws if the user withdraws after 5 days but before 2 weeks.
                treasuryAmount = _amount.mul(userFeeStage[5]).div(100);
            }
            if (timeDelta>unstakingPeriodStage[5]){

            }
             else if (
                timeDelta >= timeDeltaStartStage[1] &&
                timeDelta <= timeDeltaEndStage[0]
            ) {                
            } else if (
                timeDelta >= timeDeltaStartStage[2] &&
                timeDelta <= timeDeltaEndStage[1]
            ) {
                
            } else if (
                timeDelta >= timeDeltaStartStage[3] &&
                timeDelta <= timeDeltaEndStage[2]
            ) {
                
            } else if (
                timeDelta >= timeDeltaStartStage[4] &&
                timeDelta <= timeDeltaEndStage[3]
            ) {
                
            } else if (
                timeDelta >= timeDeltaStartStage[5] &&
                timeDelta <= timeDeltaEndStage[4]
            ) {

            }  else if (timeDelta > timeDeltaStartStage[6]) {
                //0.01% fee if a user deposits and withdraws after 4 weeks.
                treasuryAmount = _amount.mul(userFeeStage[6]).div(10000);
            }
            userAmount= _amount.sub(treasuryAmount);
            
            govToken.transfer(
                address(msg.sender),
                userAmount
            );

            uint256 burnAmount = treasuryAmount.div(100);
            treasuryAmount = treasuryAmount.sub(burnAmount);

            govToken.transfer(
                address(communityPool),
                treasuryAmount.mul(45).div(100)
            );
            govToken.transfer(
                address(ecosystemPool),
                treasuryAmount.mul(20).div(100)
            );
            govToken.transfer(
                address(reservePool),
                treasuryAmount.mul(15).div(100)
            );
            govToken.transfer(
                address(foundersPool),
                treasuryAmount.mul(15).div(100)
            );
            govToken.transfer(
                address(advisorsPool),
                treasuryAmount.mul(5).div(100)
            );

            govToken.burn(burnAmount);

            emit Unstaked(msg.sender, _amount);
            user.lastWithdrawTime = block.timestamp;
        }
    }
}        
