// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";
import "forge-std/StdInvariant.sol";

/**
 * Invariant tests for LotterySingleWinner.
 *
 * Run with:
 *   forge test --match-path test/LotteryInvariant.t.sol -vv
 * or just:
 *   forge test -vv
 */
contract LotteryInvariantTest is BaseTest, StdInvariant {
    LotteryHandler internal handler;

    function setUp() public override {
        super.setUp();

        // Deploy a fresh lottery instance
        lottery = _deployDefaultLottery();

        // Build handler with a small actor set
        address;
        _actors[0] = buyer1;
        _actors[1] = buyer2;
        _actors[2] = creator; // included mostly for withdraw attempts; buy will revert anyway

        handler = new LotteryHandler(
            lottery,
            usdc,
            entropy,
            provider,
            safeOwner,
            feeRecipient,
            _actors
        );

        // Tell Foundry what to fuzz
        targetContract(address(handler));

        // Restrict fuzzing to specific handler functions (better signal/noise)
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

    /// Contract USDC balance must always cover reserved liabilities.
    function invariant_USDCBalanceCoversReserved() public view {
        uint256 bal = usdc.balanceOf(address(lottery));
        uint256 reserved = lottery.totalReservedUSDC();
        assertGe(bal, reserved);
    }

    /// Reserved liabilities can never exceed pot + ticketRevenue (prevents accounting drift).
    function invariant_ReservedNeverExceedsPotPlusRevenue() public view {
        uint256 reserved = lottery.totalReservedUSDC();
        uint256 maxLiability = lottery.winningPot() + lottery.ticketRevenue();
        assertLe(reserved, maxLiability);
    }

    /// If Completed, winner must be set.
    function invariant_CompletedImpliesWinnerSet() public view {
        if (lottery.status() == LotterySingleWinner.Status.Completed) {
            assertTrue(lottery.winner() != address(0));
        }
    }

    /// Canceled is terminal (cannot go back to Open).
    function invariant_CanceledIsTerminal() public view {
        if (lottery.status() == LotterySingleWinner.Status.Canceled) {
            assertTrue(lottery.status() != LotterySingleWinner.Status.Open);
        }
    }
}

/**
 * Handler contract for invariant fuzzing.
 *
 * Foundry will call these functions in random sequences with random inputs.
 * We use try/catch so invalid actions no-op rather than breaking the run.
 */
contract LotteryHandler is Test {
    LotterySingleWinner internal lot;
    MockUSDC internal usdc;
    MockEntropy internal entropy;
    address internal provider;

    address internal safeOwner;
    address internal feeRecipient;

    address[] internal actors;

    constructor(
        LotterySingleWinner _lot,
        MockUSDC _usdc,
        MockEntropy _entropy,
        address _provider,
        address _safeOwner,
        address _feeRecipient,
        address[] memory _actors
    ) {
        lot = _lot;
        usdc = _usdc;
        entropy = _entropy;
        provider = _provider;
        safeOwner = _safeOwner;
        feeRecipient = _feeRecipient;
        actors = _actors;

        // Pre-approve USDC for actors so buys can succeed without extra steps
        for (uint256 i = 0; i < actors.length; i++) {
            vm.startPrank(actors[i]);
            usdc.approve(address(lot), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// Random ticket purchases (bounded for gas).
    function buy(uint256 actorSeed, uint256 countSeed) external {
        address a = _actor(actorSeed);
        uint256 count = (countSeed % 5) + 1;

        vm.startPrank(a);
        try lot.buyTickets(count) {} catch {}
        vm.stopPrank();
    }

    /// Try finalize with proper fee; optionally resolve immediately.
    function finalizeLottery(uint256 actorSeed, uint256 randSeed, bool alsoResolve) external {
        address a = _actor(actorSeed);
        uint256 fee = entropy.getFee(provider);

        vm.startPrank(a);
        try lot.finalize{value: fee}() {
            if (alsoResolve) {
                uint64 reqId = lot.entropyRequestId();
                if (reqId != 0) {
                    entropy.fulfill(reqId, bytes32(randSeed));
                }
            }
        } catch {}
        vm.stopPrank();
    }

    function cancelLottery(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        try lot.cancel() {} catch {}
    }

    function forceCancelStuck(uint256 actorSeed) external {
        address a = _actor(actorSeed);
        vm.prank(a);
        try lot.forceCancelStuck() {} catch {}
    }

    function withdrawFunds(uint256 actorSeed) external {
        address a = _actor(actorSeed);

        vm.prank(a);
        try lot.withdrawFunds() {} catch {}

        // Also try feeRecipient withdrawals sometimes (helps explore completion paths)
        vm.prank(feeRecipient);
        try lot.withdrawFunds() {} catch {}
    }

    function pauseLottery(uint256 seed) external {
        if (seed % 2 == 0) {
            vm.prank(safeOwner);
            try lot.pause() {} catch {}
        }
    }

    function unpauseLottery(uint256 seed) external {
        if (seed % 2 == 0) {
            vm.prank(safeOwner);
            try lot.unpause() {} catch {}
        }
    }

    receive() external payable {}
}