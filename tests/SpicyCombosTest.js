import { expect } from 'chai';
import { ethers } from 'hardhat';

const { utils: { parseEther } } = ethers;

describe("SpicyCombos", function () {
    var sc, signers;

    before(async function () {
        signers = await ethers.getSigners();

        const SpicyCombos = await ethers.getContractFactory("SpicyCombos");
        sc = await SpicyCombos.deploy(parseEther('.00001'));
        await sc.deployed();
    });

    it("minValue", async function () {
        const minValue = await sc.minValue();
        expect(minValue).to.equal(parseEther('.00001'));
    });

    describe("deposit() eth", function () {
        before(async function () {
            const [owner] = signers;
            await sc.connect(owner).deposit({ value: parseEther('2') });
        });
        it("check available deposits", async function () {
            const [owner] = signers;
            const addr = owner.address;
            const { 0: availableDeposits } = await sc.balances(addr);
            expect(availableDeposits).to.equal(parseEther('2'));
        });
    });
});