// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

contract LotteryPolishTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    // -----------------------------
    // Deadline boundary behavior
    // -----------------------------

    function test_BuyBoundary_DeadlineMinus1Succeeds_DeadlineReverts() public {
        // Buy at deadline - 1 should succeed
        vm.warp(lottery.deadline() - 1);

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(1);
        vm.stopPrank();

        assertEq(lottery.getSold(), 1);

        // Buy at deadline should revert (contract checks block.timestamp >= deadline)
        vm.warp(lottery.deadline());

        vm.startPrank(buyer1);
        vm.expectRevert(LotterySingleWinner.LotteryExpired.selector);
        lottery.buyTickets(1);
        vm.stopPrank();
    }

    function test_FinalizeAtExactDeadline_SucceedsWhenMinTicketsReached() public {
        // Reach minTickets
        uint256 need = uint256(lottery.minTickets());

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(need);
        vm.stopPrank();

        // Finalize at exact deadline should be allowed (expired == true)
        vm.warp(lottery.deadline());

        uint256 fee = entropy.getFee(provider);
        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Drawing));
        assertTrue(lottery.entropyRequestId() != 0);
    }

    // -----------------------------
    // MaxTickets enforcement
    // -----------------------------

    function test_MaxTickets_ExactlyMaxSucceeds_OverMaxReverts() public {
        // Deploy a capped lottery using real deployer flow
        vm.startPrank(creator);
        usdc.approve(address(deployer), type(uint256).max);

        address lotAddr = deployer.createSingleWinnerLottery(
            "MaxTickets Cap Test",
            2 * 1e6,      // ticket price
            100 * 1e6,    // winning pot
            1,            // minTickets
            5,            // maxTickets
            3600,         // duration
            0             // minPurchaseAmount
        );
        vm.stopPrank();

        LotterySingleWinner l = LotterySingleWinner(payable(lotAddr));

        // Buy exactly max (5) succeeds
        vm.startPrank(buyer1);
        usdc.approve(address(l), type(uint256).max);
        l.buyTickets(5);
        vm.stopPrank();

        assertEq(l.getSold(), 5);

        // Any additional ticket should revert (TicketLimitReached)
        vm.startPrank(buyer2);
        usdc.approve(address(l), type(uint256).max);
        vm.expectRevert(LotterySingleWinner.TicketLimitReached.selector);
        l.buyTickets(1);
        vm.stopPrank();
    }

    // -----------------------------
    // Withdraw end-to-end correctness
    // -----------------------------

    function test_Withdraw_EndToEnd_WinnerCreatorProtocolAndReservedAccounting() public {
        // Only buyer1 buys so winner must be buyer1
        uint256 need = uint256(lottery.minTickets());

        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(need);
        vm.stopPrank();

        vm.warp(lottery.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(buyer2);
        lottery.finalize{value: fee}();

        uint64 reqId = lottery.entropyRequestId();
        entropy.fulfill(reqId, bytes32(uint256(123)));

        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lottery.winner(), buyer1);

        // Snapshot claimables + reserved before withdrawals
        uint256 wClaim = lottery.claimableFunds(buyer1);
        uint256 cClaim = lottery.claimableFunds(creator);
        uint256 pClaim = lottery.claimableFunds(feeRecipient);

        uint256 reservedBefore = lottery.totalReservedUSDC();

        uint256 wBalBefore = usdc.balanceOf(buyer1);
        uint256 cBalBefore = usdc.balanceOf(creator);
        uint256 pBalBefore = usdc.balanceOf(feeRecipient);

        // Winner withdraw
        vm.prank(buyer1);
        lottery.withdrawFunds();
        assertEq(usdc.balanceOf(buyer1), wBalBefore + wClaim);

        // Creator withdraw
        vm.prank(creator);
        lottery.withdrawFunds();
        assertEq(usdc.balanceOf(creator), cBalBefore + cClaim);

        // Protocol withdraw
        vm.prank(feeRecipient);
        lottery.withdrawFunds();
        assertEq(usdc.balanceOf(feeRecipient), pBalBefore + pClaim);

        // totalReservedUSDC should decrease by total withdrawn
        uint256 reservedAfter = lottery.totalReservedUSDC();
        assertEq(reservedBefore - reservedAfter, wClaim + cClaim + pClaim);

        // Claimables should be zeroed
        assertEq(lottery.claimableFunds(buyer1), 0);
        assertEq(lottery.claimableFunds(creator), 0);
        assertEq(lottery.claimableFunds(feeRecipient), 0);
    }

    // -----------------------------
    // Registry assertions after creation
    // -----------------------------

    function test_Registry_AfterCreate_IsRegisteredWithCorrectMetadata() public {
        address lotAddr = address(lottery);

        assertTrue(registry.isRegisteredLottery(lotAddr));
        assertEq(registry.typeIdOf(lotAddr), 1);
        assertEq(registry.creatorOf(lotAddr), creator);

        // sanity: lottery ownership was transferred to safeOwner by deployer
        assertEq(lottery.owner(), safeOwner);
        assertEq(lottery.creator(), creator);
    }
}