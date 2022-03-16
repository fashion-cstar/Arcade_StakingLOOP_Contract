import { ethers, upgrades } from 'hardhat'
import { BigNumber } from 'ethers'

function expandTo18Decimals(n: number) {
    return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

function expandTo17Decimals(n: number) {
    return BigNumber.from(n).mul(BigNumber.from(10).pow(17))
}

async function main() {

    const [deployer] = await ethers.getSigners()

    if (deployer === undefined) throw new Error('Deployer is undefined.')
    console.log('Deploying contracts with the account:', deployer.address)
    console.log('Account balance:', (await deployer.getBalance()).toString())

    const LoopToken = await ethers.getContractFactory('LoopToken')
    const LoopTokenDeployed = await LoopToken.deploy()
    console.log('LoopToken:', LoopTokenDeployed.address);

    const startTime: number = Math.floor(Date.now() / 1000);
    const _govToken = LoopTokenDeployed.address
    const _cap = expandTo18Decimals(145000000)
    const _rewardPerBlock = 1 // rewards amount per Block (currently set 1 as a constant)
    const _oneblocktime = 2 // block time (Harmony block time is 2s)
    const _stakingStartTimestamp = startTime + 1000 // set staking start time (Unix Timestamp Ex: Fri Feb 18 2022 01:08:16 GMT+0000 = 1645146496)
    const _halvingAfterBlock = 1296000 // 30days block counts
    // 35 months multiplier
    const _rewardMultiplier = [12, 7, 6, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
    // 35 months Locked (%)
    const _percentLockReward = [95, 93, 91, 89, 87, 85, 83, 81, 79, 77, 75, 73, 71, 69, 67, 65, 63, 61, 59, 57, 55, 53, 51, 49, 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 27]
    // Staking period when withdrawing: Same Block, <1day >1day >5days >7days >14days >30days
    const _unstakingPeriodStage = [86400, 432000, 640800, 1209600, 2592000]
    // Withdrawal Fees:     25%   8%   4%   2%   1%  0.25% 0.01%
    const _userFeePerPeriodStage = [2500, 800, 400, 200, 100, 25, 1] //percentage * 100

    const LoopStaking = await ethers.getContractFactory('LoopStaking')
    const LoopStakingDeployed = await LoopStaking.deploy(
        _govToken,
        _rewardPerBlock,
        _stakingStartTimestamp,
        _halvingAfterBlock,
        _oneblocktime,
        _rewardMultiplier,
        _percentLockReward,
        _unstakingPeriodStage,
        _userFeePerPeriodStage
    )
    console.log('LoopStaking:', LoopStakingDeployed.address);

    const communityPool = "0x1CE9a65c6b32aB58ad748AC3E3dbE9c15E112182"
    const ecosystemPool = "0x1CE9a65c6b32aB58ad748AC3E3dbE9c15E112182"
    const reservePool = "0x1CE9a65c6b32aB58ad748AC3E3dbE9c15E112182"
    const foundersPool = "0x1CE9a65c6b32aB58ad748AC3E3dbE9c15E112182"
    const advisorsPool = "0x1CE9a65c6b32aB58ad748AC3E3dbE9c15E112182"
    await LoopStakingDeployed.setDistributionAddress(
        communityPool,
        ecosystemPool,
        reservePool,
        foundersPool,
        advisorsPool
    )
    LoopStakingDeployed.setOwner("0x0806929584025F523Db3F6d80ae7FCAe01220262");
    await LoopTokenDeployed.setMinterRole(LoopStakingDeployed.address)    
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })
