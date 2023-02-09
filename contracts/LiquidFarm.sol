//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ILiquidFarmFactory} from "./interfaces/ILiquidFarmFactory.sol";
import {ILiquidFarm} from "./interfaces/ILiquidFarm.sol";
import {IFlashBorrower} from "./interfaces/IFlashBorrower.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {FullMath} from "./lib/FullMath.sol";

contract LiquidFarm is ILiquidFarm, ERC20 {
    using SafeERC20 for IERC20;

    address public rewardsToken;
    address public stakingToken;
    address public farmsFactory;
    address public WETH;
    uint256 public rewardRate = 1e14;
    uint256 public rewardPerTokenStored;
    uint256 public rewardsPending;
    uint256 internal constant PRECISION = 1e30;
    uint64 public lastUpdateTime;
    uint32 public constant transferLock = 7 days; // for liquid staked LP tokens after stake or claim (withdrawals exempted)
    uint32 public constant flashLoanFee = 4e3; // 0.04%
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint64) public lastClaimedRewards;

    constructor(
        string memory name,
        string memory symbol,
        address _rewardsToken,
        address _stakingToken,
        address _WETH
    ) ERC20(name, symbol) {
        rewardsToken = _rewardsToken;
        stakingToken = _stakingToken;
        WETH = _WETH;
        farmsFactory = msg.sender;
    }

    receive() external payable {}

    function getTransferUnlockTime(address _account) external view returns (uint64) {
        return lastClaimedRewards[_account] > 0 ? lastClaimedRewards[_account] + transferLock : 0;
    }

    function rewardPerToken() external view returns (uint256) {
        return _rewardPerToken(totalSupply(), rewardRate);
    }

    function earned(address account) external view returns (uint256) {
        return
            _earned(
                account,
                balanceOf(account),
                _rewardPerToken(totalSupply(), rewardRate),
                rewards[account]
            );
    }

    function earnedRewardToken(address account) public view returns (uint256) {
        return
            FullMath.mulDiv(
                _earned(
                    account,
                    balanceOf(account),
                    _rewardPerToken(totalSupply(), rewardRate),
                    rewards[account]
                ),
                IERC20(rewardsToken).balanceOf(address(this)),
                rewardsPending + (block.timestamp - lastUpdateTime) * rewardRate
            );
    }

    function stake(uint256 amount) external {
        if (amount == 0) {
            revert StakingZero();
        }
        uint256 accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        lastClaimedRewards[msg.sender] = uint64(block.timestamp);
        rewardPerTokenStored = rewardPerToken_;
        if (lastUpdateTime != 0) {
            rewardsPending += (block.timestamp - lastUpdateTime) * rewardRate;
        }
        lastUpdateTime = uint64(block.timestamp);
        rewards[msg.sender] = _earned(
            msg.sender,
            accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public {
        if (amount == 0) {
            revert WithdrawingZero();
        }
        uint256 accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        rewardPerTokenStored = rewardPerToken_;
        if (lastUpdateTime != 0) {
            rewardsPending += (block.timestamp - lastUpdateTime) * rewardRate;
        }
        lastUpdateTime = uint64(block.timestamp);
        rewards[msg.sender] = _earned(
            msg.sender,
            accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        _approve(msg.sender, address(this), amount);
        _burn(msg.sender, amount);
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        uint256 accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        uint256 _rewardsPending = rewardsPending;
        uint256 reward = _earned(msg.sender, accountBalance, rewardPerToken_, rewards[msg.sender]);
        if (reward > 0) {
            rewards[msg.sender] = 0;
        }
        rewardPerTokenStored = rewardPerToken_;
        if (lastUpdateTime != 0) {
            _rewardsPending += (block.timestamp - lastUpdateTime) * rewardRate;
            rewardsPending = _rewardsPending;
        }
        lastUpdateTime = uint64(block.timestamp);
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;
        _approve(msg.sender, address(this), accountBalance);
        if (reward > 0) {
            address _rewardsToken = rewardsToken;
            rewardsPending -= reward;
            uint256 profitsShare = FullMath.mulDiv(
                reward,
                IERC20(_rewardsToken).balanceOf(address(this)),
                _rewardsPending
            );
            _getReward(_rewardsToken, profitsShare);
        }
        _burn(msg.sender, accountBalance);
        IERC20(stakingToken).safeTransfer(msg.sender, accountBalance);
        emit Withdrawn(msg.sender, accountBalance);
    }

    function getReward() public {
        uint256 accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        uint256 _rewardsPending = rewardsPending;
        uint256 reward = _earned(msg.sender, accountBalance, rewardPerToken_, rewards[msg.sender]);
        lastClaimedRewards[msg.sender] = uint64(block.timestamp);
        rewardPerTokenStored = rewardPerToken_;
        if (lastUpdateTime != 0) {
            _rewardsPending += (block.timestamp - lastUpdateTime) * rewardRate;
            rewardsPending = _rewardsPending;
        }
        lastUpdateTime = uint64(block.timestamp);
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;

        if (reward > 0) {
            rewards[msg.sender] = 0;
            address _rewardsToken = rewardsToken;
            rewardsPending -= reward;
            uint256 profitsShare = FullMath.mulDiv(
                reward,
                IERC20(_rewardsToken).balanceOf(address(this)),
                _rewardsPending
            );
            _getReward(_rewardsToken, profitsShare);
        }
    }

    function flashLoan(
        IFlashBorrower borrower,
        address receiver,
        uint256 amount,
        bytes memory data
    ) public {
        IERC20 _rewardsToken = IERC20(rewardsToken);
        bool freeFlashLoan = ILiquidFarmFactory(farmsFactory).isFreeFlashLoan(msg.sender);
        uint256 fee = !freeFlashLoan ? FullMath.mulDiv(amount, flashLoanFee, 1e7) : 0;
        uint256 minBalanceAfter = _rewardsToken.balanceOf(address(this)) + fee;
        _rewardsToken.safeTransfer(receiver, amount);
        borrower.onFlashLoan(msg.sender, address(rewardsToken), amount, fee, data);
        if (_rewardsToken.balanceOf(address(this)) < minBalanceAfter) {
            revert FlashLoanNotRepaid();
        }
        emit LogFlashLoan(address(borrower), receiver, address(rewardsToken), amount, fee);
    }

    function _earned(
        address account,
        uint256 accountBalance,
        uint256 rewardPerToken_,
        uint256 accountRewards
    ) internal view returns (uint256) {
        return
            FullMath.mulDiv(
                accountBalance,
                rewardPerToken_ - userRewardPerTokenPaid[account],
                PRECISION
            ) + accountRewards;
    }

    function _rewardPerToken(uint256 totalSupply_, uint256 rewardRate_)
        internal
        view
        returns (uint256)
    {
        if (totalSupply_ == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            FullMath.mulDiv(
                (block.timestamp - lastUpdateTime) * PRECISION,
                rewardRate_,
                totalSupply_
            );
    }

    function _getReward(address _rewardsToken, uint256 profitsShare) private {
        if (rewardsToken == WETH) {
            IWETH(WETH).withdraw(profitsShare);
            (bool success, ) = msg.sender.call{value: profitsShare}("");
            require(success, "Transfer failed");
        } else {
            IERC20(_rewardsToken).safeTransfer(msg.sender, profitsShare);
        }
        emit RewardPaid(msg.sender, profitsShare);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        if (_from == address(0) || _to == address(0) || _amount == 0) {
            return;
        }

        uint256 _lastClaim = lastClaimedRewards[_from];
        if (_lastClaim != 0 || _to != address(0)) {
            uint256 _unlockTime = _lastClaim + transferLock;
            if (block.timestamp < _unlockTime) {
                revert TransferLocked(_unlockTime);
            }
        }
        uint256 _fromBalance = balanceOf(_from);
        uint256 _toBalance = balanceOf(_to);
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply(), rewardRate);
        rewardPerTokenStored = rewardPerToken_;
        if (lastUpdateTime != 0) {
            rewardsPending += (block.timestamp - lastUpdateTime) * rewardRate;
        }
        lastUpdateTime = uint64(block.timestamp);
        uint256 reward = _earned(_from, _fromBalance, rewardPerToken_, rewards[_from]);
        uint256 rewardsToTransfer = FullMath.mulDiv(reward, _amount, balanceOf(_from));
        rewards[_from] = reward - rewardsToTransfer;
        rewards[_to] = _earned(_to, _toBalance, rewardPerToken_, rewards[_to] + rewardsToTransfer);
        userRewardPerTokenPaid[_from] = rewardPerToken_;
        userRewardPerTokenPaid[_to] = rewardPerToken_;
    }
}
