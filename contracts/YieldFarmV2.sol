// base-defi-yield-farming/contracts/YieldFarmV2.sol
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
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 periodFinish;
        uint256 allocPoint;
        uint256 lastRewardTime;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastRewardTime;
        uint256 pendingRewards;
    }

    mapping(address => Pool) public pools;
    mapping(address => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256[]) public userPools;
    
    IERC20 public rewardToken;
    IERC20 public stakingToken;
    
    uint256 public totalAllocPoints;
    uint256 public rewardPerSecond;
    uint256 public lastUpdateTime;
    
    // Конфигурация
    uint256 public constant MAX_ALLOC_POINTS = 10000;
    uint256 public constant MAX_REWARD_RATE = 1000000000000000000; // 1 token per second
    
    // События
    event PoolCreated(address indexed token, uint256 allocPoint, uint256 rewardRate);
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 reward);
    event EmergencyWithdraw(address indexed user, address indexed token, uint256 amount);
    event PoolUpdated(address indexed token, uint256 allocPoint, uint256 rewardRate);
    event RewardRateUpdated(uint256 newRate);

    constructor(
        address _rewardToken,
        address _stakingToken,
        uint256 _rewardPerSecond
    ) {
        rewardToken = IERC20(_rewardToken);
        stakingToken = IERC20(_stakingToken);
        rewardPerSecond = _rewardPerSecond;
        lastUpdateTime = block.timestamp;
    }

    // Создание нового пула
    function createPool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        
        Pool storage pool = pools[token];
        require(pool.token == address(0), "Pool already exists");
        
        pool.token = IERC20(token);
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        pool.lastRewardTime = block.timestamp;
        
        totalAllocPoints = totalAllocPoints.add(allocPoint);
        
        emit PoolCreated(token, allocPoint, rewardRate);
    }

    // Обновление параметров пула
    function updatePool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        
        totalAllocPoints = totalAllocPoints.sub(pool.allocPoint).add(allocPoint);
        
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        
        emit PoolUpdated(token, allocPoint, rewardRate);
    }

    // Стейкинг токенов
    function stake(
        address token,
        uint256 amount
    ) external nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
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
        
        pool.token.transferFrom(msg.sender, address(this), amount);
        user.lastRewardTime = block.timestamp;
        
        // Обновление истории пользователя
        userPools[msg.sender].push(token);
        
        emit Staked(msg.sender, token, amount);
    }

    // Вывод токенов
    function withdraw(
        address token,
        uint256 amount
    ) external nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(userInfo[token][msg.sender].amount >= amount, "Insufficient balance");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        uint256 pending = calculatePendingReward(token, msg.sender);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        
        user.amount = user.amount.sub(amount);
        pool.totalStaked = pool.totalStaked.sub(amount);
        
        pool.token.transfer(msg.sender, amount);
        user.lastRewardTime = block.timestamp;
        
        emit Withdrawn(msg.sender, token, amount);
    }

    // Получение награды
    function getReward(
        address token
    ) external nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        uint256 pending = calculatePendingReward(token, msg.sender);
        require(pending > 0, "No rewards to claim");
        
        user.pendingRewards = user.pendingRewards.add(pending);
        user.rewardDebt = user.rewardDebt.add(pending);
        
        // Перевод награды
        rewardToken.transfer(msg.sender, pending);
        
        emit RewardPaid(msg.sender, token, pending);
    }

    // Экстренный вывод (только для владельца)
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

    // Обновление пулов
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

    // Расчет ожидаемой награды
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

    // Получение информации о пуле
    function getPoolInfo(address token) external view returns (Pool memory) {
        return pools[token];
    }

    // Получение информации о пользователе
    function getUserInfo(address token, address user) external view returns (UserInfo memory) {
        return userInfo[token][user];
    }

    // Получение всех пулов пользователя
    function getUserPools(address user) external view returns (address[] memory) {
        return userPools[user];
    }

    // Установка новой ставки награды
    function setRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= MAX_REWARD_RATE, "Reward rate too high");
        rewardPerSecond = newRate;
        emit RewardRateUpdated(newRate);
    }

    // Получение общей статистики
    function getFarmStats() external view returns (
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 totalUsers
    ) {
        // Реализация статистики
        return (0, 0, 0);
    }
}
