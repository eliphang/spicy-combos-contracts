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
        it("should revert with a ValueOutOfRange error", async function () {
            await sc.comboInfo(0, 0, 0, 0, 0, 0).catch(e => {
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

        const premium1 = parseEther('.01')

        before(async function () {
            const [owner] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = true
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
                    premium1,
                    { value: parseEther('.26') }
                )
        })

        describe('withdrawDevFund()', function () {
            var oldDevFundAmount, newDevFundAmount

            before(async function () {
                const [owner, addr1] = signers
                oldDevFundAmount = await owner.getBalance()
                await sc.connect(addr1).withdrawDevFund()
                newDevFundAmount = await owner.getBalance()
            })

            it('the dev fund should increase by the premium deposited', function () {
                expect(oldDevFundAmount.add(premium1)).to.equal(newDevFundAmount)
            })
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

        it('attempting to add a helping without enough deposits should return a "NotEnoughAvailableDeposits" error', async function () {
            const [, addr1] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = false
            const zeroPremium = 0
            var NotEnoughAvailableDeposits
            await sc
                .connect(addr1)
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
                    zeroPremium,
                    { value: parseEther('.24') }
                ).catch(e => {
                    // todo: check e.errorName once this remix IDE bug is resolved https://github.com/ethereum/remix-project/issues/3024
                    NotEnoughAvailableDeposits = true;
                })
            expect(NotEnoughAvailableDeposits).to.be.true;
        })

        it('attempting to add a creator helping when there\'s already an active helping should return a "CreatorOnlyUnsuccessful" error', async function () {
            const [, addr1] = signers
            const doubleHelping = true
            const usingCredits = false
            const creatorOnly = true
            const zeroPremium = 0
            var CreatorOnlyUnsuccessful
            await sc
                .connect(addr1)
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
                    zeroPremium,
                    { value: parseEther('.25') }
                ).catch(e => {
                    // todo: check e.errorName once this remix IDE bug is resolved https://github.com/ethereum/remix-project/issues/3024
                    CreatorOnlyUnsuccessful = true;
                })
            expect(CreatorOnlyUnsuccessful).to.be.true;
        })

        describe("addHelping() after an active creator helping", function () {
            before(async function () {

            })
        })
    })
})
