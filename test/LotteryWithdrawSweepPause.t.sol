// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./Base.t.sol";
import "./mocks/RevertingReceiver.sol";

contract LotteryWithdrawSweepPauseTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function test_WithdrawFunds_DecrementsReserved() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(5);
        vm.stopPrank();

        vm.warp(lottery.deadline());

        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        entropy.fulfill(lottery.entropyRequestId(), bytes32(uint256(123)));

        uint256 creatorClaimable = lottery.claimableFunds(creator);
        assertGt(creatorClaimable, 0);

        uint256 reservedBefore = lottery.totalReservedUSDC();

        vm.prank(creator);
        lottery.withdrawFunds();

        uint256 reservedAfter = lottery.totalReservedUSDC();
        assertEq(reservedAfter, reservedBefore - creatorClaimable);
    }

    function test_NativeRefundCredit_ThenWithdrawTo() public {
        vm.warp(lottery.deadline());

        RevertingReceiver rr = new RevertingReceiver();
        vm.deal(address(rr), 10 ether);

        uint256 fee = entropy.getFee(provider);
        uint256 overpay = 0.123 ether;

        // Track lottery balance before
        uint256 lotteryBalanceBefore = address(lottery).balance;

        // Call finalize via reverting receiver
        rr.callFinalize{value: fee + overpay}(address(lottery));

        // Track lottery balance after
        uint256 lotteryBalanceAfter = address(lottery).balance;

        // The difference is the failed refund amount that stayed in the lottery
        uint256 expectedCredited = lotteryBalanceAfter - lotteryBalanceBefore;

        uint256 credited = lottery.claimableNative(address(rr));
        assertEq(credited, expectedCredited);

        uint256 beforeBal = buyer1.balance;
        rr.callWithdrawNativeTo(address(lottery), buyer1);
        uint256 afterBal = buyer1.balance;

        assertEq(afterBal, beforeBal + credited);
        assertEq(lottery.claimableNative(address(rr)), 0);
    }

    function test_Pause_BlocksBuyAndFinalize() public {
        vm.prank(safeOwner);
        lottery.pause();

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.expectRevert();
        lottery.buyTickets(1);
        vm.stopPrank();

        vm.warp(lottery.deadline());

        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer1);
        vm.expectRevert();
        lottery.finalize{value: fee}();
    }

    function test_SweepSurplus_WorksOnlyIfSurplus() public {
        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(vm.addr(999));

        uint256 accidental = 123 * 1e6;
        usdc.mint(address(lottery), accidental);

        address recipient = vm.addr(999);
        uint256 beforeBal = usdc.balanceOf(recipient);

        vm.prank(safeOwner);
        lottery.sweepSurplus(recipient);

        uint256 afterBal = usdc.balanceOf(recipient);
        assertEq(afterBal, beforeBal + accidental);

        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(recipient);
    }
}