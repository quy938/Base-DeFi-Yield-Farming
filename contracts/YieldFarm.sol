// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; 

contract YieldFarm is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public stakeToken;
    IERC20 public rewardToken;

    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare;

    uint256 public totalStaked;

    struct User {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => User) public users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Funded(uint256 amount);

    constructor(address _stake, address _reward, uint256 _rewardPerBlock) {
        stakeToken = IERC20(_stake);
        rewardToken = IERC20(_reward);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) return;
        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;

        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function deposit(uint256 amount) external whenNotPaused nonReentrant {
        User storage u = users[msg.sender];
        _updatePool();

        if (u.amount > 0) {
            uint256 pending = (u.amount * accRewardPerShare) / 1e12 - u.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(msg.sender, pending);
                emit Claim(msg.sender, pending);
            }
        }

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        u.amount += amount;
        totalStaked += amount;

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        User storage u = users[msg.sender];
        require(u.amount >= amount, "too much");

        _updatePool();

        uint256 pending = (u.amount * accRewardPerShare) / 1e12 - u.rewardDebt;

        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

        u.amount -= amount;
        totalStaked -= amount;

        stakeToken.safeTransfer(msg.sender, amount);

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        emit Withdraw(msg.sender, amount);
    }

    function claim() external whenNotPaused nonReentrant {
        User storage u = users[msg.sender];
        _updatePool();

        uint256 pending = (u.amount * accRewardPerShare) / 1e12 - u.rewardDebt;
        require(pending > 0, "no rewards");

        rewardToken.safeTransfer(msg.sender, pending);

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        emit Claim(msg.sender, pending);
    }

    function fundRewards(uint256 amount) external {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(amount);
    }

    function emergencyWithdraw() external nonReentrant {
        User storage u = users[msg.sender];

        uint256 amount = u.amount;
        require(amount > 0, "zero");

        u.amount = 0;
        u.rewardDebt = 0;

        totalStaked -= amount;

        stakeToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRewardPerBlock(uint256 newRate) external onlyOwner {
        _updatePool();
        rewardPerBlock = newRate;
    }
}
