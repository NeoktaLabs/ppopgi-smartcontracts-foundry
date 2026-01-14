# Ppopgi (뽑기) — Smart Contract Testing & Verification

This repository includes a comprehensive **Foundry-based test suite** covering the core smart contracts powering **Ppopgi**, a fully on-chain raffle platform built on Etherlink (Tezos L2).

The purpose of this test suite is to validate correctness, safety assumptions, and edge-case behavior of the contracts under realistic and adversarial conditions.

**All tests are deterministic, reproducible, and publicly reviewable.**

---

## 📦 What’s Inside

The test suite validates all core components of the system:
* **`LotteryRegistry`** — registry integrity, pagination, and authorization.
* **`SingleWinnerDeployer`** — factory deployment flow, funding, and ownership transfer.
* **`LotterySingleWinner`** — ticket sales, finalization, randomness, refunds, withdrawals, and admin controls.
* **External integrations** — mocked randomness (Entropy), ERC20 behavior, and hostile receivers.

---

## 🛡️ Key Properties Verified by Tests

* ✅ Deterministic and verifiable lottery lifecycle
* ✅ Correct accounting of USDC and native ETH
* ✅ Pull-based payouts for all participants
* ✅ Safe cancellation and emergency recovery paths
* ✅ Protection against malicious or non-standard receivers
* ✅ Strict authorization for registry and governance actions
* ✅ Safe handling of external randomness callbacks
* ✅ Admin powers cannot steal or misroute user funds
* ✅ Boundary conditions (deadlines, caps, off-by-one cases)
* ✅ Winner selection correctness at range boundaries (first ticket, last ticket, and edge cases)
* ✅ Anti-spam economic constraints enforced at deployment time
* ✅ Full liability exhaustion after withdrawals (`totalReservedUSDC == 0`)
* ✅ Safety against randomness callback replay

## 🔁 Invariant Testing (Stateful Fuzzing)

In addition to traditional unit and integration tests, this repository includes **stateful invariant tests** implemented using Foundry’s `StdInvariant` framework.

Invariant testing verifies that **critical safety properties always hold**, regardless of the order, frequency, or combination of valid contract interactions.  
Instead of asserting outcomes of specific scenarios, invariants assert **global truths** that must never be violated.

---

### 🎯 Why Invariant Testing Matters

Lottery-style contracts have:
- Complex state machines
- Multiple actors with different privileges
- Asynchronous randomness callbacks
- Long-lived accounting obligations

These characteristics make them especially vulnerable to **unexpected interaction sequences** that are difficult to reason about manually.

Invariant testing explores *thousands of randomized call sequences* and ensures that **fund safety and registry correctness are preserved at all times**.

---

### 🧪 Invariants Implemented

The invariant test suite (`LotteryInvariant_DeployerRegistry.t.sol`) continuously fuzzes interactions across:

- `SingleWinnerDeployer`
- `LotteryRegistry`
- Multiple `LotterySingleWinner` instances

The following invariants are enforced:

#### 🔐 Financial Solvency Invariants

These guarantees must **always** hold, regardless of user behavior, admin actions, or randomness timing:

- `USDC.balanceOf(lottery) >= totalReservedUSDC`  
  Ensures the contract can always cover all outstanding USDC liabilities.
- `address(lottery).balance >= totalClaimableNative`  
  Ensures all claimable native ETH is fully backed.
- All withdrawals reduce liabilities correctly.
- Sweep functions can never steal user or protocol funds.

#### 🧭 Lifecycle & State Machine Invariants

- `activeDrawings ∈ {0, 1}` at all times.
- A lottery in `Drawing` state must:
  - Have a valid entropy request ID
  - Have a recorded draw timestamp
  - Have non-zero sold tickets
- A lottery in `Open` state must not have an active entropy request.

These checks ensure **no invalid or partially-initialized states** can persist.

#### 🗂️ Registry & Deployer Consistency Invariants

- Every deployed lottery:
  - Has `deployer == SingleWinnerDeployer`
  - Has `owner == safeOwner`
- If a lottery is registered:
  - Its `typeId` is correct and immutable
  - The registry’s recorded creator matches the lottery’s creator
  - `isRegisteredLottery(lottery)` remains true forever

This proves that the registry behaves as an **append-only, non-corruptible source of truth**, even if registration failures occur during deployment.

---

### 🔄 Fuzzed Actions

During invariant testing, the system is subjected to randomized sequences of valid actions, including:

- Deploying new lotteries
- Buying tickets
- Finalizing lotteries
- Fulfilling randomness callbacks
- Canceling and force-canceling lotteries
- Claiming refunds
- Withdrawing USDC and native ETH
- Sweeping surplus funds
- Updating deployer configuration
- Arbitrary time warping

All actions are executed by randomized actors under realistic constraints.

---

### 📈 Coverage & Confidence

- Each invariant is executed across **hundreds of randomized runs**
- Each run performs **tens of thousands of contract calls**
- No reverts, discards, or invariant violations were observed in the current configuration

This provides strong evidence that:
- Accounting remains correct under adversarial sequencing
- Governance actions cannot break safety guarantees
- Registry integrity is preserved across the system’s lifetime

> Invariant testing does not prove the absence of all bugs,  
> but it significantly raises confidence that **entire classes of bugs cannot exist**.

---

### 🧠 Relationship to Other Tests

Invariant tests **complement**, not replace, unit and integration tests:

- Unit tests verify *specific expected behaviors*
- Invariants verify *global safety properties*
- Together, they provide defense-in-depth against both logic bugs and emergent behavior

---

## 🛠️ Technology & Tooling

* **Framework:** Foundry (`forge`)
* **Solidity:** `^0.8.24`
* **CI:** GitHub Actions
* **Dependencies:**
    * OpenZeppelin Contracts v5.0.1
    * forge-std

**All tests are executed automatically on:**
* Every push
* Every pull request
* Manual workflow triggers

CI workflow file: `.github/workflows/tests.yml`

---

## 📊 Test Results (Current State)

| Metric | Status |
| :--- | :--- |
| **CI status** | 🟢 Green |
| **Total tests** | 30+ |
| **Passed** | 100% |
| **Failed** | 0 |

**Latest successful run (abridged):**

```text
Ran multiple test suites
All tests passed, 0 failed, 0 skipped
```

**This confirms:**
* Contracts compile cleanly
* All tested behaviors behave as expected
* No regressions were introduced

> **Note:** Passing tests do not imply absolute security. They guarantee correctness only for the scenarios covered by the test suite.

---

## 📂 Test Structure Overview

```text
test/
├── Base.t.sol
├── DeployerAndRegistry.t.sol
├── LotteryBuy.t.sol
├── LotteryCancelRefund.t.sol
├── LotteryFinalizeResolve.t.sol
├── LotteryWithdrawSweepPause.t.sol
├── LotteryGovernanceSweep.t.sol
├── LotteryCreation.t.sol
├── LotteryPolish.t.sol
├── LotteryInvariant_DeployerRegistry.sol
├── LotteryAdditionalCoverage.t.sol
└── mocks/
    ├── MockEntropy.sol
    ├── MockUSDC.sol
    └── RevertingReceiver.sol
```

---

## 📝 Test Coverage by File

### `Base.t.sol` — Shared Test Setup
**Purpose:** Establishes a clean and reproducible environment for every test suite.
* Deploys core contracts
* Sets up mock dependencies
* Defines deterministic test actors (creator, buyers, admin, provider)
* Provides shared helper functions
* Ensures full isolation between tests

### `DeployerAndRegistry.t.sol` — Factory & Registry Tests
**Contracts tested:** `SingleWinnerDeployer`, `LotteryRegistry`
* **Behavior:**
    * Only authorized registrars can register lotteries
    * Factory deploys valid lottery instances
    * Funding and `confirmFunding()` are executed correctly
    * Ownership is transferred to the designated `safeOwner`
    * Registry pagination behaves correctly, including empty results
* **Why this matters:** Prevents unauthorized deployments and ensures registry integrity.

### `LotteryCreation.t.sol` — Lottery Initialization
**Contract tested:** `LotterySingleWinner` (via deployer)
* **Behavior:**
    * Initial state is correct immediately after deployment
    * Creator, owner, and configuration parameters are set correctly
    * Funding is fully accounted for
    * No tickets sold and no drawings active at creation
* **Why this matters:** Proves constructor and deployment correctness.

### `LotteryBuy.t.sol` — Ticket Purchase Logic
**Contract tested:** `LotterySingleWinner`
* **Behavior:**
    * Correct accounting for ticket purchases
    * Multiple purchases by the same buyer (range merging)
    * Creator self-participation is prevented
    * Buying after the deadline reverts
    * Buying beyond `maxTickets` reverts
    * ERC20 transfers are verified using balance deltas
* **Why this matters:** Prevents self-dealing, overselling, and token-based exploits.

### `LotteryCancelRefund.t.sol` — Cancellation & Refunds
**Contract tested:** `LotterySingleWinner`
* **Behavior:**
    * Cancellation after deadline when minimum tickets are not reached
    * Emergency cancellation when randomness is stuck
    * Automatic refunds to ticket buyers
    * Creator pot refund behavior
    * Safe handling of native ETH refunds
* **Why this matters:** Users are never stuck in a failed or stalled lottery.

### `LotteryFinalizeResolve.t.sol` — Finalization & Randomness
**Contract tested:** `LotterySingleWinner`
* **Behavior:**
    * Finalization eligibility checks
    * Finalize succeeds when `maxTickets` is reached (before deadline)
    * Insufficient entropy fee reverts
    * Extra native ETH is refunded
    * Double-finalize protection
    * Only authorized entropy callbacks are accepted
    * Incorrect providers or sequence numbers are rejected
    * Winner selection across multiple ticket ranges
    * `activeDrawings` governance lock behavior
* **Why this matters:** Ensures fair randomness and correct draw resolution.

### `LotteryWithdrawSweepPause.t.sol` — Withdrawals, Surplus & Pausing
**Contract tested:** `LotterySingleWinner`
* **Behavior:**
    * Withdrawals correctly reduce reserved balances
    * Claimable funds cannot be double-withdrawn
    * Pausing blocks ticket purchases and finalization
    * USDC surplus can only be swept when a real surplus exists
    * Only the owner can sweep surplus funds
* **Why this matters:** Prevents fund leakage and misuse of admin privileges.

### `LotteryGovernanceSweep.t.sol` — Governance Locks & Fund Safety
**Contract tested:** `LotterySingleWinner`
* **Behavior:**
    * Admin cannot change entropy provider or contract while drawing
    * Governance actions are unlocked after resolution or cancellation
    * USDC sweep cannot steal user or protocol liabilities
    * Native ETH sweep respects `totalClaimableNative`
    * Accidental transfers can be recovered safely
* **Why this matters:** Proves admin powers are constrained and non-custodial.

### `LotteryPolish.t.sol` — Boundary & End-to-End Tests
**Contract tested:** `LotterySingleWinner`, `LotteryRegistry`
* **Behavior:**
    * Buying at `deadline - 1` succeeds, buying at `deadline` reverts
    * Finalizing exactly at the deadline succeeds
    * `maxTickets` boundary enforcement (`== max` vs `> max`)
    * End-to-end withdrawals for winner, creator, and protocol
    * `totalReservedUSDC` accounting after full withdrawals
    * Registry metadata correctness after creation
* **Why this matters:** Catches subtle off-by-one and lifecycle bugs.

### `LotteryAdditionalCoverage.t.sol` — Advanced Edge-Case & Accounting Tests
**Contracts tested:** `LotterySingleWinner`, `SingleWinnerDeployer`, `MockEntropy`
* **Behavior:**
    * Winner selection at all critical ticket boundaries:
        * First ticket
        * Last ticket
        * Edges between ticket ranges
    * Deployment-time rejection of economically unsafe configurations (BatchTooCheap)
    * End-to-end withdrawals for winner, creator, and protocol
    * Verification that all liabilities are exhausted (`totalReservedUSDC == 0`)
    * Protection against randomness callback replay
* **Why this matters:** These tests cover the most subtle and failure-prone areas of raffle-style contracts: off-by-one errors, accounting drift, misconfigured deployments, and unexpected external callbacks.

---

## ⚡ Special Case: Native ETH Refund Safety

Some contracts revert when receiving ETH. To prevent denial-of-service scenarios:
1. Failed ETH transfers are credited internally as `claimableNative`.
2. Users can later withdraw ETH to a safe address.

This behavior is explicitly tested using a `RevertingReceiver` mock to ensure **no ETH is lost** and **no transaction is bricked**.

---

## 🎲 Mocking Randomness (Entropy)

The real Pyth Entropy contract lives on a different network and uses asynchronous callbacks. For deterministic testing, a mock implementation is used.

**`MockEntropy.sol` Behavior:**
* Implements the `IEntropy` interface
* Tracks randomness requests internally
* Enforces provider fee payment
* Allows manual fulfillment of randomness

**Randomness flow in tests:**
1.  Lottery requests randomness via `requestWithCallback`
2.  Mock stores the request ID
3.  Test calls `fulfill(requestId, randomValue)`
4.  Lottery receives the callback and resolves the draw

---

## ⚠️ Guarantees & Limitations

**What These Tests Guarantee:**
* Contract logic behaves as intended
* Critical edge cases are covered
* Funds are safely accounted for
* Refunds work even for hostile receivers
* Admin actions are constrained and auditable

**What These Tests Do NOT Guarantee:**
* Absolute security
* Protection against all economic attacks
* Safety against compromised admin keys
* Production behavior of external integrations

For higher assurance, **Invariant testing**, **Fuzz testing**, and **Independent security audits** are recommended.

---

## 🚀 Running the Tests

Run the full test suite:

```bash
forge test -vv
```

Re-run only failed tests:

```bash
forge test --rerun
```

---

> **Important Notice**
>
> These tests — like the contracts themselves — were designed, implemented, and reviewed with the help of AI agents.
>
> They are extensive and transparent, but the system remains experimental and unaudited.
>
> **Use at your own risk and only with funds you are comfortable with.**
