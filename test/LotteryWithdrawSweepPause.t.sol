// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryWithdrawSweepPauseTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function test_WithdrawFunds_DecrementsReserved() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();
        entropy.fulfill(lottery.entropyRequestId(), bytes32(uint256(123)));

        uint256 claim = lottery.claimableFunds(buyer1);
        uint256 reservedBefore = lottery.totalReservedUSDC();

        uint256 balBefore = usdc.balanceOf(buyer1);
        vm.prank(buyer1);
        lottery.withdrawFunds();
        uint256 balAfter = usdc.balanceOf(buyer1);

        assertEq(balAfter - balBefore, claim);
        assertEq(lottery.claimableFunds(buyer1), 0);
        assertEq(lottery.totalReservedUSDC(), reservedBefore - claim);
    }

    function test_NativeRefundCredit_ThenWithdrawTo() public {
        RevertingReceiver rr = new RevertingReceiver();

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(address(rr));
        lottery.finalize{value: fee + 1 ether}();

        assertTrue(lottery.claimableNative(address(rr)) > 0);

        vm.prank(address(rr));
        lottery.withdrawNativeTo(buyer2);

        assertEq(lottery.claimableNative(address(rr)), 0);
    }

    function test_SweepSurplus_WorksOnlyIfSurplus() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer2);
        lottery.finalize{value: fee}();
        entropy.fulfill(lottery.entropyRequestId(), bytes32(uint256(1)));

        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(buyer2);

        usdc.mint(address(lottery), 123 * 1e6);

        vm.prank(safeOwner);
        lottery.sweepSurplus(buyer2);

        assertEq(usdc.balanceOf(buyer2), 123 * 1e6);
    }

    function test_Pause_BlocksBuyAndFinalize() public {
        vm.prank(safeOwner);
        lottery.pause();

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.expectRevert(); // Pausable revert
        lottery.buyTickets(1);
        vm.stopPrank();

        vm.warp(lottery.deadline());

        vm.prank(buyer2);
        vm.expectRevert(); // Pausable revert
        lottery.finalize{value: entropy.getFee(provider)}();
    }
}