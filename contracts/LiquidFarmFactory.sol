//SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import {Governable} from "./types/Governable.sol";
import {ILiquidFarmFactory} from "./interfaces/ILiquidFarmFactory.sol";
import {LiquidFarm} from "./LiquidFarm.sol";

contract LiquidFarmFactory is ILiquidFarmFactory, Governable {
    address public WETH;
    address[] public stakingLpTokens;
    mapping(address => address) public lpTokenFarm;
    mapping(address => bool) public isFreeFlashLoan;

    error AlreadyDeployed();

    event FarmDeployed(address indexed _stakingToken, address indexed _rewardsToken);

    constructor(
        address _WETH,
        address _governor,
        uint256 _transferGovernanceDelay
    ) Governable(_governor, _transferGovernanceDelay) {
        WETH = _WETH;
    }

    function setFreeFlashLoan(address _target, bool _isExempted) external onlyGovernor {
        isFreeFlashLoan[_target] = _isExempted;
    }

    function deploy(
        string memory _name,
        string memory _symbol,
        address _stakingToken,
        address _rewardsToken
    ) external onlyGovernor {
        if (lpTokenFarm[_stakingToken] != address(0)) {
            revert AlreadyDeployed();
        }
        lpTokenFarm[_stakingToken] = address(
            new LiquidFarm(_name, _symbol, _rewardsToken, _stakingToken, WETH)
        );
        stakingLpTokens.push(_stakingToken);
        emit FarmDeployed(_stakingToken, _rewardsToken);
    }
}
