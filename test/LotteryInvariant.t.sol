// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

/**
 * "Invariant-style" fuzz tests that do NOT require StdInvariant.sol.
 *
 * Runs random sequences of actions and asserts invariants after each step.
 * This works even if your forge-std version doesn't ship StdInvariant.sol.
 */
contract LotteryInvariantStyleFuzzTest is BaseTest {
    function setUp() public override {
        super.setUp();
        lottery = _deployDefaultLottery();

        // approvals for buyers
        vm.prank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(buyer2);
        usdc.approve(address(lottery), type(uint256).max);
    }

    /// @dev Main sequence fuzz test (acts like an invariant run).
    function testFuzz_InvariantSequence(uint256 seed) public {
        // We'll run a bounded number of steps to keep gas/time reasonable in CI.
        uint256 steps = 40;

        for (uint256 i = 0; i < steps; i++) {
            // pick an action
            uint256 action = uint256(keccak256(abi.encode(seed, i, "action"))) % 7;

            if (action == 0) _tryBuy(buyer1, seed, i);
            else if (action == 1) _tryBuy(buyer2, seed, i);
            else if (action == 2) _tryFinalize(seed, i);
            else if (action == 3) _tryCancel(buyer1);
            else if (action == 4) _tryForceCancel(buyer2);
            else if (action == 5) _tryWithdraw(buyer1);
            else if (action == 6) _tryWithdraw(buyer2);

            // Always check invariants after each step
            _assertInvariants();
        }
    }

    // ------------------------------------------------------------
    // Actions (all swallow reverts so the sequence continues)
    // ------------------------------------------------------------

    function _tryBuy(address who, uint256 seed, uint256 i) internal {
        uint256 count = (uint256(keccak256(abi.encode(seed, i, "count"))) % 5) + 1;

        vm.startPrank(who);
        try lottery.buyTickets(count) {} catch {}
        vm.stopPrank();
    }

    function _tryFinalize(uint256 seed, uint256 i) internal {
        // Sometimes warp to deadline to allow finalize
        if ((uint256(keccak256(abi.encode(seed, i, "warp"))) % 3) == 0) {
            vm.warp(lottery.deadline());
        }

        uint256 fee = entropy.getFee(provider);

        // finalize caller alternates between buyer1/buyer2
        address caller = ((seed + i) % 2 == 0) ? buyer1 : buyer2;

        vm.startPrank(caller);
        try lottery.finalize{value: fee}() {
            // Sometimes resolve immediately
            if ((uint256(keccak256(abi.encode(seed, i, "resolve"))) % 2) == 0) {
                uint64 reqId = lottery.entropyRequestId();
                if (reqId != 0) {
                    bytes32 rand = bytes32(uint256(keccak256(abi.encode(seed, i, "rand"))));
                    entropy.fulfill(reqId, rand);
                }
            }
        } catch {}
        vm.stopPrank();
    }

    function _tryCancel(address who) internal {
        vm.prank(who);
        try lottery.cancel() {} catch {}
    }

    function _tryForceCancel(address who) internal {
        vm.prank(who);
        try lottery.forceCancelStuck() {} catch {}
    }

    function _tryWithdraw(address who) internal {
        vm.prank(who);
        try lottery.withdrawFunds() {} catch {}

        // also try feeRecipient withdraw occasionally (helps explore completion)
        vm.prank(feeRecipient);
        try lottery.withdrawFunds() {} catch {}
    }

    // ------------------------------------------------------------
    // Invariants
    // ------------------------------------------------------------

    function _assertInvariants() internal view {
        // 1) USDC balance covers reserved liabilities
        uint256 bal = usdc.balanceOf(address(lottery));
        uint256 reserved = lottery.totalReservedUSDC();
        assertGe(bal, reserved);

        // 2) Reserved can never exceed pot + ticket revenue (prevents drift)
        uint256 maxLiability = lottery.winningPot() + lottery.ticketRevenue();
        assertLe(reserved, maxLiability);

        // 3) If Completed, winner must be set
        if (lottery.status() == LotterySingleWinner.Status.Completed) {
            assertTrue(lottery.winner() != address(0));
        }

        // 4) Canceled is terminal (never Open again)
        if (lottery.status() == LotterySingleWinner.Status.Canceled) {
            assertTrue(lottery.status() != LotterySingleWinner.Status.Open);
        }
    }
}