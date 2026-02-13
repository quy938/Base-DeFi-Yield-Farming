const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Optional: if you already have tokens, set STAKE_TOKEN and REWARD_TOKEN in .env
  let stakeToken = process.env.STAKE_TOKEN || "";
  let rewardToken = process.env.REWARD_TOKEN || "";

  if (!stakeToken) {
    const Stake = await ethers.getContractFactory("RewardToken");
    const s = await Stake.deploy("StakeToken", "STK");
    await s.deployed();
    stakeToken = s.address;
    console.log("Deployed StakeToken (RewardToken):", stakeToken);
  }

  if (!rewardToken) {
    const Reward = await ethers.getContractFactory("RewardToken");
    const r = await Reward.deploy("RewardToken", "RWD");
    await r.deployed();
    rewardToken = r.address;
    console.log("Deployed RewardToken:", rewardToken);
  }

  const rewardPerBlock = process.env.REWARD_PER_BLOCK
    ? ethers.BigNumber.from(process.env.REWARD_PER_BLOCK)
    : ethers.utils.parseUnits("1", 18);

  const Farm = await ethers.getContractFactory("YieldFarm");
  const farm = await Farm.deploy(stakeToken, rewardToken, rewardPerBlock);
  await farm.deployed();

  console.log("YieldFarm:", farm.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      StakeToken: stakeToken,
      RewardToken: rewardToken,
      YieldFarm: farm.address
    }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
