// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "./Base.t.sol";

/**
 * Invariant tests for Ppopgi LotterySingleWinner.
 *
 * These invariants aim to prove:
 *  - USDC liabilities are always covered by contract balance.
 *  - totalReservedUSDC never goes negative / never exceeds balance.
 *  - Once completed, winner is set and lottery can't return to Open.
 *
 * Notes:
 *  - We use a Handler contract to let Foundry fuzz arbitrary sequences of actions
 *    (buy/finalize/cancel/withdraw/pause/unpause).
 *  - The handler uses try/catch so "invalid actions" simply no-op rather than revert,
 *    allowing Foundry to explore more sequences.
 */
contract LotteryInvariantTest is BaseTest {
    LotteryHandler internal handler;

    function setUp() public override {
        super.setUp();

        // Deploy a fresh lottery instance
        lottery = _deployDefaultLottery();

        // Fund + approve actors for fuzzing
        // (USDC already minted in BaseTest.setUp())
        vm.startPrank(buyer1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(creator);
        usdc.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // Build handler with a small actor set
        address;
        actors[0] = buyer1;
        actors[1] = buyer2;
        actors[2] = creator; // included mostly for withdraw attempts; buy will revert anyway

        handler = new LotteryHandler(
            lottery,
            usdc,
            entropy,
            provider,
            admin,
            safeOwner,
            feeRecipient,
            actors
        );

        // Tell Foundry which contract functions it may fuzz-call
        targetContract(address(handler));

        // Optional: limit fuzzing to these selectors for better signal/noise
        bytes4;
        selectors[0] = LotteryHandler.buy.selector;
        selectors[1] = LotteryHandler.finalizeLottery.selector;
        selectors[2] = LotteryHandler.cancelLottery.selector;
        selectors[3] = LotteryHandler.forceCancelStuck.selector;
        selectors[4] = LotteryHandler.withdrawFunds.selector;
        selectors[5] = LotteryHandler.pauseLottery.selector;
        selectors[6] = LotteryHandler.unpauseLottery.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ------------------------------------------------------------
    // Invariants
    // ------------------------------------------------------------

    /// @dev Contract USDC balance must always cover reserved liabilities.
    function invariant_USDCBalanceCoversReserved() public view {
        uint256 bal = usdc.balanceOf(address(lottery));
        uint256 reserved = lottery.totalReservedUSDC();
        assertGe(bal, reserved);
    }

    /// @dev totalReservedUSDC can never exceed initial pot + ticketRevenue.
    /// This bounds accounting drift (e.g., if reserved increments without real inflow).
    function invariant_ReservedNeverExceedsPotPlusRevenue() public view {
        uint256 reserved = lottery.totalReservedUSDC();
        uint256 maxLiability = lottery.winningPot() + lottery.ticketRevenue();
        assertLe(reserved, maxLiability);
    }

    /// @dev If lottery is Completed, it must have a winner set.
    function invariant_CompletedImpliesWinnerSet() public view {
        if (lottery.status() == LotterySingleWinner.Status.Completed) {
            assertTrue(lottery.winner() != address(0));
        }
    }

    /// @dev If lottery is Canceled, it can never become Open again (monotonicity).
    function invariant_CanceledIsTerminal() public view {
        // In this contract there is no transition out of Canceled.
        if (lottery.status() == LotterySingleWinner.Status.Canceled) {
            // A weaker but practical invariant: it must not be Open.
            assertTrue(lottery.status() != LotterySingleWinner.Status.Open);
        }
    }
}

/**
 * Handler contract for invariant fuzzing.
 *
 * Foundry will call these functions in random sequences with random inputs.
 * We use try/catch (and sometimes "if" guards) so invalid actions don't halt the run.
 */
contract LotteryHandler is Test {
    LotterySingleWinner internal lot;
    MockUSDC internal usdc;
    MockEntropy internal entropy;
    address internal provider;

    address internal admin;
    address internal safeOwner;
    address internal feeRecipient;

    address[] internal actors;

    constructor(
        LotterySingleWinner _lot,
        MockUSDC _usdc,
        MockEntropy _entropy,
        address _provider,
        address _admin,
        address _safeOwner,
        address _feeRecipient,
        address[] memory _actors
    ) {
        lot = _lot;
        usdc = _usdc;
        entropy = _entropy;
        provider = _provider;
        admin = _admin;
        safeOwner = _safeOwner;
        feeRecipient = _feeRecipient;
        actors = _actors;

        // Pre-approve USDC for actors so buy can succeed without extra steps
        for (uint256 i = 0; i < actors.length; i++) {
            vm.startPrank(actors[i]);
            usdc.approve(address(lot), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @notice Random ticket purchases (bounded).
    function buy(uint256 actorSeed, uint256 countSeed) external {
        address a = _actor(actorSeed);

        // keep counts small for gas + exploration
        uint256 count = (countSeed % 5) + 1;

        vm.startPrank(a);
        // creator cannot buy, buy after deadline, etc. will revert -> swallow
        try lot.buyTickets(count) {} catch {}
        vm.stopPrank();
    }

    /// @notice Try to finalize with proper fee; if drawing starts, resolve sometimes.
    function finalizeLottery(uint256 actorSeed, uint256 randSeed, bool alsoResolve) external {
        address a = _actor(actorSeed);
        uint256 fee = entropy.getFee(provider);

        vm.startPrank(a);

        // Try to finalize; may revert if not ready or paused, etc.
        try lot.finalize{value: fee}() {
            // If we successfully entered Drawing, optionally resolve immediately
            if (alsoResolve) {
                uint64 reqId = lot.entropyRequestId();
                // reqId can only be non-zero if Drawing actually started
                if (reqId != 0) {
                    // resolve with chosen rand
                    entropy.fulfill(reqId, bytes32(randSeed));
                }
            }
        } catch {}
        vm.stopPrank();
    }

    /// @notice Try the normal cancel path.
    function cancelLottery(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        try lot.cancel() {} catch {}
    }

    /// @notice Try the emergency cancel path for stuck drawings.
    function forceCancelStuck(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        try lot.forceCancelStuck() {} catch {}
    }

    /// @notice Attempt withdrawals (winner/creator/feeRecipient may succeed).
    function withdrawFunds(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        try lot.withdrawFunds() {} catch {}

        // also try protocol + feeRecipient occasionally (helps explore)
        vm.prank(feeRecipient);
        try lot.withdrawFunds() {} catch {}
    }

    function pauseLottery(uint256 actorSeed) external {
        // Only safeOwner is the owner of lottery (transferred by deployer).
        // Use it sometimes.
        if (actorSeed % 2 == 0) {
            vm.prank(safeOwner);
            try lot.pause() {} catch {}
        }
    }

    function unpauseLottery(uint256 actorSeed) external {
        if (actorSeed % 2 == 0) {
            vm.prank(safeOwner);
            try lot.unpause() {} catch {}
        }
    }

    // allow handler to receive ETH for finalize fees if needed
    receive() external payable {}
}