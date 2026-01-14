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
        // Buy some tickets so creator earns revenue on completion
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(5);
        vm.stopPrank();

        // Make lottery ready to finalize (deadline passed)
        vm.warp(lottery.deadline());

        // finalize (pay fee)
        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        // Resolve randomness
        entropy.fulfill(lottery.entropyRequestId(), bytes32(uint256(123)));

        // Creator should have claimable revenue (ticketRevenue - fee)
        uint256 creatorClaimable = lottery.claimableFunds(creator);
        assertGt(creatorClaimable, 0);

        uint256 reservedBefore = lottery.totalReservedUSDC();

        vm.prank(creator);
        lottery.withdrawFunds();

        uint256 reservedAfter = lottery.totalReservedUSDC();
        assertEq(reservedAfter, reservedBefore - creatorClaimable);
    }

    function test_NativeRefundCredit_ThenWithdrawTo() public {
        // Make lottery ready to finalize immediately
        vm.warp(lottery.deadline());

        RevertingReceiver rr = new RevertingReceiver();
        vm.deal(address(rr), 10 ether);

        uint256 fee = entropy.getFee(provider);
        uint256 extra = 0.123 ether;

        // Call finalize from rr with fee + extra (extra refund will fail => credited to rr)
        rr.callFinalize{value: fee + extra}(address(lottery));

        // rr should now be credited extra as claimable native
        uint256 credited = lottery.claimableNative(address(rr));
        assertEq(credited, extra);

        // withdraw that credited native to an EOA that CAN receive ETH
        uint256 beforeBal = buyer1.balance;
        rr.callWithdrawNativeTo(address(lottery), buyer1);
        uint256 afterBal = buyer1.balance;

        assertEq(afterBal, beforeBal + extra);
        assertEq(lottery.claimableNative(address(rr)), 0);
    }

    function test_Pause_BlocksBuyAndFinalize() public {
        // Pause must be called by the lottery owner, which is safeOwner after deployment
        vm.prank(safeOwner);
        lottery.pause();

        // Buy should revert while paused
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.expectRevert(); // Pausable error (OZ v5 uses custom error)
        lottery.buyTickets(1);
        vm.stopPrank();

        // Make ready to finalize
        vm.warp(lottery.deadline());

        // Finalize should also revert while paused
        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer1);
        vm.expectRevert(); // Pausable error
        lottery.finalize{value: fee}();
    }

    function test_SweepSurplus_WorksOnlyIfSurplus() public {
        // Initially, no surplus should exist
        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(vm.addr(999));

        // Create a surplus: mint USDC directly to lottery (accidental deposit simulation)
        uint256 accidental = 123 * 1e6;
        usdc.mint(address(lottery), accidental);

        // Sweep should work, only by owner
        address recipient = vm.addr(999);
        uint256 beforeBal = usdc.balanceOf(recipient);

        vm.prank(safeOwner);
        lottery.sweepSurplus(recipient);

        uint256 afterBal = usdc.balanceOf(recipient);
        assertEq(afterBal, beforeBal + accidental);

        // After sweeping, surplus should be gone => sweeping again reverts
        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(recipient);
    }
}