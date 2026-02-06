// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract YieldFarmV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct Pool {
        IERC20 token;
        uint256 totalStaked;
        uint256 rewardPerSecond;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 periodFinish;
        uint256 allocPoint;
        uint256 lastRewardTime;
        bool enabled;
        uint256 apr;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastRewardTime;
        uint256 pendingRewards;
        uint256 totalRewardsReceived;
        uint256 firstStakeTime;
    }

    struct PoolInfo {
        address token;
        uint256 allocPoint;
        uint256 rewardRate;
        uint256 apr;
        uint256 totalStaked;
        bool enabled;
    }

    mapping(address => Pool) public pools;
    mapping(address => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256[]) public userPools;
    
    IERC20 public rewardToken;
    IERC20 public stakingToken;
    
    uint256 public totalAllocPoints;
    uint256 public rewardPerSecond;
    uint256 public constant MAX_ALLOC_POINTS = 100000;
    uint256 public constant MAX_REWARD_RATE = 1000000000000000000000; // 1000 tokens per second
    

    uint256 public minimumStakeAmount;
    uint256 public maximumStakeAmount;
    uint256 public performanceFee;
    uint256 public withdrawalFee;
    uint256 public lockupPeriod;
    
    // Events
    event PoolCreated(address indexed token, uint256 allocPoint, uint256 rewardRate, uint256 apr);
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 reward);
    event EmergencyWithdraw(address indexed user, address indexed token, uint256 amount);
    event PoolUpdated(address indexed token, uint256 allocPoint, uint256 rewardRate);
    event RewardRateUpdated(uint256 newRate);
    event FeeUpdated(uint256 performanceFee, uint256 withdrawalFee);
    event LockupPeriodUpdated(uint256 newPeriod);
    event PoolDisabled(address indexed token);
    event PoolEnabled(address indexed token);
    event WithdrawalLocked(address indexed user, address indexed token, uint256 unlockTime);

    constructor(
        address _rewardToken,
        address _stakingToken,
        uint256 _rewardPerSecond,
        uint256 _minimumStakeAmount,
        uint256 _maximumStakeAmount
    ) {
        rewardToken = IERC20(_rewardToken);
        stakingToken = IERC20(_stakingToken);
        rewardPerSecond = _rewardPerSecond;
        minimumStakeAmount = _minimumStakeAmount;
        maximumStakeAmount = _maximumStakeAmount;
        performanceFee = 50; // 0.5%
        withdrawalFee = 10; // 0.1%
        lockupPeriod = 30 days; // 30 days lockup
    }

    // Create new pool
    function createPool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate,
        uint256 apr
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        require(apr <= 1000000, "APR too high"); // 10000% max APR
        
        Pool storage pool = pools[token];
        require(pool.token == address(0), "Pool already exists");
        
        pool.token = IERC20(token);
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        pool.lastRewardTime = block.timestamp;
        pool.apr = apr;
        pool.enabled = true;
        
        totalAllocPoints = totalAllocPoints.add(allocPoint);
        
        emit PoolCreated(token, allocPoint, rewardRate, apr);
    }

    // Update pool parameters
    function updatePool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate,
        uint256 apr
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        require(apr <= 1000000, "APR too high");
        
        totalAllocPoints = totalAllocPoints.sub(pool.allocPoint).add(allocPoint);
        
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        pool.apr = apr;
        
        emit PoolUpdated(token, allocPoint, rewardRate);
    }

    // Enable pool
    function enablePool(address token) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        pool.enabled = true;
        emit PoolEnabled(token);
    }

    // Disable pool
    function disablePool(address token) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        pool.enabled = false;
        emit PoolDisabled(token);
    }

    // Stake tokens
    function stake(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(pool.enabled, "Pool disabled");
        require(amount >= minimumStakeAmount, "Amount below minimum");
        require(amount <= maximumStakeAmount, "Amount above maximum");
        require(amount > 0, "Amount must be greater than 0");
        require(pool.token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        if (user.amount > 0) {
            uint256 pending = calculatePendingReward(token, msg.sender);
            if (pending > 0) {
                user.pendingRewards = user.pendingRewards.add(pending);
            }
        }
        
        user.amount = user.amount.add(amount);
        pool.totalStaked = pool.totalStaked.add(amount);
        
        if (user.firstStakeTime == 0) {
            user.firstStakeTime = block.timestamp;
        }
        
        pool.token.transferFrom(msg.sender, address(this), amount);
        user.lastRewardTime = block.timestamp;
        
        // Update user history
        userPools[msg.sender].push(token);
        
        emit Staked(msg.sender, token, amount);
    }

    // Withdraw tokens
    function withdraw(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(pool.enabled, "Pool disabled");
        require(userInfo[token][msg.sender].amount >= amount, "Insufficient balance");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        uint256 pending = calculatePendingReward(token, msg.sender);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        
        // Check lockup period
        if (block.timestamp < user.firstStakeTime.add(lockupPeriod)) {
            uint256 feeAmount = amount.mul(withdrawalFee).div(10000);
            uint256 amountAfterFee = amount.sub(feeAmount);
            
            // Apply fee
            if (feeAmount > 0) {
                pool.token.transfer(owner(), feeAmount);
            }
            
            user.amount = user.amount.sub(amountAfterFee);
            pool.totalStaked = pool.totalStaked.sub(amountAfterFee);
            pool.token.transfer(msg.sender, amountAfterFee);
        } else {
            user.amount = user.amount.sub(amount);
            pool.totalStaked = pool.totalStaked.sub(amount);
            pool.token.transfer(msg.sender, amount);
        }
        
        user.lastRewardTime = block.timestamp;
        
        emit Withdrawn(msg.sender, token, amount);
    }

    // Claim rewards
    function getReward(
        address token
    ) external whenNotPaused nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(pool.enabled, "Pool disabled");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        uint256 pending = calculatePendingReward(token, msg.sender);
        require(pending > 0, "No rewards to claim");
        
        user.pendingRewards = user.pendingRewards.add(pending);
        user.rewardDebt = user.rewardDebt.add(pending);
        user.totalRewardsReceived = user.totalRewardsReceived.add(pending);
        
        // Apply performance fee
        uint256 performanceFeeAmount = pending.mul(performanceFee).div(10000);
        uint256 amountAfterFee = pending.sub(performanceFeeAmount);
        
        if (performanceFeeAmount > 0) {
            rewardToken.transfer(owner(), performanceFeeAmount);
        }
        
        // Transfer rewards
        rewardToken.transfer(msg.sender, amountAfterFee);
        
        emit RewardPaid(msg.sender, token, amountAfterFee);
    }

    // Emergency withdraw (only owner)
    function emergencyWithdraw(
        address token
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        
        UserInfo storage user = userInfo[token][msg.sender];
        uint256 amount = user.amount;
        
        if (amount > 0) {
            user.amount = 0;
            pool.totalStaked = pool.totalStaked.sub(amount);
            pool.token.transfer(msg.sender, amount);
            emit EmergencyWithdraw(msg.sender, token, amount);
        }
    }

    // Update pools
    function updatePool(address token) internal {
        Pool storage pool = pools[token];
        if (block.timestamp <= pool.lastUpdateTime) return;
        
        uint256 timePassed = block.timestamp.sub(pool.lastUpdateTime);
        uint256 newRewards = timePassed.mul(pool.rewardRate);
        
        if (pool.totalStaked > 0) {
            pool.rewardPerTokenStored = pool.rewardPerTokenStored.add(
                newRewards.mul(1e18).div(pool.totalStaked)
            );
        }
        
        pool.lastUpdateTime = block.timestamp;
    }

    // Calculate pending reward
    function calculatePendingReward(
        address token,
        address user
    ) public view returns (uint256) {
        Pool storage pool = pools[token];
        UserInfo storage userInfo = userInfo[token][user];
        
        uint256 rewardPerToken = pool.rewardPerTokenStored;
        uint256 userReward = userInfo.rewardDebt;
        
        if (userInfo.amount > 0) {
            uint256 userEarned = userInfo.amount.mul(rewardPerToken.sub(userReward)).div(1e18);
            return userEarned;
        }
        return 0;
    }

    // Get pool info
    function getPoolInfo(address token) external view returns (PoolInfo memory) {
        Pool storage pool = pools[token];
        return PoolInfo({
            token: address(pool.token),
            allocPoint: pool.allocPoint,
            rewardRate: pool.rewardRate,
            apr: pool.apr,
            totalStaked: pool.totalStaked,
            enabled: pool.enabled
        });
    }

    // Get user info
    function getUserInfo(address token, address user) external view returns (UserInfo memory) {
        return userInfo[token][user];
    }

    // Get user pools
    function getUserPools(address user) external view returns (address[] memory) {
        return userPools[user];
    }

    // Set reward rate
    function setRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= MAX_REWARD_RATE, "Reward rate too high");
        rewardPerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }

    // Set fees
    function setFees(uint256 newPerformanceFee, uint256 newWithdrawalFee) external onlyOwner {
        require(newPerformanceFee <= 1000, "Performance fee too high"); // 10%
        require(newWithdrawalFee <= 1000, "Withdrawal fee too high"); // 10%
        performanceFee = newPerformanceFee;
        withdrawalFee = newWithdrawalFee;
        emit FeeUpdated(newPerformanceFee, newWithdrawalFee);
    }

    // Set lockup period
    function setLockupPeriod(uint256 newPeriod) external onlyOwner {
        lockupPeriod = newPeriod;
        emit LockupPeriodUpdated(newPeriod);
    }

    // Set stake limits
    function setStakeLimits(uint256 newMin, uint256 newMax) external onlyOwner {
        minimumStakeAmount = newMin;
        maximumStakeAmount = newMax;
    }

    // Get farm stats
    function getFarmStats() external view returns (
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 totalUsers,
        uint256 totalPools
    ) {
        totalStaked = 0;
        totalRewards = 0;
        totalUsers = 0;
        totalPools = 0;
        
        for (uint256 i = 0; i < type(uint256).max; i++) {
            if (pools[address(i)].token != address(0)) {
                totalPools++;
                totalStaked = totalStaked.add(pools[address(i)].totalStaked);
            }
        }
        
        return (totalStaked, totalRewards, totalUsers, totalPools);
    }

    // Check if user can claim reward
    function canClaimReward(address token, address user) external view returns (bool) {
        Pool storage pool = pools[token];
        UserInfo storage userInfo = userInfo[token][user];
        if (pool.token == address(0) || !pool.enabled) return false;
        return userInfo.amount > 0;
    }

    // Pause contract
    function pause() external onlyOwner {
        _pause();
    }

    // Unpause contract
    function unpause() external onlyOwner {
        _unpause();
    }
    // Добавить функции:
function calculateDynamicRewardRate(
    address token,
    uint256 liquidity,
    uint256 marketCap,
    uint256 tradingVolume
) external view returns (uint256) {
    // Алгоритм динамического расчета наград
    // Учитывает ликвидность, рыночную капитализацию и объем торгов
    uint256 baseRate = 1000; // 10%
    uint256 liquidityFactor = liquidity / 1000000000000000000; // 1 ETH
    uint256 volumeFactor = tradingVolume / 1000000000000000000; // 1 ETH
    uint256 marketCapFactor = marketCap / 1000000000000000000000; // 1000 ETH
    
    uint256 dynamicRate = baseRate + 
                         (liquidityFactor * 2) + 
                         (volumeFactor / 100) + 
                         (marketCapFactor / 1000);
    
    return dynamicRate > 10000 ? 10000 : dynamicRate; // Максимум 100%
}

function getMarketData(address token) external view returns (
    uint256 liquidity,
    uint256 marketCap,
    uint256 tradingVolume
) {
    
    return (0, 0, 0); // Реализация в будущем
}
// Добавить структуры:
struct VirtualStake {
    uint256 amount;
    uint256 virtualAmount;
    uint256 lastUpdateTime;
    uint256 rewardDebt;
    uint256 pendingRewards;
    uint256 totalRewardsReceived;
    uint256 firstStakeTime;
}

struct AutoReinvestConfig {
    bool enabled;
    uint256 frequency; // seconds
    uint256 minAmount;
    uint256 maxAmount;
    uint256 minAPR;
    bool compoundRewards;
}

// Добавить маппинги:
mapping(address => mapping(address => VirtualStake)) public virtualStakes;
mapping(address => AutoReinvestConfig) public autoReinvestConfigs;

// Добавить события:
event VirtualStakeCreated(
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 virtualAmount
);

event VirtualStakeUpdated(
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 virtualAmount
);

event AutoReinvestEnabled(
    address indexed user,
    address indexed token,
    bool enabled,
    uint256 frequency
);

// Добавить функции:
function createVirtualStake(
    address token,
    uint256 amount,
    uint256 virtualMultiplier
) external {
    require(amount > 0, "Amount must be greater than 0");
    require(token != address(0), "Invalid token");
    
    // Calculate virtual amount
    uint256 virtualAmount = amount * virtualMultiplier / 10000;
    
    VirtualStake storage stake = virtualStakes[token][msg.sender];
    
    stake.amount = stake.amount + amount;
    stake.virtualAmount = stake.virtualAmount + virtualAmount;
    stake.lastUpdateTime = block.timestamp;
    
    if (stake.firstStakeTime == 0) {
        stake.firstStakeTime = block.timestamp;
    }
    
    emit VirtualStakeCreated(msg.sender, token, amount, virtualAmount);
}

function updateVirtualStake(
    address token,
    uint256 amount,
    uint256 virtualMultiplier
) external {
    require(amount > 0, "Amount must be greater than 0");
    
    uint256 virtualAmount = amount * virtualMultiplier / 10000;
    
    VirtualStake storage stake = virtualStakes[token][msg.sender];
    
    stake.amount = stake.amount + amount;
    stake.virtualAmount = stake.virtualAmount + virtualAmount;
    stake.lastUpdateTime = block.timestamp;
    
    emit VirtualStakeUpdated(msg.sender, token, amount, virtualAmount);
}

function enableAutoReinvest(
    address token,
    uint256 frequency,
    uint256 minAmount,
    uint256 maxAmount,
    uint256 minAPR,
    bool compoundRewards
) external {
    require(frequency >= 3600, "Frequency too short (minimum 1 hour)");
    
    autoReinvestConfigs[token] = AutoReinvestConfig({
        enabled: true,
        frequency: frequency,
        minAmount: minAmount,
        maxAmount: maxAmount,
        minAPR: minAPR,
        compoundRewards: compoundRewards
    });
    
    emit AutoReinvestEnabled(msg.sender, token, true, frequency);
}

function autoReinvestRewards(
    address token
) external {
    AutoReinvestConfig storage config = autoReinvestConfigs[token];
    require(config.enabled, "Auto reinvest not enabled");
    
    VirtualStake storage stake = virtualStakes[token][msg.sender];
    require(stake.amount > 0, "No stake to reinvest");
    
    // Check if enough time has passed
    require(block.timestamp >= stake.lastUpdateTime + config.frequency, "Too early for reinvestment");
    
    // Calculate pending rewards
    uint256 pendingRewards = calculatePendingReward(msg.sender, token);
    
    // Check minimum amount
    if (pendingRewards >= config.minAmount && pendingRewards <= config.maxAmount) {
        // Reinvest rewards
        uint256 reinvestAmount = pendingRewards;
        
        if (config.compoundRewards) {
            // Compound rewards by adding to stake
            uint256 virtualMultiplier = 10000; // 100% virtual multiplier
            uint256 virtualAmount = reinvestAmount * virtualMultiplier / 10000;
            
            stake.amount = stake.amount + reinvestAmount;
            stake.virtualAmount = stake.virtualAmount + virtualAmount;
            stake.lastUpdateTime = block.timestamp;
        }
        
        // Reset pending rewards
        stake.pendingRewards = 0;
        stake.totalRewardsReceived = stake.totalRewardsReceived + pendingRewards;
        
        emit AutoReinvestExecuted(msg.sender, token, reinvestAmount, pendingRewards, block.timestamp);
    }
}

function getVirtualStakeInfo(address token, address user) external view returns (VirtualStake memory) {
    return virtualStakes[token][user];
}

function getAutoReinvestConfig(address token) external view returns (AutoReinvestConfig memory) {
    return autoReinvestConfigs[token];
}
    
    // Новые структуры для динамических наград
    struct MarketData {
        uint256 totalLiquidity;
        uint256 marketCap;
        uint256 tradingVolume;
        uint256 priceChange24h;
        uint256 networkActivity;
        uint256 timestamp;
    }
    
    struct DynamicRewardConfig {
        uint256 baseRewardRate;
        uint256 liquidityMultiplier;
        uint256 volumeMultiplier;
        uint256 marketCapMultiplier;
        uint256 priceImpactMultiplier;
        uint256 networkActivityMultiplier;
        uint256 maxRewardRate;
        uint256 minRewardRate;
    }
    
    struct PoolDynamicInfo {
        uint256 poolLiquidity;
        uint256 poolVolume;
        uint256 poolAPR;
        uint256 lastUpdateTime;
        uint256 rewardAdjustment;
    }
    
    // Новые маппинги
    mapping(address => MarketData) public marketData;
    mapping(address => DynamicRewardConfig) public poolRewardConfigs;
    mapping(address => PoolDynamicInfo) public poolDynamicInfo;
    
    // Новые события
    event MarketDataUpdated(
        address indexed token,
        uint256 totalLiquidity,
        uint256 marketCap,
        uint256 tradingVolume,
        uint256 timestamp
    );
    
    event DynamicRewardConfigUpdated(
        address indexed token,
        uint256 baseRewardRate,
        uint256 liquidityMultiplier,
        uint256 volumeMultiplier
    );
    
    event PoolRewardAdjusted(
        address indexed token,
        uint256 newRewardRate,
        uint256 adjustmentReason
    );
    
    // Новые функции для динамических наград
    function setDynamicRewardConfig(
        address token,
        uint256 baseRewardRate,
        uint256 liquidityMultiplier,
        uint256 volumeMultiplier,
        uint256 marketCapMultiplier,
        uint256 priceImpactMultiplier,
        uint256 networkActivityMultiplier,
        uint256 maxRewardRate,
        uint256 minRewardRate
    ) external onlyOwner {
        require(baseRewardRate <= 1000000, "Base reward rate too high");
        require(maxRewardRate >= minRewardRate, "Invalid reward rate limits");
        
        poolRewardConfigs[token] = DynamicRewardConfig({
            baseRewardRate: baseRewardRate,
            liquidityMultiplier: liquidityMultiplier,
            volumeMultiplier: volumeMultiplier,
            marketCapMultiplier: marketCapMultiplier,
            priceImpactMultiplier: priceImpactMultiplier,
            networkActivityMultiplier: networkActivityMultiplier,
            maxRewardRate: maxRewardRate,
            minRewardRate: minRewardRate
        });
        
        emit DynamicRewardConfigUpdated(
            token,
            baseRewardRate,
            liquidityMultiplier,
            volumeMultiplier
        );
    }
    
    function updateMarketData(
        address token,
        uint256 totalLiquidity,
        uint256 marketCap,
        uint256 tradingVolume,
        uint256 priceChange24h,
        uint256 networkActivity
    ) external onlyOwner {
        marketData[token] = MarketData({
            totalLiquidity: totalLiquidity,
            marketCap: marketCap,
            tradingVolume: tradingVolume,
            priceChange24h: priceChange24h,
            networkActivity: networkActivity,
            timestamp: block.timestamp
        });
        
        emit MarketDataUpdated(
            token,
            totalLiquidity,
            marketCap,
            tradingVolume,
            block.timestamp
        );
    }
    
    function calculateDynamicRewardRate(
        address token,
        uint256 poolLiquidity,
        uint256 poolVolume,
        uint256 poolAPR
    ) external view returns (uint256) {
        DynamicRewardConfig storage config = poolRewardConfigs[token];
        MarketData storage market = marketData[token];
        
        if (config.baseRewardRate == 0) {
            return 1000; // 10% по умолчанию
        }
        
       
        uint256 baseReward = config.baseRewardRate;
        
       
        uint256 liquidityFactor = poolLiquidity > 0 ? 
            (poolLiquidity * config.liquidityMultiplier) / 10000 : 0;
            
        // Множитель объема торгов
        uint256 volumeFactor = poolVolume > 0 ? 
            (poolVolume * config.volumeMultiplier) / 1000000 : 0;
            
       
        uint256 marketCapFactor = market.marketCap > 0 ? 
            (market.marketCap * config.marketCapMultiplier) / 1000000000 : 0;
            
        // Множитель влияния цены
        uint256 priceImpactFactor = (market.priceChange24h * config.priceImpactMultiplier) / 10000;
            
        // Множитель активности сети
        uint256 networkFactor = (market.networkActivity * config.networkActivityMultiplier) / 10000;
        
        // Общий коэффициент
        uint256 totalMultiplier = baseReward + 
                                liquidityFactor + 
                                volumeFactor + 
                                marketCapFactor + 
                                priceImpactFactor + 
                                networkFactor;
        
        // Ограничение максимальной и минимальной награды
        uint256 rewardRate = totalMultiplier;
        if (rewardRate > config.maxRewardRate) {
            rewardRate = config.maxRewardRate;
        }
        if (rewardRate < config.minRewardRate) {
            rewardRate = config.minRewardRate;
        }
        
        return rewardRate;
    }
    
    function adjustPoolRewardRate(
        address token,
        uint256 poolLiquidity,
        uint256 poolVolume,
        uint256 poolAPR
    ) external {
        uint256 newRewardRate = calculateDynamicRewardRate(token, poolLiquidity, poolVolume, poolAPR);
        
        // Обновить информацию о пуле
        PoolDynamicInfo storage dynamicInfo = poolDynamicInfo[token];
        dynamicInfo.poolLiquidity = poolLiquidity;
        dynamicInfo.poolVolume = poolVolume;
        dynamicInfo.poolAPR = poolAPR;
        dynamicInfo.lastUpdateTime = block.timestamp;
        dynamicInfo.rewardAdjustment = newRewardRate;
        
        emit PoolRewardAdjusted(token, newRewardRate, 1); // 1 - автоматическое изменение
    }
    
    function getPoolDynamicInfo(address token) external view returns (PoolDynamicInfo memory) {
        return poolDynamicInfo[token];
    }
    
    function getMarketDataInfo(address token) external view returns (MarketData memory) {
        return marketData[token];
    }
    
    function getDynamicRewardConfig(address token) external view returns (DynamicRewardConfig memory) {
        return poolRewardConfigs[token];
    }
    
    function getMarketStats() external view returns (
        uint256 totalLiquidity,
        uint256 totalMarketCap,
        uint256 totalVolume,
        uint256 avgPriceChange,
        uint256 totalNetworkActivity
    ) {
        
        return (0, 0, 0, 0, 0);
    }
    // Добавить в функцию calculatePendingReward
function calculatePendingReward(address user, address token) public view returns (uint256) {
    // Защита от переполнения
    uint256 rewardPerToken = pool.rewardPerTokenStored;
    uint256 userReward = userInfo[token][user].rewardDebt;
    
    if (userInfo[token][user].amount > 0) {
        uint256 userEarned = userInfo[token][user].amount.mul(rewardPerToken.sub(userReward)).div(1e18);
        // Защита от переполнения
        require(userEarned <= type(uint256).max, "Reward calculation overflow");
        return userEarned;
    }
    return 0;
}
}
