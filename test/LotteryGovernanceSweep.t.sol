// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";
import "./mocks/RevertingReceiver.sol";

contract LotteryGovernanceSweepTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();
    }

    function _buyMinAndFinalizeToDrawing(LotterySingleWinner l, address buyer, address finalizer) internal returns (uint64) {
        // Ensure minTickets reached
        vm.startPrank(buyer);
        usdc.approve(address(l), type(uint256).max);
        l.buyTickets(l.minTickets());
        vm.stopPrank();

        // Finalize at/after deadline
        vm.warp(l.deadline());
        uint256 fee = entropy.getFee(provider);

        vm.prank(finalizer);
        l.finalize{value: fee}();

        assertEq(uint256(l.status()), uint256(LotterySingleWinner.Status.Drawing));
        assertEq(l.activeDrawings(), 1);

        return l.entropyRequestId();
    }

    // -----------------------------
    // Governance locks
    // -----------------------------

    function test_GovernanceLock_BlocksEntropyUpdatesWhileDrawing() public {
        uint64 reqId = _buyMinAndFinalizeToDrawing(lottery, buyer1, buyer2);
        assertTrue(reqId != 0);

        vm.startPrank(safeOwner);

        vm.expectRevert(LotterySingleWinner.DrawingsActive.selector);
        lottery.setEntropyProvider(address(0xBEEF));

        vm.expectRevert(LotterySingleWinner.DrawingsActive.selector);
        lottery.setEntropyContract(address(0xCAFE));

        vm.stopPrank();
    }

    function test_GovernanceLock_AllowsEntropyUpdatesAfterResolve() public {
        uint64 reqId = _buyMinAndFinalizeToDrawing(lottery, buyer1, buyer2);

        // Resolve
        entropy.fulfill(reqId, bytes32(uint256(123)));
        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Completed));
        assertEq(lottery.activeDrawings(), 0);

        vm.startPrank(safeOwner);

        address newProvider = address(0xBEEF);
        MockEntropy newEntropy = new MockEntropy();
        newEntropy.setFee(newProvider, 0.01 ether);

        lottery.setEntropyProvider(newProvider);
        assertEq(lottery.entropyProvider(), newProvider);

        lottery.setEntropyContract(address(newEntropy));
        assertEq(address(lottery.entropy()), address(newEntropy));

        vm.stopPrank();
    }

    // -----------------------------
    // USDC sweep safety
    // -----------------------------

    function test_SweepSurplus_RevertsWhenNoTrueSurplus() public {
        // Create liabilities: pot + ticket revenue still reserved
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        // With liabilities outstanding, balance should equal reserved (no surplus)
        vm.startPrank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(safeOwner);
        vm.stopPrank();
    }

    function test_SweepSurplus_SweepsOnlyExtraUSDC() public {
        // Create some liabilities
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        lottery.buyTickets(2);
        vm.stopPrank();

        // Send accidental extra USDC directly to the lottery
        uint256 extra = 123 * 1e6;
        vm.prank(creator);
        usdc.transfer(address(lottery), extra);

        uint256 ownerBefore = usdc.balanceOf(safeOwner);

        vm.prank(safeOwner);
        lottery.sweepSurplus(safeOwner);

        uint256 ownerAfter = usdc.balanceOf(safeOwner);
        assertEq(ownerAfter - ownerBefore, extra);

        // After sweeping, reserved should still be covered exactly (no further surplus)
        vm.prank(safeOwner);
        vm.expectRevert(LotterySingleWinner.NoSurplus.selector);
        lottery.sweepSurplus(safeOwner);
    }

    // -----------------------------
    // Native sweep safety
    // -----------------------------

    function test_SweepNativeSurplus_ProtectsClaimableNative() public {
        // Create a native claimable by forcing a refund to a contract that rejects ETH
        RevertingReceiver rr = new RevertingReceiver();
        uint256 refundAmt = 0.2 ether;

        // Call finalize on a not-ready lottery (will revert) isn't useful; instead:
        // We can force native claimable through _safeNativeTransfer by triggering the cancel branch
        // and making msg.sender a reverting receiver.
        //
        // To enter cancel branch in finalize():
        // - warp to deadline
        // - sold < minTickets
        // Then finalize refunds msg.value back to msg.sender; if receiver rejects, it becomes claimableNative.

        vm.warp(lottery.deadline());

        uint256 beforeClaimable = lottery.claimableNative(address(rr));
        assertEq(beforeClaimable, 0);

        // Call finalize from rr via a low-level call so msg.sender is rr
        bytes memory callData = abi.encodeWithSelector(LotterySingleWinner.finalize.selector);
        vm.deal(address(rr), refundAmt);

        vm.prank(address(rr));
        (bool ok,) = address(lottery).call{value: refundAmt}(callData);
        assertTrue(ok);

        // Lottery should be canceled and rr should have claimableNative
        assertEq(uint256(lottery.status()), uint256(LotterySingleWinner.Status.Canceled));
        assertEq(lottery.claimableNative(address(rr)), refundAmt);
        assertEq(lottery.totalClaimableNative(), refundAmt);

        // Send extra native to the lottery to create sweepable surplus
        uint256 extra = 0.5 ether;
        vm.deal(creator, creator.balance + extra);
        vm.prank(creator);
        (bool sent,) = address(lottery).call{value: extra}("");
        assertTrue(sent);

        uint256 ownerBefore = safeOwner.balance;

        // Sweep should only sweep the extra (not the claimableNative)
        vm.prank(safeOwner);
        lottery.sweepNativeSurplus(safeOwner);

        uint256 ownerAfter = safeOwner.balance;
        assertEq(ownerAfter - ownerBefore, extra);

        // Claimable should still be intact
        assertEq(lottery.claimableNative(address(rr)), refundAmt);
        assertEq(lottery.totalClaimableNative(), refundAmt);
    }
}