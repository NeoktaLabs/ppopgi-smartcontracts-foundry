// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryAdditionalCoverageTest is BaseTest {
    // -----------------------------------------
    // 1) Winner boundary tests across ranges
    // -----------------------------------------

    function test_WinnerBoundaries_FirstLastAndEdges() public {
        // Scenario:
        // buyer1 buys 2 => tickets [0,1]
        // buyer2 buys 3 => tickets [2,3,4]
        // totalSold = 5
        _assertWinnerForIndex(0, buyer1); // first ticket
        _assertWinnerForIndex(1, buyer1); // last ticket of buyer1 range
        _assertWinnerForIndex(2, buyer2); // first ticket of buyer2 range
        _assertWinnerForIndex(4, buyer2); // last ticket overall
    }

    function _assertWinnerForIndex(uint256 winningIndex, address expectedWinner) internal {
        LotterySingleWinner lot = _deployDefaultLottery();

        vm.startPrank(buyer1);
        usdc.approve(address(lot), type(uint256).max);
        lot.buyTickets(2);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(lot), type(uint256).max);
        lot.buyTickets(3);
        vm.stopPrank();

        vm.warp(lot.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer1);
        lot.finalize{value: fee}();

        uint64 reqId = lot.entropyRequestId();
        entropy.fulfill(reqId, bytes32(winningIndex));

        assertEq(uint256(lot.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lot.winner(), expectedWinner);
    }

    // -----------------------------------------
    // 2) Deploy config guard: BatchTooCheap
    // -----------------------------------------

    function test_DeployReverts_BatchTooCheapConfig() public {
        vm.startPrank(creator);
        usdc.approve(address(deployer), type(uint256).max);

        // minPurchaseAmount = 0 and ticketPrice < 1 USDC => should revert BatchTooCheap
        vm.expectRevert(LotterySingleWinner.BatchTooCheap.selector);
        deployer.createSingleWinnerLottery(
            "Cheap",
            0.5e6,      // 0.5 USDC per ticket
            100 * 1e6,  // winning pot
            1,          // minTickets
            0,          // maxTickets
            3600,       // duration
            0           // minPurchaseAmount
        );

        vm.stopPrank();
    }

    // -----------------------------------------
    // 3) Withdraw flow: accounting + transfers
    // -----------------------------------------

    function test_WithdrawFunds_UpdatesReservedAndTransfersCorrectly() public {
        LotterySingleWinner lot = _deployDefaultLottery();

        // buyer1 buys 3 tickets => deterministic winner with rand=7 (7 % 3 = 1) still buyer1
        vm.startPrank(buyer1);
        usdc.approve(address(lot), type(uint256).max);
        lot.buyTickets(3);
        vm.stopPrank();

        // Move time to be ready
        vm.warp(lot.deadline());
        uint256 fee = entropy.getFee(provider);

        // finalize from buyer2 just to vary caller (no special privileges)
        vm.prank(buyer2);
        lot.finalize{value: fee}();

        uint64 reqId = lot.entropyRequestId();
        entropy.fulfill(reqId, bytes32(uint256(7)));

        assertEq(uint256(lot.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lot.winner(), buyer1);

        uint256 winningPot = lot.winningPot();
        uint256 ticketRevenue = lot.ticketRevenue();

        uint256 feePot = (winningPot * 10) / 100;
        uint256 feeRev = (ticketRevenue * 10) / 100;

        uint256 winnerAmount = winningPot - feePot;
        uint256 creatorNet = ticketRevenue - feeRev;
        uint256 protocolAmount = feePot + feeRev;

        // Reserved should equal pot + revenue before any withdrawals
        uint256 reservedBefore = lot.totalReservedUSDC();
        assertEq(reservedBefore, winningPot + ticketRevenue);

        // Snapshot balances
        uint256 bWinner = usdc.balanceOf(buyer1);
        uint256 bCreator = usdc.balanceOf(creator);
        uint256 bFeeRecip = usdc.balanceOf(feeRecipient);

        // Winner withdraw
        vm.prank(buyer1);
        lot.withdrawFunds();
        assertEq(usdc.balanceOf(buyer1), bWinner + winnerAmount);
        assertEq(lot.totalReservedUSDC(), reservedBefore - winnerAmount);

        // Creator withdraw
        uint256 reservedMid1 = lot.totalReservedUSDC();
        vm.prank(creator);
        lot.withdrawFunds();
        assertEq(usdc.balanceOf(creator), bCreator + creatorNet);
        assertEq(lot.totalReservedUSDC(), reservedMid1 - creatorNet);

        // Fee recipient withdraw
        uint256 reservedMid2 = lot.totalReservedUSDC();
        vm.prank(feeRecipient);
        lot.withdrawFunds();
        assertEq(usdc.balanceOf(feeRecipient), bFeeRecip + protocolAmount);
        assertEq(lot.totalReservedUSDC(), reservedMid2 - protocolAmount);

        // All liabilities should be paid out => reserved 0
        assertEq(lot.totalReservedUSDC(), 0);
    }

    // -----------------------------------------
    // 4) MockEntropy replay behavior
    // -----------------------------------------

    function test_MockEntropyFulfill_ReplayReverts() public {
        LotterySingleWinner lot = _deployDefaultLottery();

        vm.startPrank(buyer1);
        usdc.approve(address(lot), type(uint256).max);
        lot.buyTickets(3);
        vm.stopPrank();

        vm.warp(lot.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lot.finalize{value: fee}();

        uint64 reqId = lot.entropyRequestId();

        // First fulfill resolves and deletes request
        entropy.fulfill(reqId, bytes32(uint256(7)));
        assertEq(uint256(lot.status()), uint256(LotterySingleWinner.Status.Completed));

        // Second fulfill should revert in MockEntropy ("unknown request")
        vm.expectRevert("unknown request");
        entropy.fulfill(reqId, bytes32(uint256(7)));
    }
}