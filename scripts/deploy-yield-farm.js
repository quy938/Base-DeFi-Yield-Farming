
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying Yield Farm...");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

 
  const RewardToken = await ethers.getContractFactory("RewardToken");
  const rewardToken = await RewardToken.deploy();
  await rewardToken.deployed();
  
  const StakingToken = await ethers.getContractFactory("StakingToken");
  const stakingToken = await StakingToken.deploy();
  await stakingToken.deployed();


  const YieldFarm = await ethers.getContractFactory("YieldFarmV2");
  const yieldFarm = await YieldFarm.deploy(
    rewardToken.address,
    stakingToken.address,
    ethers.utils.parseEther("100") 
  );

  await yieldFarm.deployed();

  console.log("Yield Farm deployed to:", yieldFarm.address);
  console.log("Reward Token deployed to:", rewardToken.address);
  console.log("Staking Token deployed to:", stakingToken.address);


  const fs = require("fs");
  const data = {
    yieldFarm: yieldFarm.address,
    rewardToken: rewardToken.address,
    stakingToken: stakingToken.address,
    owner: deployer.address
  };
  
  fs.writeFileSync("./config/deployment.json", JSON.stringify(data, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
