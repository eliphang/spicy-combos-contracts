import { expect } from 'chai'
import { ethers } from 'hardhat'

const {
    utils: { parseEther }
} = ethers

describe('deploy SpicyCombos contract', function () {
    var sc, signers
    const minValue = parseEther('.00001')

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

    describe('deposit()', function () {
        var oldBalance, newBalance, gasCost
        const depositAmount = parseEther('2')
        const effectiveGasPrice = 1

        before(async function () {
            const [owner] = signers
            oldBalance = await owner.getBalance()
            console.log(`old balance ${oldBalance}`);
            const transaction = await sc.connect(owner).deposit({ value: depositAmount })
            const receipt = await transaction.wait()
            gasCost = receipt.gasUsed.mul(effectiveGasPrice)
            newBalance = await owner.getBalance()
            console.log(`new balance ${newBalance}`);
        })
        it('available deposits should equal deposited amount', async function () {
            const [owner] = signers
            const addr = owner.address
            const { 0: availableDeposits } = await sc.balances(addr)
            expect(availableDeposits).to.equal(depositAmount)
        })
        it('outside eth balance should decrease by deposited amount', function () {
            expect(oldBalance.sub(depositAmount).sub(gasCost)).to.equal(newBalance);
        })
    })

    describe("addHelping(), creating 'Burning Chili Tacos with Spicy Cactus Nachos'", function () {
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
    })
})
