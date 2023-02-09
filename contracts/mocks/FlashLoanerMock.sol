// SPDX-License-Identifier: MIT
import {IFlashBorrower} from "../interfaces/IFlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity ^0.8.0;

contract FlashLoanerMock is IFlashBorrower {
    using SafeERC20 for IERC20;
    address public immutable farm;
    bool public ignoreFee = false;

    event FlashLoan(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 fee,
        bytes data
    );

    constructor(address _farm) {
        farm = _farm;
    }

    function setIgnoreFee(bool _ignoreFee) external {
        ignoreFee = _ignoreFee;
    }

    function onFlashLoan(
        address sender,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external {
        amount = ignoreFee ? amount : amount + fee;
        IERC20(token).safeTransfer(farm, amount);
        emit FlashLoan(sender, token, amount, fee, data);
    }
}
