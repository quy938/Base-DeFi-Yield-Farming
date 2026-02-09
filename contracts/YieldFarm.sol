// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  BaseYieldFarm.sol
  - Single staking pool
  - Reward per block emission
  - SafeERC20 for token interactions
  - EmergencyWithdraw (no rewards)
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseYieldFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardPerBlock;     // rewards emitted per block
    uint256 public accRewardPerShare;  // scaled by 1e12
    uint256 public lastRewardBlock;

    uint256 public totalStaked;

    struct UserInfo {
        uint256 amount;      // staked amount
        uint256 rewardDebt;  // amount * accRewardPerShare / 1e12
    }

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RewardPerBlockUpdated(uint256 oldValue, uint256 newValue);

    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _rewardPerBlock
    ) Ownable(msg.sender) {
        require(_stakeToken != address(0) && _rewardToken != address(0), "zero addr");
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerBlock = _rewardPerBlock;
        lastRewardBlock = block.number;
    }

    // ---------------------------
    // Admin
    // ---------------------------
    function setRewardPerBlock(uint256 _newRewardPerBlock) external onlyOwner {
        _updatePool();
        emit RewardPerBlockUpdated(rewardPerBlock, _newRewardPerBlock);
        rewardPerBlock = _newRewardPerBlock;
    }

    // Owner can fund rewards by sending rewardToken to this contract.
    // IMPORTANT: If rewards run out, claims will revert due to insufficient balance.

    // ---------------------------
    // Views
    // ---------------------------
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo memory u = userInfo[_user];

        uint256 _acc = accRewardPerShare;
        if (block.number > lastRewardBlock && totalStaked > 0) {
            uint256 blocks = block.number - lastRewardBlock;
            uint256 reward = blocks * rewardPerBlock;
            _acc = _acc + (reward * 1e12) / totalStaked;
        }

        uint256 accumulated = (u.amount * _acc) / 1e12;
        if (accumulated < u.rewardDebt) return 0;
        return accumulated - u.rewardDebt;
    }


    // Core logic

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updatePool();

        UserInfo storage u = userInfo[msg.sender];

        // pay pending
        uint256 pending = _pendingInternal(u);
        if (pending > 0) {
            _safeRewardTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

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

        // pay pending
        uint256 pending = _pendingInternal(u);
        if (pending > 0) {
            _safeRewardTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

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
        require(pending > 0, "nothing to claim");

        _safeRewardTransfer(msg.sender, pending);
        emit Claim(msg.sender, pending);

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;
    }

    // ---------------------------
    // Emergency exit (no rewards)
    // ---------------------------
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage u = userInfo[msg.sender];
        uint256 amount = u.amount;
        require(amount > 0, "nothing staked");

        // reset user state
        u.amount = 0;
        u.rewardDebt = 0;

        totalStaked -= amount;
        stakeToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    // ---------------------------
    // Internal
    // ---------------------------
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) return;

        if (totalStaked == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - lastRewardBlock;
        uint256 reward = blocks * rewardPerBlock;

        accRewardPerShare = accRewardPerShare + (reward * 1e12) / totalStaked;
        lastRewardBlock = block.number;
    }

    function _pendingInternal(UserInfo storage u) internal view returns (uint256) {
        uint256 accumulated = (u.amount * accRewardPerShare) / 1e12;
        if (accumulated < u.rewardDebt) return 0;
        return accumulated - u.rewardDebt;
    }

    function _safeRewardTransfer(address to, uint256 amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        require(bal >= amount, "reward depleted");
        rewardToken.safeTransfer(to, amount);
    }
}
