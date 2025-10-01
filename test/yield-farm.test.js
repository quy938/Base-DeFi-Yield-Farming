
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Base DeFi Yield Farming", function () {
  let yieldFarm;
  let rewardToken;
  let stakingToken;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // Деплой токенов
    const RewardToken = await ethers.getContractFactory("RewardToken");
    rewardToken = await RewardToken.deploy();
    await rewardToken.deployed();
    
    const StakingToken = await ethers.getContractFactory("StakingToken");
    stakingToken = await StakingToken.deploy();
    await stakingToken.deployed();
    
    // Деплой Yield Farm
    const YieldFarm = await ethers.getContractFactory("YieldFarmV3");
    yieldFarm = await YieldFarm.deploy(
      rewardToken.address,
      stakingToken.address,
      ethers.utils.parseEther("100")
    );
    await yieldFarm.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await yieldFarm.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct parameters", async function () {
      expect(await yieldFarm.rewardToken()).to.equal(rewardToken.address);
      expect(await yieldFarm.stakingToken()).to.equal(stakingToken.address);
      expect(await yieldFarm.rewardPerSecond()).to.equal(ethers.utils.parseEther("100"));
    });
  });

  describe("Pool Management", function () {
    it("Should create a pool", async function () {
      await expect(yieldFarm.createPool(
        stakingToken.address,
        1000,
        ethers.utils.parseEther("10")
      )).to.emit(yieldFarm, "PoolCreated");
    });
  });

  describe("Staking", function () {
    beforeEach(async function () {
      await yieldFarm.createPool(
        stakingToken.address,
        1000,
        ethers.utils.parseEther("10")
      );
    });

    it("Should stake tokens", async function () {
      await stakingToken.mint(addr1.address, ethers.utils.parseEther("1000"));
      await stakingToken.connect(addr1).approve(yieldFarm.address, ethers.utils.parseEther("1000"));
      
      await expect(yieldFarm.connect(addr1).stake(stakingToken.address, ethers.utils.parseEther("100")))
        .to.emit(yieldFarm, "Staked");
    });
  });
});
