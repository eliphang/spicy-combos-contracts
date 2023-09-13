import { expect } from 'chai'
import { ethers } from 'hardhat'

const {
    utils: { parseEther },
} = ethers

describe('deploy SpicyCombos contract', function () {
    var sc, signers
    const minValue = parseEther('.000001')

    before(async function () {
        signers = await ethers.getSigners()

        const SpicyCombos = await ethers.getContractFactory('SpicyCombos')
        sc = await SpicyCombos.deploy(minValue)
        await sc.deployed()
    })
    it('minValue from getter should equal minValue supplied to constructor', async function () {
        const minValueFromContract = await sc.minValue()
        expect(minValueFromContract).to.equal(minValue)
    })
    describe('attempting to get comboInfo() for a combo with values out of range', async function () {
        it('should revert with a ValueOutOfRange error', async function () {
            await sc.comboInfo(0, 0, 0, 0, 0, 0).catch((e) => {
                expect(e.errorName).to.equal('ValueOutOfRange')
                expect(e.errorArgs[0]).to.equal('amountDigit1')
            })
        })
    })
    describe('deposit()', function () {
        var oldBalance, newBalance, gasCost
        const depositAmount = parseEther('2')

        before(async function () {
            const [owner] = signers
            console.log('owner', owner)
            oldBalance = await owner.getBalance()
            const gasPrice = await owner.getGasPrice()
            console.log(`old balance ${oldBalance}`)
            const transaction = await sc.connect(owner).deposit({ value: depositAmount })
            const receipt = await transaction.wait()
            gasCost = receipt.gasUsed.mul(gasPrice)
            newBalance = await owner.getBalance()
            console.log(`new balance ${newBalance}`)
        })
        it('available deposits should equal deposited amount', async function () {
            const [owner] = signers
            const addr = owner.address
            const { 0: availableDeposits } = await sc.balances(addr)
            expect(availableDeposits).to.equal(depositAmount)
        })
        it('outside eth balance should decrease by deposited amount', function () {
            expect(oldBalance.sub(depositAmount).sub(gasCost)).to.equal(newBalance)
        })
        describe('withdraw() what was deposited', function () {
            var oldBalance, newBalance, gasCost

            before(async function () {
                const [owner] = signers
                console.log('owner', owner)
                oldBalance = await owner.getBalance()
                const gasPrice = await owner.getGasPrice()
                console.log(`old balance ${oldBalance}`)
                const transaction = await sc.connect(owner).withdraw(depositAmount)
                const receipt = await transaction.wait()
                gasCost = receipt.gasUsed.mul(gasPrice)
                newBalance = await owner.getBalance()
                console.log(`new balance ${newBalance}`)
            })
            it('available deposits should equal zero', async function () {
                const [owner] = signers
                const addr = owner.address
                const { 0: availableDeposits } = await sc.balances(addr)
                expect(availableDeposits).to.equal(0)
            })
            it('outside eth balance should increase by withdrawn amount', function () {
                expect(oldBalance.add(depositAmount).sub(gasCost)).to.equal(newBalance)
            })
        })
    })
    describe('addHelping(), creating "Burning Chili Tacos with Spicy Cactus Nachos"', function () {
        // .25 eth  "Burning Chili Tacos"
        const amountDigit1 = 2
        const amountDigit2 = 5
        const amountZeros = 4

        // 150 block time limit "Spicy Cactus Nachos"
        const blocksDigit1 = 1
        const blocksDigit2 = 5
        const blocksZeros = 1

        var comboPrice

        const premium = (x) => parseEther(0.01 * x + '')

        before(async function () {
            const [owner] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = true

            comboPrice = await sc.computePrice(amountDigit1, amountDigit2, amountZeros)

            await sc
                .connect(owner)
                .addHelping(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    doubleHelping,
                    usingCredits,
                    creatorOnly,
                    premium(1),
                    { value: comboPrice.add(premium(1)) }
                )
        })
        it('the active helping owner should be us', async function () {
            const [owner] = signers
            const { 3: activeHelpingOwner } = await sc.comboInfo(
                amountDigit1,
                amountDigit2,
                amountZeros,
                blocksDigit1,
                blocksDigit2,
                blocksZeros
            )
            expect(activeHelpingOwner).to.equal(owner.address)
        })
        it('our helping should have the creator bonus (1 deposit)', async function () {
            const [owner] = signers
            const { 5: activeHelpingDeposits } = await sc.comboInfo(
                amountDigit1,
                amountDigit2,
                amountZeros,
                blocksDigit1,
                blocksDigit2,
                blocksZeros
            )
            expect(activeHelpingDeposits).to.equal(1)
        })
        it('attempting to add a helping without enough deposits should return a "NotEnoughAvailableDeposits" error', async function () {
            const [, account2] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = false
            var NotEnoughAvailableDeposits
            await sc
                .connect(account2)
                .addHelping(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    doubleHelping,
                    usingCredits,
                    creatorOnly,
                    premium(0),
                    { value: comboPrice.div(2) }
                )
                .catch((e) => {
                    // todo: check e.errorName once this remix IDE bug is resolved https://github.com/ethereum/remix-project/issues/3024
                    NotEnoughAvailableDeposits = true
                })
            expect(NotEnoughAvailableDeposits).to.be.true
        })
        it('attempting to add a creator helping when there\'s already an active helping should return a "CreatorOnlyUnsuccessful" error', async function () {
            const [, account2] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = true
            var CreatorOnlyUnsuccessful
            await sc
                .connect(account2)
                .addHelping(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    doubleHelping,
                    usingCredits,
                    creatorOnly,
                    premium(0),
                    { value: comboPrice }
                )
                .catch((e) => {
                    // todo: check e.errorName once this remix IDE bug is resolved https://github.com/ethereum/remix-project/issues/3024
                    CreatorOnlyUnsuccessful = true
                })
            expect(CreatorOnlyUnsuccessful).to.be.true
        })
        describe('withdrawDevFund()', function () {
            var oldDevFundAmount, newDevFundAmount

            before(async function () {
                const [owner, account2] = signers
                oldDevFundAmount = await owner.getBalance()
                await sc.connect(account2).withdrawDevFund()
                newDevFundAmount = await owner.getBalance()
            })

            it('the dev fund should increase by the premium deposited', function () {
                expect(oldDevFundAmount.add(premium(1))).to.equal(newDevFundAmount)
            })
        })
        describe('addHelping() the only helping after an active creator helping', function () {
            before(async function () {
                const [, account2] = signers
                const doubleHelping = true
                const usingCredits = false
                const creatorOnly = false
                await sc
                    .connect(account2)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        doubleHelping,
                        usingCredits,
                        creatorOnly,
                        premium(0),
                        { value: comboPrice }
                    )
            })
            it('should result in our helping being the active helping', async function () {
                const [, account2] = signers
                const { 3: activeHelpingOwner } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(activeHelpingOwner).to.equal(account2.address)
            })
            it('the active helping should have zero deposits', async function () {
                const { 5: activeHelpingDeposits } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(activeHelpingDeposits).to.equal(0)
            })
            it('the queue length should still be zero', async function () {
                const [, account2] = signers
                const { 0: queueLength } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(queueLength).to.equal(0)
            })
            it('our helping should exist', async function () {
                const [, account2] = signers
                const { 0: exists } = await sc.helpingInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    account2.address
                )
                expect(exists).to.be.true
            })
            it('the active helping should not be expired', async function () {
                const { 7: activeHelpingIsExpired } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(activeHelpingIsExpired).to.be.false
            })
            it('the previous active helping should not exist', async function () {
                const [owner] = signers
                const { 0: exists } = await sc.helpingInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    owner.address
                )
                expect(exists).to.be.false
            })
        })
        describe('addHelping() first helping after a non-creator helping', function () {
            before(async function () {
                const [, , account3] = signers
                const doubleHelping = false
                const usingCredits = false
                const creatorOnly = false
                await sc
                    .connect(account3)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        doubleHelping,
                        usingCredits,
                        creatorOnly,
                        premium(3),
                        { value: comboPrice.add(premium(3)) }
                    )
            })
            it('should result in a queue of length one', async function () {
                const { 0: queueLength } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(queueLength).to.equal(1)
            })
            it('we should not be the active helping owner', async function () {
                const [, , account3] = signers
                const { 3: activeHelpingOwner } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(activeHelpingOwner).to.not.equal(account3.address)
            })
            it('the premium of the first queue entry should be our premium', async function () {
                const { 1: premium_ } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(premium_).to.equal(premium(3))
            })
            it('our helping should exist', async function () {
                const [, , account3] = signers
                const { 0: exists } = await sc.helpingInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    account3.address
                )
                expect(exists).to.be.true
            })
            it('the active helping should have one deposit', async function () {
                const { 5: activeHelpingDeposits } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(activeHelpingDeposits).to.equal(1)
            })
        })
        describe('addHelping() the second helping after a non-creator double helping', function () {
            before(async function () {
                const [, , , account4] = signers
                const doubleHelping = true
                const usingCredits = false
                const creatorOnly = false
                await sc
                    .connect(account4)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        doubleHelping,
                        usingCredits,
                        creatorOnly,
                        premium(4),
                        { value: comboPrice.add(premium(4)) }
                    )
            })
            it('should result in a queue of length one', async function () {
                const { 0: queueLength } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(queueLength).to.equal(1)
            })
            it('the premium of the first queue entry should be our premium', async function () {
                const { 1: premium_ } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(premium_).to.equal(premium(4))
            })
            it('the previous active helping owner should have doubled their available deposits', async function () {
                const [, account2] = signers
                const { 0: availableDeposits } = await sc.balances(account2.address)
                expect(availableDeposits).to.equal(comboPrice.mul(2))
            })
        })
        describe('addHelping() with the highest current premium', function () {
            before(async function () {
                const [, , , , account5] = signers
                const doubleHelping = true
                const usingCredits = false
                const creatorOnly = false
                await sc
                    .connect(account5)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        doubleHelping,
                        usingCredits,
                        creatorOnly,
                        premium(5),
                        { value: comboPrice.add(premium(5)) }
                    )
            })
            it('should move our helping into the front of the queue', async function () {
                const { 1: premium_ } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(premium_).to.equal(premium(5))
            })
        })
        describe('increasePremium() to new high', function () {
            const oldPremium = premium(4)
            const increaseByAmount = parseEther('.01444')
            const newPremium = oldPremium.add(increaseByAmount)

            before(async function () {
                const [, , , account4] = signers
                await sc
                    .connect(account4)
                    .increasePremium(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        increaseByAmount,
                        { value: increaseByAmount }
                    )
            })
            it('should move us to the front of the queue', async function () {
                const { 1: premium_ } = await sc.comboInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros
                )
                expect(premium_).to.equal(newPremium)
            })
        })
        describe('removeHelping() from queue', function () {
            before(async function () {
                const [, , , , account5] = signers
                await sc
                    .connect(account5)
                    .removeHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros
                    )
            })
            it('should give us credits', async function () {
                const [, , , , account5] = signers
                const { 2: availableCredits } = await sc.balances(account5.address)
                expect(availableCredits).to.equal(comboPrice)
            })
        })
        describe('addHelping() with credits', function () {
            var oldActiveHelpingDeposits, newActiveHelpingDeposits

            before(async function () {
                const [, , , , account5] = signers
                const doubleHelping = true
                const usingCredits = true
                const creatorOnly = false
                    ; ({ 5: oldActiveHelpingDeposits } = await sc.comboInfo(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros
                    ))
                await sc
                    .connect(account5)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        doubleHelping,
                        usingCredits,
                        creatorOnly,
                        premium(6),
                        { value: premium(6) }
                    )
                    ; ({ 5: newActiveHelpingDeposits } = await sc.comboInfo(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros
                    ))
            })
            it('should not give a deposit to the active helping', function () {
                expect(oldActiveHelpingDeposits).to.equal(newActiveHelpingDeposits);
            })
            it('helpingInfo() should say the helping is usingCredits', async function () {
                const [, , , , account5] = signers
                const { 2: usingCredits } = await sc.helpingInfo(
                    amountDigit1,
                    amountDigit2,
                    amountZeros,
                    blocksDigit1,
                    blocksDigit2,
                    blocksZeros,
                    account5.address
                );
                expect(usingCredits).to.be.true
            })
        })
    })
})
