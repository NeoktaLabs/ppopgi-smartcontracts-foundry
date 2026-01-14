// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryCancelRefundTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function test_CancelAfterDeadlineIfMinNotReached() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        lottery.cancel();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
        assertEq(lottery.soldAtCancel(), 2);

        vm.prank(buyer1);
        lottery.claimTicketRefund();

        assertEq(lottery.ticketsOwned(buyer1), 0);
        assertEq(lottery.claimableFunds(buyer1), 2 * lottery.ticketPrice());
    }

    function test_FinalizeCancelsIfExpiredAndMinNotReached_RefundsNative() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        vm.warp(lottery.deadline());

        uint256 beforeBal = buyer2.balance;
        vm.prank(buyer2);
        lottery.finalize{value: 0.5 ether}();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
        assertEq(buyer2.balance, beforeBal);
    }
}