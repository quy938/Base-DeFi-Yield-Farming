// base-defi-yield-farming/scripts/upgrade.js
const { ethers } = require("hardhat");

async function main() {
  console.log("Upgrading Base DeFi Yield Farming...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Upgrading with the account:", deployer.address);

  // Получаем адрес текущего контракта
  const currentContractAddress = "0x...";
  
  // Деплой нового контракта
  const YieldFarmV4 = await ethers.getContractFactory("YieldFarmV4");
  const newYieldFarm = await YieldFarmV4.deploy(
    "0x...", // rewardToken address
    "0x...", // stakingToken address,
    ethers.utils.parseEther("150") // 150 tokens per second
  );

  await newYieldFarm.deployed();

  console.log("New Base DeFi Yield Farming deployed to:", newYieldFarm.address);
  
  // Перенос данных с старого контракта
  const oldContract = await ethers.getContractAt("YieldFarmV3", currentContractAddress);
  
  // Увеличение комиссии
  console.log("Upgrading fee structure...");
  
  // Сохраняем информацию о обновлении
  const fs = require("fs");
  const upgradeData = {
    oldContract: currentContractAddress,
    newContract: newYieldFarm.address,
    upgradedAt: new Date().toISOString(),
    owner: deployer.address,
    newFeeRate: "0.15%" // 0.15% fee
  };
  
  fs.writeFileSync("./config/upgrade.json", JSON.stringify(upgradeData, null, 2));
  
  console.log("Upgrade completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
