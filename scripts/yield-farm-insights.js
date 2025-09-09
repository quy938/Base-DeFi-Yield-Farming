// base-defi-yield-farming/scripts/insights.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function generateYieldInsights() {
  console.log("Generating insights for Base DeFi Yield Farming...");
  
  const yieldFarmAddress = "0x...";
  const yieldFarm = await ethers.getContractAt("YieldFarmV3", yieldFarmAddress);
  
  // Получение инсайтов
  const insights = {
    timestamp: new Date().toISOString(),
    yieldFarmAddress: yieldFarmAddress,
    performanceInsights: {},
    riskMetrics: {},
    optimizationSuggestions: [],
    marketComparison: {}
  };
  
  // Показатели производительности
  const performanceInsights = await yieldFarm.getPerformanceInsights();
  insights.performanceInsights = {
    totalStaked: performanceInsights.totalStaked.toString(),
    totalRewards: performanceInsights.totalRewards.toString(),
    avgAPR: performanceInsights.avgAPR.toString(),
    totalUsers: performanceInsights.totalUsers.toString(),
    rewardRate: performanceInsights.rewardRate.toString()
  };
  
  // Риск-метрики
  const riskMetrics = await yieldFarm.getRiskMetrics();
  insights.riskMetrics = {
    volatility: riskMetrics.volatility.toString(),
    liquidityRisk: riskMetrics.liquidityRisk.toString(),
    smartContractRisk: riskMetrics.smartContractRisk.toString(),
    marketRisk: riskMetrics.marketRisk.toString()
  };
  
  // Предложения по оптимизации
  const optimizationSuggestions = await yieldFarm.getOptimizationSuggestions();
  insights.optimizationSuggestions = optimizationSuggestions;
  
  // Сравнение с рынком
  const marketComparison = await yieldFarm.getMarketComparison();
  insights.marketComparison = {
    aprVsMarket: marketComparison.aprVsMarket.toString(),
    riskVsMarket: marketComparison.riskVsMarket.toString(),
    performanceRanking: marketComparison.performanceRanking.toString()
  };
  
  // Генерация рекомендаций
  if (parseFloat(insights.performanceInsights.avgAPR) < 1000) { // 10%
    insights.optimizationSuggestions.push("Increase reward rates to improve competitiveness");
  }
  
  if (parseFloat(insights.riskMetrics.volatility) > 500) { // 5%
    insights.optimizationSuggestions.push("Implement risk mitigation strategies");
  }
  
  // Сохранение инсайтов
  const fileName = `insights-${Date.now()}.json`;
  fs.writeFileSync(`./insights/${fileName}`, JSON.stringify(insights, null, 2));
  
  console.log("Yield farming insights generated successfully!");
  console.log("File saved:", fileName);
}

generateYieldInsights()
  .catch(error => {
    console.error("Insights error:", error);
    process.exit(1);
  });
