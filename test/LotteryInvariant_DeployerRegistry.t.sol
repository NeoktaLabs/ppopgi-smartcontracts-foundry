// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Base.t.sol";

import "../src/LotteryRegistry.sol";
import "../src/SingleWinnerDeployer.sol";
import "../src/LotterySingleWinner.sol";

import "./mocks/MockUSDC.sol";
import "./mocks/MockEntropy.sol";

/// @notice Fuzz action handler that creates lotteries via the deployer and interacts with them.
/// @dev This is the contract Foundry will call randomly (targetContract).
contract LotteryInvariantHandler is BaseTest {
    LotteryRegistry public registry;
    SingleWinnerDeployer public deployer;
    MockUSDC public usdc;
    MockEntropy public entropy;

    address public admin;
    address public safeOwner;
    address public creator;
    address public buyer1;
    address public buyer2;
    address public feeRecipient;
    address public provider;

    LotterySingleWinner[] internal lots;

    constructor(
        LotteryRegistry _registry,
        SingleWinnerDeployer _deployer,
        MockUSDC _usdc,
        MockEntropy _entropy,
        address _admin,
        address _safeOwner,
        address _creator,
        address _buyer1,
        address _buyer2,
        address _feeRecipient,
        address _provider
    ) {
        registry = _registry;
        deployer = _deployer;
        usdc = _usdc;
        entropy = _entropy;

        admin = _admin;
        safeOwner = _safeOwner;
        creator = _creator;
        buyer1 = _buyer1;
        buyer2 = _buyer2;
        feeRecipient = _feeRecipient;
        provider = _provider;
    }

    // -------- view helpers used by invariants --------

    function lotsLength() external view returns (uint256) {
        return lots.length;
    }

    function lotsAt(uint256 i) external view returns (LotterySingleWinner) {
        return lots[i];
    }

    // -------- internal helpers --------

    function _hasLots() internal view returns (bool) {
        return lots.length > 0;
    }

    function _pickLot(uint256 seed) internal view returns (LotterySingleWinner) {
        return lots[seed % lots.length];
    }

    function _pickActor(uint256 seed) internal view returns (address) {
        // Keep actor set small; include admin/safeOwner occasionally.
        uint256 m = seed % 6;
        if (m == 0) return creator;
        if (m == 1) return buyer1;
        if (m == 2) return buyer2;
        if (m == 3) return feeRecipient;
        if (m == 4) return safeOwner;
        return admin;
    }

    // -------- fuzz actions --------

    /// @notice Create a new lottery through the deployer.
    function act_deployLottery(uint256 seed) external {
        // Keep runtime bounded
        if (lots.length >= 10) return;

        // Bounds must respect LotterySingleWinner constructor constraints:
        // - durationSeconds >= 600
        // - ticketPrice > 0 and satisfy your anti-spam MIN_NEW_RANGE_COST logic
        uint256 winningPot = bound(seed, 1_000 * 1e6, 50_000 * 1e6);
        uint256 ticketPrice = bound(seed >> 16, 1e6, 10e6);
        uint64 minTickets = uint64(bound(seed >> 32, 1, 50));
        uint64 maxTickets = 0; // uncapped
        uint64 durationSeconds = uint64(bound(seed >> 48, 600, 3 days));
        uint32 minPurchaseAmount = 0;

        vm.startPrank(creator);
        usdc.approve(address(deployer), winningPot);

        try deployer.createSingleWinnerLottery(
            "InvLottery",
            ticketPrice,
            winningPot,
            minTickets,
            maxTickets,
            durationSeconds,
            minPurchaseAmount
        ) returns (address lotAddr) {
            lots.push(LotterySingleWinner(payable(lotAddr)));
        } catch {
            // ignore
        }

        vm.stopPrank();
    }

    /// @notice Buy tickets from buyer1/buyer2 only.
    function act_buy(uint256 lotSeed, uint256 actorSeed, uint256 countSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address buyer = _pickActor(actorSeed);

        if (buyer != buyer1 && buyer != buyer2) return;

        if (lot.status() != LotterySingleWinner.Status.Open) return;

        uint256 count = bound(countSeed, 1, lot.MAX_BATCH_BUY());
        uint256 totalCost = lot.ticketPrice() * count;
        if (usdc.balanceOf(buyer) < totalCost) return;

        vm.startPrank(buyer);
        usdc.approve(address(lot), totalCost);
        try lot.buyTickets(count) {} catch {}
        vm.stopPrank();
    }

    /// @notice Warp time forward.
    function act_warp(uint256 dtSeed) external {
        uint256 dt = bound(dtSeed, 0, 10 days);
        vm.warp(block.timestamp + dt);
    }

    /// @notice Finalize when ready; caller pays entropy fee (+ optional overpay).
    function act_finalize(uint256 lotSeed, uint256 actorSeed, uint256 overpaySeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);

        if (lot.status() != LotterySingleWinner.Status.Open) return;
        if (lot.entropyRequestId() != 0) return;

        uint256 fee = entropy.getFee(provider);
        uint256 overpay = bound(overpaySeed, 0, 0.05 ether);
        address caller = _pickActor(actorSeed);

        vm.deal(caller, 10 ether);

        vm.startPrank(caller);
        try lot.finalize{value: fee + overpay}() {} catch {}
        vm.stopPrank();
    }

    /// @notice Fulfill entropy if request is pending.
    function act_fulfill(uint256 lotSeed, bytes32 rand) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        uint64 req = lot.entropyRequestId();
        if (req == 0) return;

        try entropy.fulfill(req, rand) {} catch {}
    }

    /// @notice Attempt normal cancel (deadline passed and minTickets not reached).
    function act_cancel(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Open) return;

        uint64 dl = lot.deadline();
        if (block.timestamp <= dl) vm.warp(uint256(dl) + 1);

        address caller = _pickActor(actorSeed);
        vm.startPrank(caller);
        try lot.cancel() {} catch {}
        vm.stopPrank();
    }

    /// @notice Force-cancel if stuck in Drawing and hatch delay passed.
    function act_forceCancelStuck(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Drawing) return;

        uint64 t = lot.drawingRequestedAt();
        if (t == 0) return;

        vm.warp(uint256(t) + lot.PUBLIC_HATCH_DELAY() + 1);

        address caller = _pickActor(actorSeed);
        vm.startPrank(caller);
        try lot.forceCancelStuck() {} catch {}
        vm.stopPrank();
    }

    /// @notice Claim ticket refunds when canceled.
    function act_claimTicketRefund(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Canceled) return;

        address caller = _pickActor(actorSeed);
        vm.startPrank(caller);
        try lot.claimTicketRefund() {} catch {}
        vm.stopPrank();
    }

    /// @notice Withdraw USDC claimables.
    function act_withdrawFunds(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address caller = _pickActor(actorSeed);

        vm.startPrank(caller);
        try lot.withdrawFunds() {} catch {}
        vm.stopPrank();
    }

    /// @notice Withdraw native claimables.
    function act_withdrawNative(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address caller = _pickActor(actorSeed);

        vm.startPrank(caller);
        try lot.withdrawNative() {} catch {}
        vm.stopPrank();
    }

    /// @notice Sweep USDC surplus (safeOwner is owner of lotteries post-deploy).
    function act_sweepUSDC(uint256 lotSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);

        vm.startPrank(safeOwner);
        try lot.sweepSurplus(safeOwner) {} catch {}
        vm.stopPrank();
    }

    /// @notice Sweep native surplus.
    function act_sweepNative(uint256 lotSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);

        vm.startPrank(safeOwner);
        try lot.sweepNativeSurplus(safeOwner) {} catch {}
        vm.stopPrank();
    }

    /// @notice Update deployer config (admin is deployer owner).
    function act_updateDeployerConfig(uint256 seed) external {
        address newFee = (seed % 2 == 0) ? feeRecipient : admin;
        address newProv = (seed % 3 == 0) ? provider : buyer1;
        uint256 newPct = bound(seed >> 8, 0, 20);

        vm.startPrank(admin);
        try deployer.setConfig(address(usdc), address(entropy), newProv, newFee, newPct) {} catch {}
        vm.stopPrank();
    }
}

/// @notice Invariant test that fuzzes deployer+registry+lottery interactions.
contract LotteryInvariant_DeployerRegistry is BaseTest {
    LotteryInvariantHandler internal handler;

    function setUp() public override {
        super.setUp();

        // ensure fee exists
        vm.startPrank(admin);
        entropy.setFee(provider, 0.01 ether);
        vm.stopPrank();

        handler = new LotteryInvariantHandler(
            registry,
            deployer,
            usdc,
            entropy,
            admin,
            safeOwner,
            creator,
            buyer1,
            buyer2,
            feeRecipient,
            provider
        );

        targetContract(address(handler));
    }

    /// @notice For all deployed lotteries:
    /// - USDC balance covers "reserved" accounting
    /// - native balance covers totalClaimableNative
    /// - drawing state variables are consistent
    function invariant_solvencyAndStateSanity() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            // USDC solvency vs current accounting variable
            uint256 bal = usdc.balanceOf(address(lot));
            uint256 reserved = lot.totalReservedUSDC();
            assertGe(bal, reserved);

            // Native solvency
            assertGe(address(lot).balance, lot.totalClaimableNative());

            // Single-instance lottery should have activeDrawings in {0,1}
            assertLe(lot.activeDrawings(), 1);

            // Drawing sanity
            if (lot.status() == LotterySingleWinner.Status.Drawing) {
                assertTrue(lot.entropyRequestId() != 0);
                assertTrue(lot.drawingRequestedAt() != 0);
                assertTrue(lot.soldAtDrawing() > 0);
            }

            // Open state should have no pending request
            if (lot.status() == LotterySingleWinner.Status.Open) {
                assertEq(lot.entropyRequestId(), 0);
            }
        }
    }

    /// @notice Registry consistency and deployer/safeOwner ownership expectations.
    function invariant_registryConsistency() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            // Created by this deployer and transferred to safeOwner
            assertEq(lot.deployer(), address(deployer));
            assertEq(lot.owner(), safeOwner);

            // If it is registered, registry metadata must match.
            uint256 typeId = registry.typeIdOf(address(lot));
            if (typeId != 0) {
                assertEq(typeId, deployer.SINGLE_WINNER_TYPE_ID());
                assertEq(registry.creatorOf(address(lot)), lot.creator());
                assertTrue(registry.isRegisteredLottery(address(lot)));
            }
        }
    }
}