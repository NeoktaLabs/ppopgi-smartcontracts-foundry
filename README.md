# Ppopgi (뽑기) — Smart Contract Testing & Verification

This repository includes a comprehensive **Foundry-based test suite** covering the core smart contracts powering **Ppopgi**, a fully on-chain raffle platform built on Etherlink (Tezos L2).

The purpose of this test suite is to validate correctness, safety assumptions, and edge-case behavior of the contracts under realistic and adversarial conditions.

**All tests are deterministic, reproducible, and publicly reviewable.**

---

## 📦 What’s Inside

The test suite validates all core components of the system:
* **`LotteryRegistry`** — registry integrity, pagination, and authorization
* **`SingleWinnerDeployer`** — factory deployment flow and ownership transfer
* **`LotterySingleWinner`** — ticket sales, finalization, randomness, refunds, and withdrawals
* **External integrations** — mocked randomness (Entropy) and ERC20 behavior

---

## 🛡️ Key Properties Verified by Tests

* ✅ Deterministic and verifiable lottery lifecycle
* ✅ Correct accounting of USDC and native ETH
* ✅ Pull-based payouts for all participants
* ✅ Safe cancellation and refund paths
* ✅ Protection against malicious or non-standard receivers
* ✅ Strict authorization for registry and admin actions
* ✅ Safe handling of external randomness callbacks

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
| **Total tests** | 17 |
| **Passed** | 17 |
| **Failed** | 0 |

**Latest successful run (abridged):**

```text
Ran 5 test suites
17 tests passed, 0 failed, 0 skipped
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
└── mocks/
    ├── MockEntropy.sol
    ├── MockUSDC.sol
    └── RevertingReceiver.sol
```

---

## 📝 Test Coverage by File

### `Base.t.sol` — Shared Test Setup

**Purpose:** Establishes a clean and reproducible environment for every test suite.

**Responsibilities:**
* Deploys core contracts
* Sets up mock dependencies
* Defines test actors (creator, buyer, admin, provider)
* Provides shared helper functions
* Ensures full isolation between tests

### `DeployerAndRegistry.t.sol` — Factory & Registry Tests

**Contracts tested:** `SingleWinnerDeployer`, `LotteryRegistry`

* **Behavior:**
    * Only authorized registrars can register lotteries
    * Factory deploys valid lottery instances
    * Ownership is transferred to the designated `safeOwner`
    * Registry pagination behaves correctly, including empty results
* **Why this matters:** Prevents unauthorized deployments and ensures registry integrity.

### `LotteryBuy.t.sol` — Ticket Purchase Logic

**Contract tested:** `LotterySingleWinner`

* **Behavior:**
    * Correct accounting for ticket purchases
    * Multiple purchases by the same buyer
    * Creator self-participation is prevented
    * Reverts when buying after the deadline
    * ERC20 transfers are verified using balance deltas
* **Why this matters:** Prevents self-dealing and protects against malicious tokens.

### `LotteryCancelRefund.t.sol` — Cancellation & Refunds

**Contract tested:** `LotterySingleWinner`

* **Behavior:**
    * Cancellation after deadline when minimum tickets are not reached
    * Automatic refunds to ticket buyers
    * Safe handling of native ETH refunds when finalization fails
* **Why this matters:** Users are never stuck in a failed lottery.

### `LotteryFinalizeResolve.t.sol` — Finalization & Randomness

**Contract tested:** `LotterySingleWinner`

* **Behavior:**
    * Finalization reverts if the lottery is not eligible
    * Only authorized entropy callbacks are accepted
    * Incorrect sequence numbers are rejected
    * Full `finalize` → `resolve` → `winner allocation` flow
* **Why this matters:** Prevents spoofed randomness and ensures fair winner selection.

### `LotteryWithdrawSweepPause.t.sol` — Withdrawals, Surplus & Pausing

**Contract tested:** `LotterySingleWinner`

* **Behavior:**
    * Withdrawals correctly reduce reserved balances
    * Pausing blocks ticket purchases and finalization
    * USDC surplus can only be swept when a real surplus exists
    * Only the owner can sweep surplus funds
    * Native ETH refunds remain safe even for reverting receivers
* **Why this matters:** Protects funds from leakage and prevents denial-of-service.

---

## ⚡ Special Case: Native ETH Refund Safety

Some contracts revert when receiving ETH. To prevent denial-of-service scenarios:

1.  Failed ETH transfers are credited internally as `claimableNative`
2.  Users can later withdraw ETH to a safe address

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
* Unauthorized actions revert correctly

**What These Tests Do NOT Guarantee:**
* Absolute security
* Protection against all economic attacks
* Safety against compromised admin keys
* Production behavior of external integrations

For higher assurance, **Fuzz testing**, **Invariant testing**, and **Independent security audits** are recommended.

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
