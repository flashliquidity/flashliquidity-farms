// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultMock {
    address public immutable stakingToken;
    mapping(address => uint256) public _balances;

    constructor(address _stakingToken) {
        stakingToken = _stakingToken;
    }

    function deposit(uint256 amount) external {
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        if (_balances[msg.sender] >= amount) {
            _balances[msg.sender] -= amount;
            IERC20(stakingToken).transfer(msg.sender, amount);
        }
    }
}
