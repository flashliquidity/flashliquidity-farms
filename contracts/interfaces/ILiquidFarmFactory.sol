// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILiquidFarmFactory {
    function lpTokenFarm(address _stakingToken) external view returns (address);

    function isFreeFlashLoan(address sender) external view returns (bool);

    function setFreeFlashLoan(address _target, bool _isExempted) external;

    function deploy(
        string memory name,
        string memory symbol,
        address stakingToken,
        address rewardsToken
    ) external;
}
