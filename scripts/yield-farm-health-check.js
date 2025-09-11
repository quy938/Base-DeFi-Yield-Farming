// base-crosschain-bridge/scripts/monitoring.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function monitorBridgeOperations() {
  console.log("Monitoring Base Cross-Chain Bridge operations...");
  
  const bridgeAddress = "0x...";
  const bridge = await ethers.getContractAt("CrossChainBridgeV3", bridgeAddress);
  
  // Мониторинг операций
  const monitoringReport = {
    timestamp: new Date().toISOString(),
    bridgeAddress: bridgeAddress,
    operationalStatus: {},
    transactionMetrics: {},
    chainStatus: [],
    performanceIndicators: {},
    alerts: [],
    recommendations: []
  };
  
  try {
    // Статус операций
    const operationalStatus = await bridge.getOperationalStatus();
    monitoringReport.operationalStatus = {
      isOperational: operationalStatus.isOperational,
      lastHeartbeat: operationalStatus.lastHeartbeat.toString(),
      uptime: operationalStatus.uptime.toString(),
      maintenanceMode: operationalStatus.maintenanceMode
    };
    
    // Метрики транзакций
    const transactionMetrics = await bridge.getTransactionMetrics();
    monitoringReport.transactionMetrics = {
      totalTransactions: transactionMetrics.totalTransactions.toString(),
      successfulTransactions: transactionMetrics.successfulTransactions.toString(),
      failedTransactions: transactionMetrics.failedTransactions.toString(),
      successRate: transactionMetrics.successRate.toString(),
      avgProcessingTime: transactionMetrics.avgProcessingTime.toString(),
      totalVolume: transactionMetrics.totalVolume.toString()
    };
    
    // Статус цепочек
    const chainCount = await bridge.getChainCount();
    monitoringReport.chainStatus = [];
    
    for (let i = 0; i < Math.min(10, chainCount.toNumber()); i++) {
      const chainStatus = await bridge.getChainStatus(i);
      monitoringReport.chainStatus.push({
        chainId: i,
        isActive: chainStatus.isActive,
        lastSync: chainStatus.lastSync.toString(),
        syncStatus: chainStatus.syncStatus.toString(),
        transactionCount: chainStatus.transactionCount.toString(),
        errorCount: chainStatus.errorCount.toString()
      });
    }
    
    // Показатели производительности
    const performanceIndicators = await bridge.getPerformanceIndicators();
    monitoringReport.performanceIndicators = {
      avgResponseTime: performanceIndicators.avgResponseTime.toString(),
      maxResponseTime: performanceIndicators.maxResponseTime.toString(),
      throughput: performanceIndicators.throughput.toString(),
      latency: performanceIndicators.latency.toString(),
      errorRate: performanceIndicators.errorRate.toString()
    };
    
    // Проверка на тревоги
    if (parseFloat(monitoringReport.transactionMetrics.failedTransactions) > 10) {
      monitoringReport.alerts.push("High number of failed transactions detected");
    }
    
    if (parseFloat(monitoringReport.performanceIndicators.errorRate) > 5) {
      monitoringReport.alerts.push("High error rate detected");
    }
    
    if (parseFloat(monitoringReport.performanceIndicators.avgResponseTime) > 5000) {
      monitoringReport.alerts.push("Slow response times detected");
    }
    
    // Рекомендации
    if (monitoringReport.alerts.length > 0) {
      monitoringReport.recommendations.push("Immediate investigation required for alerts");
    }
    
    if (parseFloat(monitoringReport.performanceIndicators.errorRate) > 2) {
      monitoringReport.recommendations.push("Implement error handling improvements");
    }
    
    // Сохранение отчета
    const monitoringFileName = `bridge-monitoring-${Date.now()}.json`;
    fs.writeFileSync(`./monitoring/${monitoringFileName}`, JSON.stringify(monitoringReport, null, 2));
    console.log(`Monitoring report created: ${monitoringFileName}`);
    
    console.log("Bridge monitoring completed successfully!");
    console.log("Alerts:", monitoringReport.alerts.length);
    console.log("Recommendations:", monitoringReport.recommendations);
    
  } catch (error) {
    console.error("Monitoring error:", error);
    throw error;
  }
}

monitorBridgeOperations()
  .catch(error => {
    console.error("Monitoring failed:", error);
    process.exit(1);
  });
