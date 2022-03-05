import chai from 'chai'
import { Contract, Wallet, BigNumber, providers } from 'ethers'
import { solidity, deployContract } from 'ethereum-waffle'
import { Address } from 'ethereumjs-util'
import { expandTo18Decimals, expandTo17Decimals } from './utils'
import LOOPStaking from '../build/LOOPStaking.json'
import LOOP from '../build/TestLOOP.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

interface LOOPFixture {
  LOOPToken: Contract
}

interface LOOPStakingFixture {
  LOOPStakingContract: Contract
  LOOPToken: Contract
}

export async function LOOP_fixture([wallet]: Wallet[]): Promise<LOOPFixture> {
  const LOOPToken = await deployContract(wallet, LOOP, ["TestLOOP Token", "TestLOOP"])
  return { LOOPToken }
}

export async function LOOPStaking_fixture([wallet, communityPool, ecosystemPool, reservePool, foundersPool, advisorsPool]: Wallet[]): Promise<LOOPStakingFixture> {
  const { LOOPToken } = await LOOP_fixture([wallet])
  const startTime: number = Math.floor(Date.now() / 1000);
  const _govToken = LOOPToken.address
  const _cap = expandTo18Decimals(145000000)
  const _rewardPerBlock = 1 // rewards amount per Block (currently set 1 as a constant)
  const _stakingStartTimestamp = startTime + 1000 // set staking start time (Unix Timestamp Ex: Fri Feb 18 2022 01:08:16 GMT+0000 = 1645146496)
  const _halvingAfterBlock = 1296000 // 30days block counts
  // 35 months multiplier
  const _rewardMultiplier = [12, 7, 6, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]
  // 35 months Locked (%)
  const _percentLockReward = [95, 93, 91, 89, 87, 85, 83, 81, 79, 77, 75, 73, 71, 69, 67, 65, 63, 61, 59, 57, 55, 53, 51, 49, 47, 45, 43, 41, 39, 37, 35, 33, 31, 29, 27]
  // Staking period when withdrawing: Same Block, <1day >1day >5days >7days >14days >30days
  const _unstakingPeriodStage = [2, 86400, 432000, 640800, 1209600, 2592000]
  // Withdrawal Fees:     25%   8%   4%   2%   1%  0.25% 0.01%
  const _userFeePerPeriodStage = [2500, 800, 400, 200, 100, 25, 1]

  const LOOPStakingContract = await deployContract(wallet, LOOPStaking, [
    _govToken,
    _cap,
    _rewardPerBlock,
    _stakingStartTimestamp,
    _halvingAfterBlock,
    _rewardMultiplier,
    _percentLockReward,
    _unstakingPeriodStage,
    _userFeePerPeriodStage
  ], overrides)
  await LOOPStakingContract.connect(wallet).setDistributionAddress(
    communityPool.address,
    ecosystemPool.address,
    reservePool.address,
    foundersPool.address,
    advisorsPool.address
  ) 
  await LOOPToken.connect(wallet).setstakingContract(LOOPStakingContract.address)
  await LOOPToken.connect(wallet).mintToStakingContract(_cap)
  return { LOOPStakingContract, LOOPToken }
}
