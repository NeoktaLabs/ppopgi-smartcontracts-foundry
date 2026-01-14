// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryCreationTest is BaseTest {
    function test_CreateLottery_InitialStateCorrect() public {
        vm.startPrank(creator);
        usdc.approve(address(deployer), type(uint256).max);

        uint256 ticketPrice = 2 * 1e6;
        uint256 winningPot = 500 * 1e6;
        uint64 minTickets = 3;
        uint64 maxTickets = 10;
        uint64 duration = 3600;

        address lotAddr = deployer.createSingleWinnerLottery(
            "Creation Test Lottery",
            ticketPrice,
            winningPot,
            minTickets,
            maxTickets,
            duration,
            0
        );
        vm.stopPrank();

        LotterySingleWinner l = LotterySingleWinner(payable(lotAddr));

        // -----------------------------
        // Core initialization checks
        // -----------------------------

        assertEq(uint256(l.status()), uint256(LotterySingleWinner.Status.Open));
        assertEq(l.creator(), creator);
        assertEq(l.owner(), safeOwner);

        assertEq(l.ticketPrice(), ticketPrice);
        assertEq(l.winningPot(), winningPot);
        assertEq(l.minTickets(), minTickets);
        assertEq(l.maxTickets(), maxTickets);

        // Deadline correctness
        assertEq(l.deadline(), l.createdAt() + duration);
        assertTrue(l.deadline() > block.timestamp);

        // -----------------------------
        // Accounting correctness
        // -----------------------------

        assertEq(l.totalReservedUSDC(), winningPot);
        assertEq(usdc.balanceOf(address(l)), winningPot);

        // No tickets sold yet
        assertEq(l.getSold(), 0);
        assertEq(l.ticketRevenue(), 0);

        // No drawings in flight
        assertEq(l.activeDrawings(), 0);
        assertEq(l.entropyRequestId(), 0);
    }
}