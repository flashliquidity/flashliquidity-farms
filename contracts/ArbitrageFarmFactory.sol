//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {Governable} from "./types/Governable.sol";
import {IArbitrageFarmFactory} from "./interfaces/IArbitrageFarmFactory.sol";
import {IArbitrageFarm} from "./interfaces/IArbitrageFarm.sol";
import {ArbitrageFarm} from "./ArbitrageFarm.sol";

contract ArbitrageFarmFactory is IArbitrageFarmFactory, Governable {
    address public WETH;
    address[] public stakingLpTokens;
    mapping(address => address) public lpTokenFarm;
    mapping(address => bool) public isFreeFlashLoan;

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
        string memory name,
        string memory symbol,
        address stakingToken,
        address rewardsToken
    ) external onlyGovernor {
        if (lpTokenFarm[stakingToken] != address(0)) {
            revert AlreadyDeployed();
        }
        lpTokenFarm[stakingToken] = address(
            new ArbitrageFarm(name, symbol, rewardsToken, stakingToken, WETH)
        );
        stakingLpTokens.push(stakingToken);
        emit FarmDeployed(stakingToken, rewardsToken);
    }
}
