// because we're using TS, we have to import test things from Buidler
import {web3, artifacts, contract} from "@nomiclabs/buidler";
import * as assert from "assert";
const MockDaiToken = artifacts.require('../src/contracts/MockDaiToken')
const EQToken = artifacts.require('../src/contracts/EQToken')
const TokenFarm = artifacts.require('../src/contracts/TokenFarm')

const chai = require('chai')

chai.use(require('chai-as-promised'))
    .should()

require('@openzeppelin/test-helpers/configure')({})

const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers')

function tokens(n: string) {
    return web3.utils.toWei(n, 'ether');
}

contract("Token", accounts => {

    let eqToken: any
    let tokenFarm: any
    let mDaiToken: any
    let platID: number
    const owner:string = accounts[0] 
    const investor:string = accounts[1]
    const investor2:string = accounts[2]

    beforeEach(async () => {
        // Load Contracts

        // use Mock Dai in this example instead of staking
        // some other token.
        mDaiToken = await MockDaiToken.new(tokens('1000000'), {from:owner})

        eqToken = await EQToken.new({from:owner})

        tokenFarm = await TokenFarm.new(eqToken.address, {from: owner})

        await tokenFarm.authorizeToken(mDaiToken.address, {from: owner})

        platID = await eqToken.platinumID()

    })

    describe('authorizeToken', () => {
        it('owner can authorize new tokens', async () => {
            const newToken = await MockDaiToken.new(tokens('1000'), {from: owner})
            await tokenFarm.authorizeToken(newToken.address, {from: owner})

            const isAllowed = await tokenFarm.tokenIsAllowed(newToken.address)

            assert.equal(isAllowed, true)
        })

        it('non-owner cannot authorize a token', async () => {
            const newToken = await MockDaiToken.new(tokens('1000'), {from: owner})

            await expectRevert(
                tokenFarm.authorizeToken(newToken.address, {from: investor}),
                "Ownable: caller is not the owner"
            )
        })

        it('unauthorized tokens are not allowed', async () => {
            const newToken = await MockDaiToken.new(tokens('1000'), {from: owner})

            const isAllowed = await tokenFarm.tokenIsAllowed(newToken.address)

            assert.equal(isAllowed, false)
        })
    })

    describe('getMockDai', () => {
        it('should give user mock dai', async () => {
            await mDaiToken.getMockDai(investor2, tokens('10'))

            const b = await mDaiToken.balanceOf(investor2)

            assert.equal(b.toString(), tokens('10'))
        })
    })

    describe('stakeTokens()', () => {
        it('should stake tokens', async () => {
            await mDaiToken.getMockDai(investor, tokens('10'))
            await mDaiToken.approve(tokenFarm.address, tokens('10'), {from: investor})
            await tokenFarm.stakeTokens(tokens('10'), mDaiToken.address, { from: investor })

            // verify the staking balance
            {
                const b = await tokenFarm.stakingBalance(mDaiToken.address, investor)
                assert.equal(b.toString(), tokens('10'))
            }

            // verify the mDaiToken ownership:
            {
                const b = await mDaiToken.balanceOf(tokenFarm.address)
                assert.equal(b.toString(), tokens('10'))
            }
        })

    })

    describe('unstakeTokens', () => {
        it('should unstake all tokens', async () => {
            // stake the tokens
            {
                await mDaiToken.getMockDai(investor, tokens('10'))
                await mDaiToken.approve(tokenFarm.address, tokens('10'), {from: investor})
                await tokenFarm.stakeTokens(tokens('10'), mDaiToken.address, { from: investor })
            }

            // unstake the tokens && verify
            {
                await tokenFarm.unstakeTokens(mDaiToken.address, {from: investor})

                const b = await tokenFarm.stakingBalance(mDaiToken.address, investor)
                assert.equal(b.toString(), tokens('0'))
            }
        })

        it('should disallow unstaking if investor does not have any tokens staked', async () => {

            // unstake the tokens && verify
            {
                await expectRevert(
                    tokenFarm.unstakeTokens(mDaiToken.address, {from: investor}),
                    'TokenFarm: You don\'t have any tokens to unstake.'
                )
            }
        })

        it('should disallow unstaking if there are unclaimed rewards.', async () => {
            // stake the tokens && distribute rewards
            {
                await mDaiToken.getMockDai(investor, tokens('10'))
                await mDaiToken.approve(tokenFarm.address, tokens('10'), {from: investor})
                await tokenFarm.stakeTokens(tokens('10'), mDaiToken.address, { from: investor })
                await tokenFarm.distributeRewards({from: owner})
            }

            // unstake the tokens && verify
            await expectRevert(
                tokenFarm.unstakeTokens(mDaiToken.address, {from: investor}),
                'TokenFarm: You have unclaimed rewards.'
            )
        })
    })

    describe('claimRewards()', () => {
        it('unstaked users cannot claim rewards', async () => {
            await tokenFarm.distributeRewards({from: owner})

            await expectRevert(
                tokenFarm.claimRewards({from: investor}),
                "TokenFarm: Account isn't active. No tokens are staked."
            )
        })

        it('staked users can claim rewards', async () => {

            // make sure our investor has staked some tokens in the Token Farm
            {
                await mDaiToken.getMockDai(investor, tokens('10'))
                await mDaiToken.getMockDai(investor2, tokens('10'))

                await mDaiToken.approve(tokenFarm.address, tokens('10'), {from: investor})
                await tokenFarm.stakeTokens(tokens('10'), mDaiToken.address, { from: investor })

                // tokens staked by investor2 should not affect the
                // rewards that investor receives.
                await mDaiToken.approve(tokenFarm.address, tokens('10'), {from: investor2})
                await tokenFarm.stakeTokens(tokens('10'), mDaiToken.address, { from: investor2 })
            }

            {
                await tokenFarm.distributeRewards({from: owner})
                await tokenFarm.claimRewards({from:investor})
                const b = await eqToken.balanceOf(investor, platID)
                assert.equal(b.toString(), tokens('10'))
            }

            {
                await tokenFarm.distributeRewards({from: owner})
                await tokenFarm.claimRewards({from:investor})
                const b = await eqToken.balanceOf(investor, platID)
                assert.equal(b.toString(), tokens('20'))
            }

            {
                await tokenFarm.distributeRewards({from: owner})
                await tokenFarm.claimRewards({from:investor})
                const b = await eqToken.balanceOf(investor, platID)
                assert.equal(b.toString(), tokens('30'))
            }
        })
    })

    // Broken
    describe('Farming tokens', async () => {
        it('rewards investors for staking tokens', async () => {
            /* assert.equal(startingBalanceEQToken.toString(), tokens('0'), 'investor wallet starts at 0') */
            /*  */
            /* const res = await tokenFarm.stakeTokens(tokens('100'), mDaiToken.address, { from: investor }) */
        })
    })

})
