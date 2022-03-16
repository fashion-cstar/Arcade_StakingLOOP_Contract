import chai from 'chai'
import { Contract, Wallet, BigNumber, providers } from 'ethers'
import { solidity, deployContract } from 'ethereum-waffle'
import { Address } from 'ethereumjs-util'
import { expandTo18Decimals, expandTo17Decimals } from './utils'
import LoopStaking from '../build/LoopStaking.json'
import LOOP from '../build/LoopToken.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

interface LOOPFixture {
  LoopToken: Contract
}

interface LoopStakingFixture {
  LoopStakingContract: Contract
  LoopToken: Contract
  _govToken: string
  _halvingAfterBlock: number
  _rewardMultiplier: number[]
  _percentLockReward: number[]
  _unstakingPeriodStage: number[]
  _userFeePerPeriodStage: number[]
}

export async function LoopToken_fixture([wallet]: Wallet[]): Promise<LOOPFixture> {
  const LoopToken = await deployContract(wallet, LOOP)
  return { LoopToken }
}

export async function LoopStaking_fixture([wallet, communityPool, ecosystemPool, reservePool, foundersPool, advisorsPool]: Wallet[]): Promise<LoopStakingFixture> {
  const { LoopToken } = await LoopToken_fixture([wallet])
  const startTime: number = Math.floor(Date.now() / 1000);
  const _govToken = LoopToken.address
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
  // Withdrawal Fees:     25%   8%      4%      2%      1%        0.25%   0.01%
  const _userFeePerPeriodStage = [2500, 800, 400, 200, 100, 25, 1] //percentage * 100

  const LoopStakingContract = await deployContract(wallet, LoopStaking, [
    _govToken,
    _rewardPerBlock,
    _stakingStartTimestamp,
    _halvingAfterBlock,
    _oneblocktime,
    _rewardMultiplier,
    _percentLockReward,
    _unstakingPeriodStage,
    _userFeePerPeriodStage
  ], overrides)
  await LoopStakingContract.connect(wallet).setDistributionAddress(
    communityPool.address,
    ecosystemPool.address,
    reservePool.address,
    foundersPool.address,
    advisorsPool.address
  )
  await LoopToken.connect(wallet).setMinterRole(LoopStakingContract.address)
  await LoopToken.connect(wallet).updateCap(expandTo18Decimals(1145000000)) //1000000000 Loops pre-minted to the owner in LoopToken Constructor
  return { LoopStakingContract, LoopToken, _govToken, _halvingAfterBlock, _rewardMultiplier, _percentLockReward, _unstakingPeriodStage, _userFeePerPeriodStage }
}
