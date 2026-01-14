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

    // -----------------------------
    // Added tests
    // -----------------------------

    function test_ClaimTicketRefundRevertsIfNotCanceled() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        vm.expectRevert(LotterySingleWinner.NotCanceled.selector);
        vm.prank(buyer1);
        lottery.claimTicketRefund();
    }

    function test_ClaimTicketRefundRevertsIfNoTickets() public {
        vm.warp(lottery.deadline());
        lottery.cancel();

        vm.expectRevert(LotterySingleWinner.NothingToRefund.selector);
        vm.prank(buyer1);
        lottery.claimTicketRefund();
    }

    function test_ClaimTicketRefundCannotDoubleClaim() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        lottery.cancel();

        vm.prank(buyer1);
        lottery.claimTicketRefund();

        vm.expectRevert(LotterySingleWinner.NothingToRefund.selector);
        vm.prank(buyer1);
        lottery.claimTicketRefund();
    }

    function test_CancelRevertsBeforeDeadline() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        vm.expectRevert(LotterySingleWinner.CannotCancel.selector);
        lottery.cancel();
    }

    function test_CancelRevertsIfMinReached() public {
        uint256 need = uint256(lottery.minTickets());

        // buy `need` tickets across one or two buyers if needed
        uint256 first = need > 1000 ? 1000 : need;
        uint256 remaining = need - first;

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(first);
        vm.stopPrank();

        if (remaining > 0) {
            // buy remaining using buyer2, split if > MAX_BATCH_BUY
            vm.startPrank(buyer2);
            usdc.approve(address(lottery), type(uint256).max);
            while (remaining > 0) {
                uint256 chunk = remaining > 1000 ? 1000 : remaining;
                lottery.buyTickets(chunk);
                remaining -= chunk;
            }
            vm.stopPrank();
        }

        vm.warp(lottery.deadline());

        vm.expectRevert(LotterySingleWinner.CannotCancel.selector);
        lottery.cancel();
    }

    function test_ForceCancelStuck_PrivilegedDelayEnforced() public {
        // Enter Drawing by reaching minTickets and finalizing after deadline
        uint256 need = uint256(lottery.minTickets());

        uint256 first = need > 1000 ? 1000 : need;
        uint256 remaining = need - first;

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(first);
        vm.stopPrank();

        if (remaining > 0) {
            vm.startPrank(buyer2);
            usdc.approve(address(lottery), type(uint256).max);
            while (remaining > 0) {
                uint256 chunk = remaining > 1000 ? 1000 : remaining;
                lottery.buyTickets(chunk);
                remaining -= chunk;
            }
            vm.stopPrank();
        }

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Drawing));

        // creator is privileged (per contract: owner() or creator)
        vm.prank(creator);
        vm.expectRevert(LotterySingleWinner.EarlyCancellationRequest.selector);
        lottery.forceCancelStuck();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        lottery.forceCancelStuck();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
    }

    function test_ForceCancelStuck_PublicDelayEnforced() public {
        uint256 need = uint256(lottery.minTickets());

        uint256 first = need > 1000 ? 1000 : need;
        uint256 remaining = need - first;

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(first);
        vm.stopPrank();

        if (remaining > 0) {
            vm.startPrank(buyer2);
            usdc.approve(address(lottery), type(uint256).max);
            while (remaining > 0) {
                uint256 chunk = remaining > 1000 ? 1000 : remaining;
                lottery.buyTickets(chunk);
                remaining -= chunk;
            }
            vm.stopPrank();
        }

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        // non-privileged caller cannot cancel before 7 days
        vm.prank(buyer2);
        vm.expectRevert(LotterySingleWinner.EmergencyHatchLocked.selector);
        lottery.forceCancelStuck();

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(buyer2);
        lottery.forceCancelStuck();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
    }

    function test_ForceCancelStuck_CallbackAfterCancelIsIgnored() public {
        uint256 need = uint256(lottery.minTickets());

        uint256 first = need > 1000 ? 1000 : need;
        uint256 remaining = need - first;

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(first);
        vm.stopPrank();

        if (remaining > 0) {
            vm.startPrank(buyer2);
            usdc.approve(address(lottery), type(uint256).max);
            while (remaining > 0) {
                uint256 chunk = remaining > 1000 ? 1000 : remaining;
                lottery.buyTickets(chunk);
                remaining -= chunk;
            }
            vm.stopPrank();
        }

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        uint64 reqId = lottery.entropyRequestId();
        assertTrue(reqId != 0);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(buyer2);
        lottery.forceCancelStuck();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
        assertEq(lottery.entropyRequestId(), 0);

        // Fulfill the old request; should NOT resolve
        entropy.fulfill(reqId, bytes32(uint256(123)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
        assertEq(lottery.winner(), address(0));
    }
}