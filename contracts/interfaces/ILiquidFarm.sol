// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IFlashBorrower.sol";

interface ILiquidFarm {
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

    function farmsFactory() external view returns (address);

    function stakingToken() external view returns (address);

    function rewardsToken() external view returns (address);

    function rewardPerToken() external view returns (uint256);

    function transferLock() external view returns (uint32);

    function getTransferUnlockTime(address _account) external view returns (uint64);

    function lastClaimedRewards(address _account) external view returns (uint64);

    function earned(address account) external view returns (uint256);

    function earnedRewardToken(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function exit() external;

    function flashLoan(
        IFlashBorrower borrower,
        address receiver,
        uint256 amount,
        bytes memory data
    ) external;
}
