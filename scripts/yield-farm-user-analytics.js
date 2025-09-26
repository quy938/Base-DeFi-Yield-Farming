// base-defi-yield-farming/scripts/user-analytics.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeYieldFarmUserBehavior() {
  console.log("Analyzing user behavior for Base DeFi Yield Farming...");
  
  const yieldFarmAddress = "0x...";
  const yieldFarm = await ethers.getContractAt("YieldFarmV3", yieldFarmAddress);
  
  // Анализ пользовательского поведения
  const userAnalytics = {
    timestamp: new Date().toISOString(),
    yieldFarmAddress: yieldFarmAddress,
    userDemographics: {},
    engagementMetrics: {},
    stakingPatterns: {},
    userSegments: {},
    recommendations: []
  };
  
  try {
    // Демография пользователей
    const userDemographics = await yieldFarm.getUserDemographics();
    userAnalytics.userDemographics = {
      totalUsers: userDemographics.totalUsers.toString(),
      activeUsers: userDemographics.activeUsers.toString(),
      newUsers: userDemographics.newUsers.toString(),
      returningUsers: userDemographics.returningUsers.toString(),
      userDistribution: userDemographics.userDistribution
    };
    
    // Метрики вовлеченности
    const engagementMetrics = await yieldFarm.getEngagementMetrics();
    userAnalytics.engagementMetrics = {
      avgSessionTime: engagementMetrics.avgSessionTime.toString(),
      dailyActiveUsers: engagementMetrics.dailyActiveUsers.toString(),
      weeklyActiveUsers: engagementMetrics.weeklyActiveUsers.toString(),
      monthlyActiveUsers: engagementMetrics.monthlyActiveUsers.toString(),
      userRetention: engagementMetrics.userRetention.toString(),
      engagementScore: engagementMetrics.engagementScore.toString()
    };
    
    // Паттерны стейкинга
    const stakingPatterns = await yieldFarm.getStakingPatterns();
    userAnalytics.stakingPatterns = {
      avgStakeAmount: stakingPatterns.avgStakeAmount.toString(),
      stakingFrequency: stakingPatterns.stakingFrequency.toString(),
      popularPools: stakingPatterns.popularPools,
      peakStakingHours: stakingPatterns.peakStakingHours,
      averageStakingPeriod: stakingPatterns.averageStakingPeriod.toString(),
      withdrawalRate: stakingPatterns.withdrawalRate.toString()
    };
    
    // Сегментация пользователей
    const userSegments = await yieldFarm.getUserSegments();
    userAnalytics.userSegments = {
      casualStakers: userSegments.casualStakers.toString(),
      activeFarmers: userSegments.activeFarmers.toString(),
      longTermStakers: userSegments.longTermStakers.toString(),
      shortTermTraders: userSegments.shortTermTraders.toString(),
      highValueStakers: userSegments.highValueStakers.toString(),
      segmentDistribution: userSegments.segmentDistribution
    };
    
    // Анализ поведения
    if (parseFloat(userAnalytics.engagementMetrics.userRetention) < 70) {
      userAnalytics.recommendations.push("Low user retention - implement retention strategies");
    }
    
    if (parseFloat(userAnalytics.stakingPatterns.withdrawalRate) > 30) {
      userAnalytics.recommendations.push("High withdrawal rate - improve user retention");
    }
    
    if (parseFloat(userAnalytics.userSegments.highValueStakers) < 50) {
      userAnalytics.recommendations.push("Low high-value stakers - focus on premium user acquisition");
    }
    
    if (userAnalytics.userSegments.casualStakers > userAnalytics.userSegments.activeFarmers) {
      userAnalytics.recommendations.push("More casual stakers than active farmers - consider farmer engagement");
    }
    
    // Сохранение отчета
    const analyticsFileName = `yield-user-analytics-${Date.now()}.json`;
    fs.writeFileSync(`./analytics/${analyticsFileName}`, JSON.stringify(userAnalytics, null, 2));
    console.log(`User analytics report created: ${analyticsFileName}`);
    
    console.log("Yield farming user analytics completed successfully!");
    console.log("Recommendations:", userAnalytics.recommendations);
    
  } catch (error) {
    console.error("User analytics error:", error);
    throw error;
  }
}

analyzeYieldFarmUserBehavior()
  .catch(error => {
    console.error("User analytics failed:", error);
    process.exit(1);
  });
