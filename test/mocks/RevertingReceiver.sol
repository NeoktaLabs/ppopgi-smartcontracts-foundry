// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILotteryFinalize {
    function finalize() external payable;
}

interface ILotteryWithdrawNative {
    function withdrawNativeTo(address to) external;
}

/// @notice A contract that cannot receive ETH (receive() always reverts),
/// and can call into the lottery as itself (msg.sender = this contract).
contract RevertingReceiver {
    error RejectETH();

    receive() external payable {
        revert RejectETH();
    }

    function callFinalize(address lottery) external payable {
        ILotteryFinalize(lottery).finalize{value: msg.value}();
    }

    function callWithdrawNativeTo(address lottery, address to) external {
        ILotteryWithdrawNative(lottery).withdrawNativeTo(to);
    }
}