// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryBuyTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function test_BuyBasicAccounting() public {
        uint256 beforeReserved = lottery.totalReservedUSDC();
        uint256 beforeRev = lottery.ticketRevenue();

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(5);
        vm.stopPrank();

        assertEq(lottery.ticketsOwned(buyer1), 5);
        assertEq(lottery.getSold(), 5);

        uint256 cost = 5 * lottery.ticketPrice();
        assertEq(lottery.ticketRevenue(), beforeRev + cost);
        assertEq(lottery.totalReservedUSDC(), beforeReserved + cost);
    }

    function test_BuyRevertsIfCreator() public {
        vm.startPrank(creator);
        usdc.approve(address(lottery), type(uint256).max);
        vm.expectRevert(LotterySingleWinner.CreatorCannotBuy.selector);
        lottery.buyTickets(1);
        vm.stopPrank();
    }

    function test_BuyRevertsAfterDeadline() public {
        vm.warp(lottery.deadline());
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.expectRevert(LotterySingleWinner.LotteryExpired.selector);
        lottery.buyTickets(1);
        vm.stopPrank();
    }

    function test_SameBuyerConsecutive_SellsCorrectly() public {
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(3);
        lottery.buyTickets(2);
        vm.stopPrank();

        assertEq(lottery.getSold(), 5);
        assertEq(lottery.ticketsOwned(buyer1), 5);
    }
}