import { ethers } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, WETH_ADDR } from "./utilities"

describe("LiquidFarmFactory", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.bob = this.signers[1]
        this.dev = this.signers[2]
        this.minter = this.signers[3]
        this.alice = this.signers[4]
        this.transferGovernanceDelay = 60
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
        this.FarmFactory = await ethers.getContractFactory("LiquidFarmFactory")
    })

    beforeEach(async function () {
        this.weth = await ethers.getContractAt("IWETH", WETH_ADDR)
        this.farmFactory = await this.FarmFactory.deploy(
            this.weth.address,
            this.governor.address,
            this.transferGovernanceDelay
        )
        await this.farmFactory.deployed()
        this.flashLP = await this.ERC20Mock.deploy("FlashLiquidity", "FLASH", 1000000000)
        this.rewardsToken = await this.ERC20Mock.deploy("RewardsToken", "MOCK1", 1000000000)
        await this.flashLP.deployed()
        await this.rewardsToken.deployed()
    })

    it("Should allow only Governor to request governance transfer", async function () {
        await expect(
            this.farmFactory.connect(this.bob).setPendingGovernor(this.bob.address)
        ).to.be.revertedWith("NotAuthorized()")
        expect(await this.farmFactory.pendingGovernor()).to.not.be.equal(this.bob.address)
        await this.farmFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        expect(await this.farmFactory.pendingGovernor()).to.be.equal(this.bob.address)
        expect(await this.farmFactory.govTransferReqTimestamp()).to.not.be.equal(0)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.farmFactory.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("ZeroAddress()")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.farmFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.farmFactory.transferGovernance()).to.be.revertedWith("TooEarly()")
        await time.increase(this.transferGovernanceDelay + 1)
        await this.farmFactory.transferGovernance()
        expect(await this.farmFactory.governor()).to.be.equal(this.bob.address)
    })

    it("Should allow only Governor to set free flashloan", async function () {
        expect(await this.farmFactory.isFreeFlashLoan(this.alice.address)).to.be.false
        await expect(
            this.farmFactory.connect(this.bob).setFreeFlashLoan(this.alice.address, true)
        ).to.be.revertedWith("NotAuthorized()")
        await this.farmFactory.connect(this.governor).setFreeFlashLoan(this.alice.address, true)
        expect(await this.farmFactory.isFreeFlashLoan(this.alice.address)).to.be.true
    })

    it("Should allow only Governor to deploy new farms", async function () {
        await expect(
            this.farmFactory
                .connect(this.bob)
                .deploy("TOKEN1-TOKEN2", "stFLASH", this.flashLP.address, this.rewardsToken.address)
        ).to.be.revertedWith("NotAuthorized()")
        expect(await this.farmFactory.lpTokenFarm(this.flashLP.address)).to.be.equal(ADDRESS_ZERO)
        await this.farmFactory
            .connect(this.governor)
            .deploy("TOKEN1-TOKEN2", "stFLASH", this.flashLP.address, this.rewardsToken.address)
        expect(await this.farmFactory.lpTokenFarm(this.flashLP.address)).to.not.be.equal(
            ADDRESS_ZERO
        )
    })

    it("Should not allow to deploy more than one farm per stakingToken", async function () {
        await this.farmFactory
            .connect(this.governor)
            .deploy("TOKEN1-TOKEN2", "stFLASH", this.flashLP.address, this.rewardsToken.address)
        expect(await this.farmFactory.lpTokenFarm(this.flashLP.address)).to.not.be.equal(
            ADDRESS_ZERO
        )
        await expect(
            this.farmFactory
                .connect(this.governor)
                .deploy("TOKEN1-TOKEN2", "stFLASH", this.flashLP.address, this.rewardsToken.address)
        ).to.be.revertedWith("AlreadyDeployed()")
    })
})
