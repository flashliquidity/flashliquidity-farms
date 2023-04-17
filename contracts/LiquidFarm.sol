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
    uint32 public constant transferLock = 7 days;
    uint32 public constant flashLoanFee = 4e3;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint64) public lastClaimedRewards;

    error StakingZero();
    error WithdrawingZero();
    error FlashLoanNotRepaid();
    error TransferLocked(uint256 _unlockTime);

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event LogFlashLoan(
        address indexed borrower,
        address indexed receiver,
        address indexed rewardsToken,
        uint256 amount,
        uint256 fee
    );
    event FreeFlashloanerChanged(address indexed flashloaner, bool indexed free);

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
        uint64 _lastClaimedRewards = lastClaimedRewards[_account];
        if (_lastClaimedRewards > 0) {
            return _lastClaimedRewards + transferLock;
        }
        return 0;
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

    function earnedRewardToken(address _account) public view returns (uint256) {
        return
            FullMath.mulDiv(
                _earned(
                    _account,
                    balanceOf(_account),
                    _rewardPerToken(totalSupply(), rewardRate),
                    rewards[_account]
                ),
                IERC20(rewardsToken).balanceOf(address(this)),
                rewardsPending + (block.timestamp - lastUpdateTime) * rewardRate
            );
    }

    function stake(uint256 _amount) external {
        if (_amount == 0) {
            revert StakingZero();
        }
        uint256 _accountBalance = balanceOf(msg.sender);
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
            _accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public {
        if (_amount == 0) {
            revert WithdrawingZero();
        }
        uint256 _accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        rewardPerTokenStored = rewardPerToken_;
        uint256 _lastUpdateTime = lastUpdateTime;
        if (_lastUpdateTime != 0) {
            rewardsPending += (block.timestamp - _lastUpdateTime) * rewardRate;
        }
        lastUpdateTime = uint64(block.timestamp);
        rewards[msg.sender] = _earned(
            msg.sender,
            _accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        //_approve(msg.sender, address(this), amount);
        _burn(msg.sender, _amount);
        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function exit() external {
        uint256 _accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        uint256 _rewardsPending = rewardsPending;
        uint256 _reward = _earned(
            msg.sender,
            _accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        if (_reward > 0) {
            rewards[msg.sender] = 0;
        }
        rewardPerTokenStored = rewardPerToken_;
        uint256 _lastUpdateTime = lastUpdateTime;
        if (_lastUpdateTime != 0) {
            _rewardsPending += (block.timestamp - _lastUpdateTime) * rewardRate;
            rewardsPending = _rewardsPending;
        }
        lastUpdateTime = uint64(block.timestamp);
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;
        //_approve(msg.sender, address(this), accountBalance);
        if (_reward > 0) {
            address _rewardsToken = rewardsToken;
            rewardsPending -= _reward;
            uint256 profitsShare = FullMath.mulDiv(
                _reward,
                IERC20(_rewardsToken).balanceOf(address(this)),
                _rewardsPending
            );
            _getReward(_rewardsToken, profitsShare);
        }
        _burn(msg.sender, _accountBalance);
        IERC20(stakingToken).safeTransfer(msg.sender, _accountBalance);
        emit Withdrawn(msg.sender, _accountBalance);
    }

    function getReward() public {
        uint256 _accountBalance = balanceOf(msg.sender);
        uint256 totalSupply_ = totalSupply();
        uint256 rewardPerToken_ = _rewardPerToken(totalSupply_, rewardRate);
        uint256 _rewardsPending = rewardsPending;
        uint256 _reward = _earned(
            msg.sender,
            _accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );
        lastClaimedRewards[msg.sender] = uint64(block.timestamp);
        rewardPerTokenStored = rewardPerToken_;
        uint256 _lastUpdateTime = lastUpdateTime;
        if (_lastUpdateTime != 0) {
            _rewardsPending += (block.timestamp - _lastUpdateTime) * rewardRate;
            rewardsPending = _rewardsPending;
        }
        lastUpdateTime = uint64(block.timestamp);
        userRewardPerTokenPaid[msg.sender] = rewardPerToken_;
        if (_reward > 0) {
            rewards[msg.sender] = 0;
            address _rewardsToken = rewardsToken;
            rewardsPending -= _reward;
            uint256 profitsShare = FullMath.mulDiv(
                _reward,
                IERC20(_rewardsToken).balanceOf(address(this)),
                _rewardsPending
            );
            _getReward(_rewardsToken, profitsShare);
        }
    }

    function flashLoan(
        IFlashBorrower _borrower,
        address _receiver,
        uint256 _amount,
        bytes memory _data
    ) public {
        IERC20 _rewardsToken = IERC20(rewardsToken);
        bool _freeFlashLoan = ILiquidFarmFactory(farmsFactory).isFreeFlashLoan(msg.sender);
        uint256 _fee = !_freeFlashLoan ? FullMath.mulDiv(_amount, flashLoanFee, 1e7) : 0;
        uint256 minBalanceAfter = _rewardsToken.balanceOf(address(this)) + _fee;
        _rewardsToken.safeTransfer(_receiver, _amount);
        _borrower.onFlashLoan(msg.sender, address(rewardsToken), _amount, _fee, _data);
        if (_rewardsToken.balanceOf(address(this)) < minBalanceAfter) {
            revert FlashLoanNotRepaid();
        }
        emit LogFlashLoan(address(_borrower), _receiver, address(rewardsToken), _amount, _fee);
    }

    function _earned(
        address _account,
        uint256 _accountBalance,
        uint256 rewardPerToken_,
        uint256 _accountRewards
    ) internal view returns (uint256) {
        return
            FullMath.mulDiv(
                _accountBalance,
                rewardPerToken_ - userRewardPerTokenPaid[_account],
                PRECISION
            ) + _accountRewards;
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

    function _getReward(address _rewardsToken, uint256 _profitsShare) private {
        if (_rewardsToken == WETH) {
            IWETH(WETH).withdraw(_profitsShare);
            (bool success, ) = msg.sender.call{value: _profitsShare}("");
            require(success, "Transfer failed");
        } else {
            IERC20(_rewardsToken).safeTransfer(msg.sender, _profitsShare);
        }
        emit RewardPaid(msg.sender, _profitsShare);
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
        uint256 _lastUpdateTime = lastUpdateTime;
        if (_lastUpdateTime != 0) {
            rewardsPending += (block.timestamp - _lastUpdateTime) * rewardRate;
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
