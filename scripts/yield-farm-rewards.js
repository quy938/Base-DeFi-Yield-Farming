// base-defi-yield-farming/scripts/rewards-distribution.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function distributeRewards() {
  console.log("Distributing rewards for Base DeFi Yield Farming...");
  
  const yieldFarmAddress = "0x...";
  const yieldFarm = await ethers.getContractAt("YieldFarmV3", yieldFarmAddress);
  
  // Получение списка пользователей с наградами
  const users = await yieldFarm.getRewardRecipients();
  console.log("Reward recipients:", users.length);
  
  // Распределение наград
  const rewards = [];
  for (let i = 0; i < users.length; i++) {
    const user = users[i];
    const pendingReward = await yieldFarm.calculatePendingReward(user);
    
    if (pendingReward.gt(ethers.utils.parseEther("0.001"))) {
      rewards.push({
        user: user,
        amount: pendingReward.toString(),
        timestamp: Date.now()
      });
      
      console.log(`User ${user} eligible for ${pendingReward.toString()} rewards`);
    }
  }
  
  // Сохранение информации о распределении
  const distributionData = {
    timestamp: new Date().toISOString(),
    totalRecipients: rewards.length,
    totalRewards: rewards.reduce((sum, reward) => sum + parseFloat(reward.amount), 0),
    distributions: rewards
  };
  
  fs.writeFileSync(`./rewards/distribution-${Date.now()}.json`, JSON.stringify(distributionData, null, 2));
  
  console.log(`Rewards distributed to ${rewards.length} users`);
}

distributeRewards()
  .catch(error => {
    console.error("Rewards distribution error:", error);
    process.exit(1);
  });
