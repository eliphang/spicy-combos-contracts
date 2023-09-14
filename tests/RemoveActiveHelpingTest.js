import { expect } from 'chai'
import { ethers } from 'hardhat'

const {
    utils: { parseEther },
} = ethers

describe('deploy SpicyCombos contract', function () {
    var sc, signers
    const minValue = parseEther('.00000001')

    before(async function () {
        signers = await ethers.getSigners()
        const SpicyCombos = await ethers.getContractFactory('SpicyCombos')
        sc = await SpicyCombos.deploy(minValue)
        await sc.deployed()
    })

    describe('addHelping(), creating "Zesty Shrimp Stew"', function () {
        // 4.4 eth  "Zesty Shrimp Stew"
        const amountDigit1 = 4
        const amountDigit2 = 4
        const amountZeros = 5

        // adjust the block time limit to experiment with timed helpings
        const blocksDigit1 = 2
        const blocksDigit2 = 5
        const blocksZeros = 0

        var comboPrice

        const premium = (x) => parseEther(0.001 * x + '')

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
                    premium(0),
                    { value: comboPrice.add(premium(0)) }
                )
        })
        describe('removeHelping() removing an active double helping with a creator bonus and no follow-on helpings', function () {
            before(async function () {
                const [owner] = signers
                await sc
                    .connect(owner)
                    .removeHelping(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
            })
            it('should return the deposit', async function () {
                const [owner] = signers
                const { 0: availableDeposits } = await sc.balances(owner.address)
                expect(availableDeposits).to.equal(comboPrice)
            })
        })
        describe('addHelping() adding another double helping after one with creator bonus', function () {
            before(async function () {
                const [, account2, account3] = signers
                const doubleHelping = true
                const timedHelping = false
                const usingCredits = false
                const creatorOnlyOne = true
                const creatorOnlyTwo = false

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
                        creatorOnlyOne,
                        premium(0),
                        { value: comboPrice.add(premium(0)) }
                    )

                await sc
                    .connect(account3)
                    .addHelping(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros,
                        timedHelping,
                        usingCredits,
                        creatorOnlyTwo,
                        premium(0),
                        { value: comboPrice.add(premium(0)) }
                    )
            })
            it('should result in an active helping with no creator bonus (no deposits received)', async function () {
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
            it('the previous active helping owner should have doubled their deposit', async function () {
                const [, account2] = signers
                const { 0: availableDeposits } = await sc.balances(account2.address)
                expect(availableDeposits).to.equal(comboPrice.mul(2))
            })
            describe('removeHelping() removing an expired timed helping with one deposit received', async function () {
                before(async function () {
                    const [owner, , account3, account4] = signers
                    const timedHelping = false
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
                            timedHelping,
                            usingCredits,
                            creatorOnly,
                            premium(0),
                            { value: comboPrice.add(premium(0)) }
                        )
                    // deposit a bunch of times to make more blocks pass
                    const numTransactionsToWaste = 80;
                    for (let i = 0; i < numTransactionsToWaste; ++i) {
                        await sc.connect(owner).deposit({ value: premium(.001) })
                    }
                    // needs to have expired. play with the block time in the combo definition
                    await sc
                        .connect(account3)
                        .removeHelping(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
                })
                it('should result in getting your deposit back', async function () {
                    const [, , account3] = signers
                    const { 0: availableDeposits } = await sc.balances(account3.address)
                    expect(availableDeposits).to.equal(comboPrice)
                })
                it('the helping that made the deposit should be the active helping now', async function () {
                    const account4 = signers[3]
                    const { 3: activeHelpingOwner } = await sc.comboInfo(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros
                    )
                    expect(activeHelpingOwner).to.equal(account4.address)
                })
            })
            describe('removeHelping() removing an expired timed helping with three deposits received', async function () {
                before(async function () {
                    const [owner,,,account4] = signers
                    const timedHelping = true
                    const usingCredits = false
                    const creatorOnly = false
                    for (let i = 0; i < 3; ++i) {
                        await sc
                            .connect(signers[i + 4])
                            .addHelping(
                                amountDigit1,
                                amountDigit2,
                                amountZeros,
                                blocksDigit1,
                                blocksDigit2,
                                blocksZeros,
                                timedHelping,
                                usingCredits,
                                creatorOnly,
                                premium(0),
                                { value: comboPrice.add(premium(0)) }
                            )
                    }
                    // deposit a bunch of times to make more blocks pass
                    const numTransactionsToWaste = 80;
                    for (let i = 0; i < numTransactionsToWaste; ++i) {
                        await sc.connect(owner).deposit({ value: premium(.001) })
                    }
                    // needs to have expired. play with the block time in the combo definition
                    await sc
                        .connect(account4)
                        .removeHelping(amountDigit1, amountDigit2, amountZeros, blocksDigit1, blocksDigit2, blocksZeros)
                })
                it('should result in deposit back plus 90% of the next two deposits', async function () {
                    const account4 = signers[3]
                    const { 0: availableDeposits } = await sc.balances(account4.address)
                    expect(availableDeposits).to.equal(comboPrice.add(comboPrice.mul(2 * 9).div(10)))
                })
                it('next active helping should be the first one added to the queue', async function () {
                    const account5 = signers[4]
                    const { 3: activeHelpingOwner } = await sc.comboInfo(
                        amountDigit1,
                        amountDigit2,
                        amountZeros,
                        blocksDigit1,
                        blocksDigit2,
                        blocksZeros
                    )
                    expect(activeHelpingOwner).to.equal(account5.address)
                })
            })
        })
    })
})
