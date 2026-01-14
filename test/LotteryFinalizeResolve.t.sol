// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryFinalizeResolveTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function test_FinalizeRevertsIfNotReady() public {
        vm.expectRevert(LotterySingleWinner.NotReadyToFinalize.selector);
        vm.prank(buyer1);
        lottery.finalize{value: 0.01 ether}();
    }

    function test_FinalizeThenResolve_AllocationsCorrect() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Drawing));
        uint64 reqId = lottery.entropyRequestId();
        assertTrue(reqId != 0);

        entropy.fulfill(reqId, bytes32(uint256(7)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lottery.winner(), buyer1);

        uint256 winningPot = lottery.winningPot();
        uint256 ticketRevenue = lottery.ticketRevenue();

        uint256 feePot = (winningPot * 10) / 100;
        uint256 feeRev = (ticketRevenue * 10) / 100;

        uint256 winnerAmount = winningPot - feePot;
        uint256 creatorNet = ticketRevenue - feeRev;
        uint256 protocolAmount = feePot + feeRev;

        assertEq(lottery.claimableFunds(buyer1), winnerAmount);
        assertEq(lottery.claimableFunds(creator), creatorNet);
        assertEq(lottery.claimableFunds(feeRecipient), protocolAmount);
    }

    function test_CallbackUnauthorized() public {
        vm.expectRevert(LotterySingleWinner.UnauthorizedCallback.selector);
        lottery.entropyCallback(1, provider, bytes32(uint256(1)));
    }

    function test_CallbackWrongSequenceRejected_NoStateChange() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        uint64 realId = lottery.entropyRequestId();

        vm.prank(address(entropy));
        lottery.entropyCallback(realId + 999, provider, bytes32(uint256(1)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Drawing));
        assertEq(lottery.entropyRequestId(), realId);
    }

    // -----------------------------
    // Added tests
    // -----------------------------

    function test_FinalizeRevertsIfInsufficientFee() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.expectRevert(LotterySingleWinner.InsufficientFee.selector);
        vm.prank(buyer2);
        lottery.finalize{value: fee - 1}();
    }

    function test_FinalizeRefundsExtraNative() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        uint256 beforeBal = buyer2.balance;

        vm.prank(buyer2);
        lottery.finalize{value: fee + 0.123 ether}();

        // buyer2 paid exactly `fee`, rest refunded
        assertEq(buyer2.balance, beforeBal - fee);
    }

    function test_FinalizeRevertsIfRequestPending() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        vm.expectRevert(LotterySingleWinner.RequestPending.selector);
        vm.prank(buyer2);
        lottery.finalize{value: fee}();
    }

    function test_CallbackWrongProviderRejected_NoStateChange() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        uint64 realId = lottery.entropyRequestId();

        // callback with wrong provider should be rejected and state unchanged
        address wrongProvider = address(0xBEEF);

        vm.prank(address(entropy));
        lottery.entropyCallback(realId, wrongProvider, bytes32(uint256(1)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Drawing));
        assertEq(lottery.entropyRequestId(), realId);
    }

    function test_ActiveDrawings_IncrementsAndDecrementsOnResolve() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        assertEq(lottery.activeDrawings(), 0);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        assertEq(lottery.activeDrawings(), 1);

        uint64 reqId = lottery.entropyRequestId();
        entropy.fulfill(reqId, bytes32(uint256(7)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lottery.activeDrawings(), 0);
    }

    function test_WinnerSelectionAcrossRanges() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2); // tickets [0,1]
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3); // tickets [2,3,4]
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer1);
        lottery.finalize{value: fee}();

        uint64 reqId = lottery.entropyRequestId();

        // total = 5, winningIndex = 4 -> buyer2
        entropy.fulfill(reqId, bytes32(uint256(4)));

        assertEq(lottery.winner(), buyer2);
    }
}