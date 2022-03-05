import chai, { expect } from 'chai'
import { Contract, Wallet, BigNumber, providers } from 'ethers'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { LOOPStaking_fixture, LOOP_fixture } from './fixtures'
import { expandTo18Decimals, mineBlock } from './utils'

describe('LOOPStaking', () => {
    const AddressZero = "0x0000000000000000000000000000000000000000"
    const provider = new MockProvider({
        ganacheOptions: {
            hardfork: 'istanbul',
            mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
            gasLimit: 9999999,
        },
    })

    const [wallet, nonOwner, user1, user2, user3, communityPool, ecosystemPool, reservePool, foundersPool, advisorsPool] = provider.getWallets()

    const loadFixture = createFixtureLoader([wallet, communityPool, ecosystemPool, reservePool, foundersPool, advisorsPool], provider)
    const overrides = {
        gasLimit: 9999999
    }

    let LOOPToken: Contract
    let LOOPStakingContract: Contract
    const currentTime: number = Math.floor(Date.now() / 1000);

    beforeEach(async () => {
        const fixture = await loadFixture(LOOPStaking_fixture)
        LOOPStakingContract = fixture.LOOPStakingContract
        LOOPToken = fixture.LOOPToken
    })

    it('Only owner can set the startStakingTimestamp', async () => {
        await expect(LOOPStakingContract.connect(nonOwner).setRewardStartTimestamp(currentTime))
            .to.revertedWith("Ownable: caller is not the owner");
        await mineBlock(provider, currentTime + 1000);
        await expect(LOOPStakingContract.connect(wallet).setRewardStartTimestamp(currentTime))
            .to.revertedWith('_rewardStartTimestamp must be after block.timestamp!');
        await LOOPStakingContract.connect(wallet).setRewardStartTimestamp(currentTime + 2000)
    })

    it('staking, claiming, pending, unstaking, lockamount, unlockamount, harvest, unlock and unlockAll test', async () => {
        console.log("===transfer LOOP token to user1, user2, user3 for testing===")
        await LOOPToken.connect(wallet).mint(wallet.address, expandTo18Decimals(25000000))
        let balance: BigNumber = await LOOPToken.totalSupply()
        console.log("totalSupply: " + balance.div(BigNumber.from(10).pow(18)).toNumber())
        balance = await LOOPToken.balanceOf(wallet.address)
        console.log("owner balance: " + balance.div(BigNumber.from(10).pow(18)).toNumber())
        balance = await LOOPToken.balanceOf(LOOPStakingContract.address)
        console.log("LOOPStaking contract balance: " + balance.div(BigNumber.from(10).pow(18)).toNumber())
        console.log("==================================\n")
        await LOOPToken.connect(wallet).approve(user1.address, expandTo18Decimals(5000000))
        await LOOPToken.connect(wallet).transfer(user1.address, expandTo18Decimals(5000000))
        await LOOPToken.connect(wallet).approve(user2.address, expandTo18Decimals(5500000))
        await LOOPToken.connect(wallet).transfer(user2.address, expandTo18Decimals(5500000))
        await LOOPToken.connect(wallet).approve(user3.address, expandTo18Decimals(6000000))
        await LOOPToken.connect(wallet).transfer(user3.address, expandTo18Decimals(6000000))
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance: " + balance.div(BigNumber.from(10).pow(18)))
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance: " + balance.div(BigNumber.from(10).pow(18)))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        let rewardStartTime = currentTime + 2000        

        console.log("\n===user1 staked 1000000 before reward starting===")
        await LOOPToken.connect(user1).approve(LOOPStakingContract.address, expandTo18Decimals(1000000))
        await LOOPStakingContract.connect(user1).staking(expandTo18Decimals(1000000))
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")


        console.log("\n===user1 staked 1000000 after 5days since reward starting===")
        let secs = 3600 * 24 * 5
        let blockTime = rewardStartTime + secs
        let blockCounts = secs / 2

        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user1).approve(LOOPStakingContract.address, expandTo18Decimals(1000000))
        await LOOPStakingContract.connect(user1).staking(expandTo18Decimals(1000000))
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 staked 500000 after 8days since reward starting===')
        secs = 3600 * 24 * 8
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user2).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user2).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user1 claimed after 12days since reward starting===')
        secs = 3600 * 24 * 12
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        let res = await LOOPStakingContract.pendingReward(user1.address)
        console.log("user1 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user1).claimReward()
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 staked 1500000 after 18days since reward starting===')
        secs = 3600 * 24 * 18
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user3).approve(LOOPStakingContract.address, expandTo18Decimals(1500000))
        await LOOPStakingContract.connect(user3).staking(expandTo18Decimals(1500000))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 staked 500000 after 25days since reward starting===')
        secs = 3600 * 24 * 25
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user3).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user3).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 staked 2000000 after 35days since reward starting===')
        secs = 3600 * 24 * 35
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user2).approve(LOOPStakingContract.address, expandTo18Decimals(2000000))
        await LOOPStakingContract.connect(user2).staking(expandTo18Decimals(2000000))
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 claimed after 40days since reward starting===')
        secs = 3600 * 24 * 40
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user3.address)
        console.log("user3 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user3).claimReward()
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user1 claimed after 50days since reward starting===')
        secs = 3600 * 24 * 50
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user1.address)
        console.log("user1 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user1).claimReward()
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 staked 500000 after 59days since reward starting===')
        secs = 3600 * 24 * 59
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user3).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user3).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 claimed after 65days since reward starting===')
        secs = 3600 * 24 * 65
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user2.address)
        console.log("user2 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user2).claimReward()
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user1 unstaked 1000000 after 70days since reward starting===')
        secs = 3600 * 24 * 70
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPStakingContract.connect(user1).unstaking(expandTo18Decimals(1000000))
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after unstaked: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")
        balance = await LOOPToken.balanceOf(communityPool.address)
        console.log("communityPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(ecosystemPool.address)
        console.log("ecosystemPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(reservePool.address)
        console.log("reservePool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(foundersPool.address)
        console.log("foundersPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(advisorsPool.address)
        console.log("advisorsPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        console.log("==================================\n")

        console.log('\n===user1 staked 500000 after 120days since reward starting===')
        secs = 3600 * 24 * 120
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user1).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user1).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 staked 500000 after 180days since reward starting===')
        secs = 3600 * 24 * 180
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user2).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user2).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 claimed after 200days since reward starting===')
        secs = 3600 * 24 * 200
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user2.address)
        console.log("user2 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user2).claimReward()
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user1 claimed after 210days since reward starting===')
        secs = 3600 * 24 * 210
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user1.address)
        console.log("user1 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user1).claimReward()
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 staked 500000 after 220days since reward starting===')
        secs = 3600 * 24 * 220
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPToken.connect(user3).approve(LOOPStakingContract.address, expandTo18Decimals(500000))
        await LOOPStakingContract.connect(user3).staking(expandTo18Decimals(500000))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after staking: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 unstaked 1000000 after 220days 20hours since reward starting===')
        secs = 3600 * 24 * 220 + 3600 * 20
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        await LOOPStakingContract.connect(user3).unstaking(expandTo18Decimals(1000000))
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after unstaked: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")
        balance = await LOOPToken.balanceOf(communityPool.address)
        console.log("communityPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(ecosystemPool.address)
        console.log("ecosystemPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(reservePool.address)
        console.log("reservePool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(foundersPool.address)
        console.log("foundersPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        balance = await LOOPToken.balanceOf(advisorsPool.address)
        console.log("advisorsPool balance after unstaked: " + (balance.div(BigNumber.from(10).pow(16)).toNumber()) / 100)
        console.log("==================================\n")

        console.log('\n===user3 claimed after 250days since reward starting===')
        secs = 3600 * 24 * 250
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user3.address)
        console.log("user3 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user3).claimReward()
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user1 total locked rewards after 250days since reward starting===')
        secs = 3600 * 24 * 250
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.getLockedRewards(user1.address)
        console.log("user1 total locked rewards: " + res.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 total locked rewards after 260days since reward starting===')
        secs = 3600 * 24 * 260
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.getLockedRewards(user2.address)
        console.log("user2 total locked rewards: " + res.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")


        console.log('\n===user1 claimed after 42months since reward starting===')
        secs = 3600 * 24 * 30 * 42
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user1.address)
        console.log("user1 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user1 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user1).claimReward()
        balance = await LOOPToken.balanceOf(user1.address)
        console.log("user1 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user2 claimed after 42months since reward starting===')
        secs = 3600 * 24 * 30 * 42
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user2.address)
        console.log("user2 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user2 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user2).claimReward()
        balance = await LOOPToken.balanceOf(user2.address)
        console.log("user2 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")

        console.log('\n===user3 claimed after 42months since reward starting===')
        secs = 3600 * 24 * 30 * 42
        blockTime = rewardStartTime + secs
        blockCounts = secs / 2
        await mineBlock(provider, blockTime);
        res = await LOOPStakingContract.pendingReward(user3.address)
        console.log("user3 pendingUnlocked rewards: " + res.pendingUnlocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 pendingLocked rewards: " + res.pendingLocked.div(BigNumber.from(10).pow(18)))
        console.log("user3 availableLockedAmount rewards: " + res.availableLockedAmount.div(BigNumber.from(10).pow(18)))
        await LOOPStakingContract.connect(user3).claimReward()
        balance = await LOOPToken.balanceOf(user3.address)
        console.log("user3 balance after claiming: " + balance.div(BigNumber.from(10).pow(18)))
        console.log("==================================\n")        
        
        console.log('\n===user1 claimed history since reward starting===')
        res = await LOOPStakingContract.connect(wallet).getClaimHistory()
        let user1Claimed = res.filter((item: any) => item.user === user1.address)
        let sum = 0, total=0
        console.log("\nuser1 claimed history: ")
        user1Claimed.map((item: any) => {
            console.log("\t" + item.amount.div(BigNumber.from(10).pow(18)) + "   " + (new Date(item.datetime.toNumber() * 1000)).toLocaleString('en-GB', { timeZone: 'UTC' }))
            sum += item.amount.div(BigNumber.from(10).pow(18)).toNumber()
        })
        total+=sum
        console.log("\t user1 total rewards: " + sum)
        let user2Claimed = res.filter((item: any) => item.user === user2.address)
        sum=0
        console.log("\nuser2 claimed history: ")
        user2Claimed.map((item: any) => {
            console.log("\t" + item.amount.div(BigNumber.from(10).pow(18)) + "   " + (new Date(item.datetime.toNumber() * 1000)).toLocaleString('en-GB', { timeZone: 'UTC' }))
            sum += item.amount.div(BigNumber.from(10).pow(18)).toNumber()
        })
        total+=sum
        console.log("\t user2 total rewards: " + sum)
        let user3Claimed = res.filter((item: any) => item.user === user3.address)
        sum=0
        console.log("\nuser3 claimed history: ")
        user3Claimed.map((item: any) => {
            console.log("\t" + item.amount.div(BigNumber.from(10).pow(18)) + "   " + (new Date(item.datetime.toNumber() * 1000)).toLocaleString('en-GB', { timeZone: 'UTC' }))
            sum += item.amount.div(BigNumber.from(10).pow(18)).toNumber()
        })
        total+=sum
        console.log("\t user2 total rewards: " + sum)
        console.log("\n\t total claimed rewards: "+total)
        console.log("==================================\n")
    })
})
