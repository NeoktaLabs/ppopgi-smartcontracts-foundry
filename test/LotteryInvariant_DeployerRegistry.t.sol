// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/StdInvariant.sol";
import "forge-std/Vm.sol";

import "../src/LotteryRegistry.sol";
import "../src/SingleWinnerDeployer.sol";
import "../src/LotterySingleWinner.sol";

import "./mocks/MockUSDC.sol";
import "./mocks/MockEntropy.sol";

/// @notice Base for invariants: inherit StdInvariant only (avoids diamond with Test).
/// @dev We define our own `_vm` and minimal assert helpers for max compatibility.
contract InvariantBase is StdInvariant {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // ---- minimal assertion helpers (do not depend on forge-std/Test.sol) ----
    function _assertTrue(bool ok, string memory err) internal pure {
        if (!ok) revert(err);
    }

    function _assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function _assertEqAddr(address a, address b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function _assertGe(uint256 a, uint256 b, string memory err) internal pure {
        if (a < b) revert(err);
    }

    function _assertLe(uint256 a, uint256 b, string memory err) internal pure {
        if (a > b) revert(err);
    }
}

/// @notice Handler: fuzz actions. We avoid inheriting Test; we only need Vm + simple bounds.
contract LotteryInvariantHandler {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    // ----- view helpers -----

    function lotsLength() external view returns (uint256) {
        return lots.length;
    }

    function lotsAt(uint256 i) external view returns (LotterySingleWinner) {
        return lots[i];
    }

    // ----- internal helpers -----

    function _hasLots() internal view returns (bool) {
        return lots.length > 0;
    }

    function _pickLot(uint256 seed) internal view returns (LotterySingleWinner) {
        return lots[seed % lots.length];
    }

    function _pickActor(uint256 seed) internal view returns (address) {
        uint256 m = seed % 6;
        if (m == 0) return creator;
        if (m == 1) return buyer1;
        if (m == 2) return buyer2;
        if (m == 3) return feeRecipient;
        if (m == 4) return safeOwner;
        return admin;
    }

    function _bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) return min;
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }

    // ---------------- fuzz actions ----------------

    function act_deployLottery(uint256 seed) external {
        if (lots.length >= 10) return;

        uint256 winningPot = _bound(seed, 1_000 * 1e6, 50_000 * 1e6);
        uint256 ticketPrice = _bound(seed >> 16, 1e6, 10e6);
        uint64 minTickets = uint64(_bound(seed >> 32, 1, 50));
        uint64 maxTickets = 0;
        uint64 durationSeconds = uint64(_bound(seed >> 48, 600, 3 days));
        uint32 minPurchaseAmount = 0;

        _vm.startPrank(creator);
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
        } catch {}

        _vm.stopPrank();
    }

    function act_buy(uint256 lotSeed, uint256 actorSeed, uint256 countSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address buyer = _pickActor(actorSeed);

        if (buyer != buyer1 && buyer != buyer2) return;
        if (lot.status() != LotterySingleWinner.Status.Open) return;

        uint256 count = _bound(countSeed, 1, lot.MAX_BATCH_BUY());
        uint256 totalCost = lot.ticketPrice() * count;
        if (usdc.balanceOf(buyer) < totalCost) return;

        _vm.startPrank(buyer);
        usdc.approve(address(lot), totalCost);
        try lot.buyTickets(count) {} catch {}
        _vm.stopPrank();
    }

    function act_warp(uint256 dtSeed) external {
        uint256 dt = _bound(dtSeed, 0, 10 days);
        _vm.warp(block.timestamp + dt);
    }

    function act_finalize(uint256 lotSeed, uint256 actorSeed, uint256 overpaySeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Open) return;
        if (lot.entropyRequestId() != 0) return;

        uint256 fee = entropy.getFee(provider);
        uint256 overpay = _bound(overpaySeed, 0, 0.05 ether);
        address caller = _pickActor(actorSeed);

        _vm.deal(caller, 10 ether);

        _vm.startPrank(caller);
        try lot.finalize{value: fee + overpay}() {} catch {}
        _vm.stopPrank();
    }

    function act_fulfill(uint256 lotSeed, bytes32 rand) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        uint64 req = lot.entropyRequestId();
        if (req == 0) return;

        try entropy.fulfill(req, rand) {} catch {}
    }

    function act_cancel(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Open) return;

        uint64 dl = lot.deadline();
        if (block.timestamp <= dl) _vm.warp(uint256(dl) + 1);

        address caller = _pickActor(actorSeed);
        _vm.startPrank(caller);
        try lot.cancel() {} catch {}
        _vm.stopPrank();
    }

    function act_forceCancelStuck(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Drawing) return;

        uint64 t = lot.drawingRequestedAt();
        if (t == 0) return;

        _vm.warp(uint256(t) + lot.PUBLIC_HATCH_DELAY() + 1);

        address caller = _pickActor(actorSeed);
        _vm.startPrank(caller);
        try lot.forceCancelStuck() {} catch {}
        _vm.stopPrank();
    }

    function act_claimTicketRefund(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Canceled) return;

        address caller = _pickActor(actorSeed);
        _vm.startPrank(caller);
        try lot.claimTicketRefund() {} catch {}
        _vm.stopPrank();
    }

    function act_withdrawFunds(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address caller = _pickActor(actorSeed);

        _vm.startPrank(caller);
        try lot.withdrawFunds() {} catch {}
        _vm.stopPrank();
    }

    function act_withdrawNative(uint256 lotSeed, uint256 actorSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        address caller = _pickActor(actorSeed);

        _vm.startPrank(caller);
        try lot.withdrawNative() {} catch {}
        _vm.stopPrank();
    }

    function act_sweepUSDC(uint256 lotSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);

        _vm.startPrank(safeOwner);
        try lot.sweepSurplus(safeOwner) {} catch {}
        _vm.stopPrank();
    }

    function act_sweepNative(uint256 lotSeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);

        _vm.startPrank(safeOwner);
        try lot.sweepNativeSurplus(safeOwner) {} catch {}
        _vm.stopPrank();
    }

    function act_updateDeployerConfig(uint256 seed) external {
        address newFee = (seed % 2 == 0) ? feeRecipient : admin;
        address newProv = (seed % 3 == 0) ? provider : buyer1;
        uint256 newPct = _bound(seed >> 8, 0, 20);

        _vm.startPrank(admin);
        try deployer.setConfig(address(usdc), address(entropy), newProv, newFee, newPct) {} catch {}
        _vm.stopPrank();
    }
}

contract LotteryInvariant_DeployerRegistry is InvariantBase {
    address internal admin;
    address internal safeOwner;
    address internal creator;
    address internal buyer1;
    address internal buyer2;
    address internal feeRecipient;
    address internal provider;

    LotteryRegistry internal registry;
    SingleWinnerDeployer internal deployer;

    MockUSDC internal usdc;
    MockEntropy internal entropy;

    LotteryInvariantHandler internal handler;

    /// @dev Known actors whose claimables we can sum deterministically in invariants.
    ///      Winner is added dynamically per lottery (if not already in this list).
    address[] internal actors;

    function setUp() public {
        admin        = _vm.addr(1);
        safeOwner    = _vm.addr(2);
        creator      = _vm.addr(3);
        buyer1       = _vm.addr(4);
        buyer2       = _vm.addr(5);
        feeRecipient = _vm.addr(6);
        provider     = _vm.addr(7);

        _vm.startPrank(admin);

        usdc = new MockUSDC();
        entropy = new MockEntropy();
        entropy.setFee(provider, 0.01 ether);

        registry = new LotteryRegistry(admin);

        deployer = new SingleWinnerDeployer(
            admin,
            address(registry),
            safeOwner,
            address(usdc),
            address(entropy),
            provider,
            feeRecipient,
            10
        );

        registry.setRegistrar(address(deployer), true);

        _vm.stopPrank();

        usdc.mint(creator, 50_000_000 * 1e6);
        usdc.mint(buyer1, 50_000_000 * 1e6);
        usdc.mint(buyer2, 50_000_000 * 1e6);

        _vm.deal(creator, 100 ether);
        _vm.deal(buyer1, 100 ether);
        _vm.deal(buyer2, 100 ether);
        _vm.deal(admin, 100 ether);
        _vm.deal(safeOwner, 100 ether);
        _vm.deal(feeRecipient, 100 ether);

        // ---- actors list for deterministic claimable sums ----
        actors.push(admin);
        actors.push(safeOwner);
        actors.push(creator);
        actors.push(buyer1);
        actors.push(buyer2);
        actors.push(feeRecipient);

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

    function invariant_solvencyAndStateSanity() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            _assertGe(usdc.balanceOf(address(lot)), lot.totalReservedUSDC(), "USDC insolvent vs reserved");
            _assertGe(address(lot).balance, lot.totalClaimableNative(), "Native insolvent vs claimable");
            _assertLe(lot.activeDrawings(), 1, "activeDrawings out of range");

            if (lot.status() == LotterySingleWinner.Status.Drawing) {
                _assertTrue(lot.entropyRequestId() != 0, "Drawing: missing requestId");
                _assertTrue(lot.drawingRequestedAt() != 0, "Drawing: missing requestedAt");
                _assertTrue(lot.soldAtDrawing() > 0, "Drawing: soldAtDrawing=0");
            }

            if (lot.status() == LotterySingleWinner.Status.Open) {
                _assertEq(lot.entropyRequestId(), 0, "Open: entropyRequestId should be 0");
            }
        }
    }

    function invariant_registryConsistency() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            _assertEqAddr(lot.deployer(), address(deployer), "lot.deployer mismatch");
            _assertEqAddr(lot.owner(), safeOwner, "lot.owner mismatch");

            uint256 typeId = registry.typeIdOf(address(lot));
            if (typeId != 0) {
                _assertEq(typeId, deployer.SINGLE_WINNER_TYPE_ID(), "registry typeId mismatch");
                _assertEqAddr(registry.creatorOf(address(lot)), lot.creator(), "registry creator mismatch");
                _assertTrue(registry.isRegisteredLottery(address(lot)), "registry says not registered");
            }
        }
    }

    // ------------------------------------------------------------------------
    // New invariants (added)
    // ------------------------------------------------------------------------

    /// @notice Claimable USDC for known actors (and the current winner) must never exceed
    ///         the contract's reserved liabilities; reserved liabilities must remain solvent.
    /// @dev We can't iterate all possible addresses in fuzzing, but summing protocol roles +
    ///      buyers + winner catches the common accounting failure modes.
    function invariant_claimablesBoundedByReserved() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            uint256 sum;
            for (uint256 j = 0; j < actors.length; j++) {
                sum += lot.claimableFunds(actors[j]);
            }

            // Include winner (may not be in actors list).
            address w = lot.winner();
            if (w != address(0)) {
                bool winnerAlreadyCounted;
                for (uint256 j = 0; j < actors.length; j++) {
                    if (actors[j] == w) {
                        winnerAlreadyCounted = true;
                        break;
                    }
                }
                if (!winnerAlreadyCounted) {
                    sum += lot.claimableFunds(w);
                }
            }

            _assertLe(sum, lot.totalReservedUSDC(), "claimables sum > totalReservedUSDC");
            _assertGe(usdc.balanceOf(address(lot)), lot.totalReservedUSDC(), "USDC insolvent vs reserved (claimables)");
        }
    }

    /// @notice Entropy request bookkeeping must match the state machine:
    ///         - requestId != 0  => status == Drawing and requestedAt != 0
    ///         - status == Drawing => requestId != 0
    function invariant_entropyRequestMatchesStatus() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            uint64 req = lot.entropyRequestId();
            LotterySingleWinner.Status st = lot.status();

            if (req != 0) {
                _assertEq(uint256(st), uint256(LotterySingleWinner.Status.Drawing), "reqId set while not Drawing");
                _assertTrue(lot.drawingRequestedAt() != 0, "reqId set but requestedAt=0");
            }

            if (st == LotterySingleWinner.Status.Drawing) {
                _assertTrue(req != 0, "Drawing but reqId=0");
            }
        }
    }
}