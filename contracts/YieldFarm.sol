// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardPerBlock;
    uint256 public accRewardPerShare; // 1e12
    uint256 public lastRewardBlock;

    uint256 public totalStaked;

    // NEW: tracked reward budget 
    uint256 public rewardBudget;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event RewardPerBlockUpdated(uint256 oldValue, uint256 newValue);

    // NEW
    event RewardsFunded(address indexed by, uint256 amount, uint256 newBudget);

    constructor(address _stakeToken, address _rewardToken, uint256 _rewardPerBlock) Ownable(msg.sender) {
        require(_stakeToken != address(0) && _rewardToken != address(0), "zero addr");
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
    }

    function fundRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "amount=0");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardBudget += amount;
        emit RewardsFunded(msg.sender, amount, rewardBudget);
    }

    function setRewardPerBlock(uint256 _newRewardPerBlock) external onlyOwner {
        _updatePool();
        emit RewardPerBlockUpdated(rewardPerBlock, _newRewardPerBlock);
        rewardPerBlock = _newRewardPerBlock;
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo memory u = userInfo[_user];
        uint256 _acc = accRewardPerShare;

        if (block.number > lastRewardBlock && totalStaked > 0 && rewardBudget > 0) {
            uint256 blocks = block.number - lastRewardBlock;
            uint256 reward = blocks * rewardPerBlock;
            if (reward > rewardBudget) reward = rewardBudget;
            _acc = _acc + (reward * 1e12) / totalStaked;
        }

        uint256 accumulated = (u.amount * _acc) / 1e12;
        if (accumulated < u.rewardDebt) return 0;
        return accumulated - u.rewardDebt;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updatePool();

        UserInfo storage u = userInfo[msg.sender];
        uint256 pending = _pendingInternal(u);
        if (pending > 0) _pay(msg.sender, pending);

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        u.amount += amount;
        totalStaked += amount;
        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _updatePool();

        UserInfo storage u = userInfo[msg.sender];
        require(u.amount >= amount, "insufficient");

        uint256 pending = _pendingInternal(u);
        if (pending > 0) _pay(msg.sender, pending);

        if (amount > 0) {
            u.amount -= amount;
            totalStaked -= amount;
            stakeToken.safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, amount);
        }

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;
    }

    function claim() external nonReentrant {
        _updatePool();
        UserInfo storage u = userInfo[msg.sender];

        uint256 pending = _pendingInternal(u);
        require(pending > 0, "nothing");

        _pay(msg.sender, pending);
        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) return;

        if (totalStaked == 0 || rewardBudget == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;
        if (reward > rewardBudget) reward = rewardBudget;

        accRewardPerShare = accRewardPerShare + (reward * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function _pendingInternal(UserInfo storage u) internal view returns (uint256) {
        uint256 accumulated = (u.amount * accRewardPerShare) / 1e12;
        if (accumulated < u.rewardDebt) return 0;
        return accumulated - u.rewardDebt;
    }

    function _pay(address to, uint256 amount) internal {
        if (amount > rewardBudget) amount = rewardBudget;
        require(amount > 0, "budget=0");
        rewardBudget -= amount;
        rewardToken.safeTransfer(to, amount);
        emit Claim(to, amount);
    }
}
