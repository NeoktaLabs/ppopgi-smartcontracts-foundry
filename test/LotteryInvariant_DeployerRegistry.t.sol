// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Vm.sol";

import "../src/LotteryRegistry.sol";
import "../src/SingleWinnerDeployer.sol";
import "../src/LotterySingleWinner.sol";

import "./mocks/MockUSDC.sol";
import "./mocks/MockEntropy.sol";
import "./mocks/RevertingReceiver.sol";

/// @notice Separate base class for invariant tests to avoid inheritance diamond.
/// @dev Define our own `vm` handle explicitly (for older forge-std where `vm` isn't auto-exposed).
contract InvariantBaseTest is StdInvariant {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function setUp() public virtual {
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
    }
}

/// @notice Fuzz action handler that creates lotteries via the deployer and interacts with them.
/// @dev Uses its own `_vm` handle (do not rely on `vm` being injected by forge-std version).
contract LotteryInvariantHandler is Test {
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

    function lotsLength() external view returns (uint256) {
        return lots.length;
    }

    function lotsAt(uint256 i) external view returns (LotterySingleWinner) {
        return lots[i];
    }

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

    // ---------------- fuzz actions ----------------

    function act_deployLottery(uint256 seed) external {
        if (lots.length >= 10) return;

        uint256 winningPot = bound(seed, 1_000 * 1e6, 50_000 * 1e6);
        uint256 ticketPrice = bound(seed >> 16, 1e6, 10e6);
        uint64 minTickets = uint64(bound(seed >> 32, 1, 50));
        uint64 maxTickets = 0;
        uint64 durationSeconds = uint64(bound(seed >> 48, 600, 3 days));
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

        uint256 count = bound(countSeed, 1, lot.MAX_BATCH_BUY());
        uint256 totalCost = lot.ticketPrice() * count;
        if (usdc.balanceOf(buyer) < totalCost) return;

        _vm.startPrank(buyer);
        usdc.approve(address(lot), totalCost);
        try lot.buyTickets(count) {} catch {}
        _vm.stopPrank();
    }

    function act_warp(uint256 dtSeed) external {
        uint256 dt = bound(dtSeed, 0, 10 days);
        _vm.warp(block.timestamp + dt);
    }

    function act_finalize(uint256 lotSeed, uint256 actorSeed, uint256 overpaySeed) external {
        if (!_hasLots()) return;

        LotterySingleWinner lot = _pickLot(lotSeed);
        if (lot.status() != LotterySingleWinner.Status.Open) return;
        if (lot.entropyRequestId() != 0) return;

        uint256 fee = entropy.getFee(provider);
        uint256 overpay = bound(overpaySeed, 0, 0.05 ether);
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
        uint256 newPct = bound(seed >> 8, 0, 20);

        _vm.startPrank(admin);
        try deployer.setConfig(address(usdc), address(entropy), newProv, newFee, newPct) {} catch {}
        _vm.stopPrank();
    }
}

contract LotteryInvariant_DeployerRegistry is InvariantBaseTest {
    LotteryInvariantHandler internal handler;

    function setUp() public override {
        super.setUp();

        _vm.startPrank(admin);
        entropy.setFee(provider, 0.01 ether);
        _vm.stopPrank();

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

            assertGe(usdc.balanceOf(address(lot)), lot.totalReservedUSDC());
            assertGe(address(lot).balance, lot.totalClaimableNative());
            assertLe(lot.activeDrawings(), 1);

            if (lot.status() == LotterySingleWinner.Status.Drawing) {
                assertTrue(lot.entropyRequestId() != 0);
                assertTrue(lot.drawingRequestedAt() != 0);
                assertTrue(lot.soldAtDrawing() > 0);
            }

            if (lot.status() == LotterySingleWinner.Status.Open) {
                assertEq(lot.entropyRequestId(), 0);
            }
        }
    }

    function invariant_registryConsistency() public view {
        uint256 n = handler.lotsLength();
        for (uint256 i = 0; i < n; i++) {
            LotterySingleWinner lot = handler.lotsAt(i);

            assertEq(lot.deployer(), address(deployer));
            assertEq(lot.owner(), safeOwner);

            uint256 typeId = registry.typeIdOf(address(lot));
            if (typeId != 0) {
                assertEq(typeId, deployer.SINGLE_WINNER_TYPE_ID());
                assertEq(registry.creatorOf(address(lot)), lot.creator());
                assertTrue(registry.isRegisteredLottery(address(lot)));
            }
        }
    }
}