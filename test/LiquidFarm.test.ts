import { ethers } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"

describe("LiquidFarm", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.bob = this.signers[1]
        this.jack = this.signers[2]
        this.minter = this.signers[3]
        this.alice = this.signers[4]
        this.transferGovernanceDelay = 60
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
        this.FarmFactory = await ethers.getContractFactory("LiquidFarmFactory")
        this.VaultMock = await ethers.getContractFactory("VaultMock")
        this.FlashLoanerMock = await ethers.getContractFactory("FlashLoanerMock")
        this.WETH = await ethers.getContractFactory("WETH9")
    })

    beforeEach(async function () {
        this.weth = await this.WETH.deploy()
        await this.weth.deployed()
        this.farmFactory = await this.FarmFactory.deploy(
            this.weth.address,
            this.governor.address,
            this.transferGovernanceDelay
        )
        await this.farmFactory.deployed()
        this.flashLP = await this.ERC20Mock.deploy("FlashLiquidity", "FLASH", 1e15)
        this.rewardsToken = await this.ERC20Mock.deploy("RewardsToken", "MOCK1", 1e15)
        await this.flashLP.deployed()
        await this.rewardsToken.deployed()
        this.flashLP.connect(this.minter).transfer(this.bob.address, 1e12)
        this.flashLP.connect(this.minter).transfer(this.alice.address, 1e12)
        this.flashLP.connect(this.minter).transfer(this.jack.address, 1e13)
        await this.farmFactory
            .connect(this.governor)
            .deploy("MOCK1-MOCK2", "stFLASH", this.flashLP.address, this.rewardsToken.address)
        const farmAddr = await this.farmFactory.lpTokenFarm(this.flashLP.address)
        this.farm = await ethers.getContractAt("LiquidFarm", farmAddr)
    })

    it("Should set farmsFactory correctly", async function () {
        expect(await this.farm.farmsFactory()).to.equal(this.farmFactory.address)
    })

    it("Should not allow to stake 0", async function () {
        await expect(this.farm.connect(this.bob).stake(0)).to.be.revertedWith("StakingZero()")
    })

    it("Should mint stFLASH amount equal to FLASH LP staked ", async function () {
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        expect(await this.flashLP.balanceOf(this.bob.address)).to.be.equal(0)
        expect(await this.farm.balanceOf(this.bob.address)).to.be.equal(1e12)
    })

    it("Should burn stFLASH amount equal to FLASH LP withdrawed ", async function () {
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        await this.farm.connect(this.bob).withdraw(1e12)
        expect(await this.flashLP.balanceOf(this.bob.address)).to.be.equal(1e12)
        expect(await this.farm.balanceOf(this.bob.address)).to.be.equal(0)
    })

    it("Earned function return value should be greater than 0 after staking", async function () {
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e6)
        await this.farm.connect(this.bob).stake(1e6)
        await time.increase(60)
        expect(await this.farm.earned(this.bob.address)).to.not.be.equal(0)
    })

    it("Should not allow to withdraw if nothing staked", async function () {
        await expect(this.farm.connect(this.bob).withdraw(1)).to.be.revertedWith(
            "ERC20: burn amount exceeds balance"
        )
    })

    it("Should not allow to withdraw zero", async function () {
        await expect(this.farm.connect(this.bob).withdraw(0)).to.be.revertedWith(
            "WithdrawingZero()"
        )
    })

    it("exit() should retrieve rewards and staked tokens", async function () {
        await this.rewardsToken.connect(this.minter).transfer(this.farm.address, 1e6)
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        await time.increase(86400)
        await this.flashLP.connect(this.alice).approve(this.farm.address, 1e12)
        await this.farm.connect(this.alice).stake(1e12)
        await time.increase(86400)
        expect(await this.farm.earnedRewardToken(this.bob.address)).to.be.equal(750002)
        expect(await this.farm.earnedRewardToken(this.alice.address)).to.be.equal(249997)
        await this.farm.connect(this.bob).exit()
        await this.farm.connect(this.alice).exit()
        expect(await this.rewardsToken.balanceOf(this.bob.address)).to.be.equal(750001)
        expect(await this.rewardsToken.balanceOf(this.alice.address)).to.be.equal(249999)
        expect(await this.rewardsToken.balanceOf(this.farm.address)).to.be.equal(0)
    })

    it("Should not revert due to overflow when staking for a long period", async function () {
        await this.rewardsToken.connect(this.minter).transfer(this.farm.address, 1e6)
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        await time.increase(864000000)
        expect(await this.farm.earned(this.bob.address)).to.be.equal("86400000000000000000000")
        await this.farm.connect(this.bob).exit()
        expect(await this.rewardsToken.balanceOf(this.bob.address)).to.be.equal(1e6)
    })

    it("Should not allow to transfer stFLASH, after staking or claiming rewards, before transferLock period", async function () {
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        await this.farm.connect(this.bob).getReward()
        const timestamp = await this.farm.getTransferUnlockTime(this.bob.address)
        await expect(
            this.farm.connect(this.bob).transfer(this.alice.address, 1e12)
        ).to.be.revertedWith("TransferLocked(" + timestamp + ")")
        await time.increase(86400 * 7)
        await this.farm.connect(this.bob).transfer(this.alice.address, 1e12)
        expect(await this.farm.balanceOf(this.alice.address)).to.be.equal(1e12)
        expect(await this.farm.balanceOf(this.bob.address)).to.be.equal(0)
    })

    it("Should reduce attempts to extract rewards from contracts (eg vaults/pools)", async function () {
        this.vault = await this.VaultMock.deploy(this.farm.address)
        await this.vault.deployed()
        await this.rewardsToken.connect(this.minter).transfer(this.farm.address, 1e6)
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.flashLP.connect(this.alice).approve(this.farm.address, 1e12)
        await this.flashLP.connect(this.jack).approve(this.farm.address, 1e13)
        await this.farm.connect(this.bob).stake(1e12)
        await this.farm.connect(this.alice).stake(1e12)
        await this.farm.connect(this.jack).stake(1e13)
        await time.increase(86400 * 7)
        await this.farm.connect(this.bob).approve(this.vault.address, 1e15)
        await this.farm.connect(this.alice).approve(this.vault.address, 1e15)
        await this.vault.connect(this.alice).deposit(1e12)
        for (let i = 1; i < 3; i++) {
            await this.rewardsToken.connect(this.minter).transfer(this.farm.address, 1e6)
            await time.increase(86400 * 7)
            await this.vault.connect(this.bob).deposit(1e12)
            await this.vault.connect(this.bob).withdraw(1e12)
            await this.farm.connect(this.bob).getReward()
            const timestamp = await this.farm.getTransferUnlockTime(this.bob.address)
            await expect(this.vault.connect(this.bob).deposit(1e12)).to.be.revertedWith(
                "TransferLocked(" + timestamp + ")"
            )
        }
        await this.vault.connect(this.alice).withdraw(1e12)
        await this.farm.connect(this.alice).getReward()
        await this.farm.connect(this.jack).getReward()
        expect(await this.rewardsToken.balanceOf(this.bob.address)).to.be.equal(333335)
        expect(await this.rewardsToken.balanceOf(this.alice.address)).to.be.equal(166667)
        expect(await this.rewardsToken.balanceOf(this.jack.address)).to.be.equal(2499997)
    })

    it("Should charge 4bps fee for flashloans except exempted addresses", async function () {
        this.flashLoaner = await this.FlashLoanerMock.deploy(this.farm.address)
        await this.flashLoaner.deployed()
        await this.rewardsToken.connect(this.minter).transfer(this.flashLoaner.address, 1e10)
        await this.rewardsToken.connect(this.minter).transfer(this.farm.address, 1e12)
        await this.farm
            .connect(this.bob)
            .flashLoan(
                this.flashLoaner.address,
                this.flashLoaner.address,
                1e12,
                ethers.utils.formatBytes32String("")
            )
        expect(await this.rewardsToken.balanceOf(this.flashLoaner.address)).to.be.equal(96e8)
        await this.flashLoaner.setIgnoreFee(true)
        await expect(
            this.farm
                .connect(this.bob)
                .flashLoan(
                    this.flashLoaner.address,
                    this.flashLoaner.address,
                    1e12,
                    ethers.utils.formatBytes32String("")
                )
        ).to.be.revertedWith("FlashLoanNotRepaid()")
        await this.farmFactory.connect(this.governor).setFreeFlashLoan(this.bob.address, true)
        await this.farm
            .connect(this.bob)
            .flashLoan(
                this.flashLoaner.address,
                this.flashLoaner.address,
                1e12,
                ethers.utils.formatBytes32String("")
            )
    })
})

describe("ArbitrageFarm (WETH rewards case)", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.bob = this.signers[1]
        this.jack = this.signers[2]
        this.minter = this.signers[3]
        this.alice = this.signers[4]
        this.transferGovernanceDelay = 60
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
        this.FarmFactory = await ethers.getContractFactory("LiquidFarmFactory")
        this.VaultMock = await ethers.getContractFactory("VaultMock")
        this.FlashLoanerMock = await ethers.getContractFactory("FlashLoanerMock")
        this.WETH = await ethers.getContractFactory("WETH9")
    })

    beforeEach(async function () {
        this.weth = await this.WETH.deploy()
        await this.weth.deployed()
        this.farmFactory = await this.FarmFactory.deploy(
            this.weth.address,
            this.governor.address,
            this.transferGovernanceDelay
        )
        await this.farmFactory.deployed()
        this.flashLP = await this.ERC20Mock.deploy("FlashLiquidity", "FLASH", 1e15)
        await this.flashLP.deployed()
        this.flashLP.connect(this.minter).transfer(this.bob.address, 1e12)
        this.flashLP.connect(this.minter).transfer(this.alice.address, 1e12)
        this.flashLP.connect(this.minter).transfer(this.jack.address, 1e13)
        await this.farmFactory
            .connect(this.governor)
            .deploy("MOCK1-MOCK2", "stFLASH", this.flashLP.address, this.weth.address)
        const farmAddr = await this.farmFactory.lpTokenFarm(this.flashLP.address)
        this.farm = await ethers.getContractAt("LiquidFarm", farmAddr)
    })

    it("exit() should retrieve rewards and staked tokens", async function () {
        await this.weth.connect(this.minter).deposit({ value: ethers.utils.parseEther("1") })
        await this.weth
            .connect(this.minter)
            .transfer(this.farm.address, ethers.utils.parseEther("1"))
        await this.flashLP.connect(this.bob).approve(this.farm.address, 1e12)
        await this.farm.connect(this.bob).stake(1e12)
        await time.increase(86400)
        await this.flashLP.connect(this.alice).approve(this.farm.address, 1e12)
        await this.farm.connect(this.alice).stake(1e12)
        await time.increase(86400)
        await this.farm.connect(this.bob).exit()
        await this.farm.connect(this.alice).exit()
        expect(await ethers.provider.getBalance(this.bob.address)).to.be.equal(
            ethers.utils.parseUnits("10000746455217102813319", "wei")
        )
        expect(await ethers.provider.getBalance(this.alice.address)).to.be.equal(
            ethers.utils.parseUnits("10000248727683813299557", "wei")
        )
        expect(await this.weth.balanceOf(this.farm.address)).to.be.equal(0)
        expect(await ethers.provider.getBalance(this.farm.address)).to.be.equal(0)
    })
})
