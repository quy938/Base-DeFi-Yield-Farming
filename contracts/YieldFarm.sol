# base-defi-yield-farming/contracts/YieldFarm.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract YieldFarm is Ownable {
    IERC20 public rewardToken;
    IERC20 public stakingToken;
    
    struct Pool {
        uint256 totalStaked;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 periodFinish;
    }
    
    mapping(address => uint256) public userStakes;
    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public userLastUpdateTime;
    
    Pool public pool;
    
    event Stake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    
    constructor(
        address _rewardToken,
        address _stakingToken,
        uint256 _rewardRate
    ) {
        rewardToken = IERC20(_rewardToken);
        stakingToken = IERC20(_stakingToken);
        pool.rewardRate = _rewardRate;
        pool.periodFinish = block.timestamp + 30 days;
    }
    
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        updatePool();
        userStakes[msg.sender] += amount;
        pool.totalStaked += amount;
        
        emit Stake(msg.sender, amount);
    }
    
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(userStakes[msg.sender] >= amount, "Insufficient balance");
        
        updatePool();
        userStakes[msg.sender] -= amount;
        pool.totalStaked -= amount;
        
        stakingToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }
    
    function getReward() external {
        updatePool();
        uint256 reward = earned(msg.sender);
        require(reward > 0, "No rewards to claim");
        
        userRewards[msg.sender] = 0;
        userLastUpdateTime[msg.sender] = block.timestamp;
        
        rewardToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }
    
    function updatePool() internal {
        if (block.timestamp <= pool.periodFinish) {
            uint256 timePassed = block.timestamp - pool.lastUpdateTime;
            uint256 newRewards = timePassed * pool.rewardRate;
            
            if (pool.totalStaked > 0) {
                pool.rewardPerTokenStored += (newRewards * 1e18) / pool.totalStaked;
            }
        }
        pool.lastUpdateTime = block.timestamp;
    }
    
    function earned(address account) public view returns (uint256) {
        uint256 userStake = userStakes[account];
        uint256 rewardPerToken = pool.rewardPerTokenStored;
        uint256 userReward = userRewards[account];
        
        if (userStake > 0) {
            uint256 userEarned = (userStake * (rewardPerToken - userLastUpdateTime[account])) / 1e18;
            return userEarned + userReward;
        }
        return userReward;
    }
}
