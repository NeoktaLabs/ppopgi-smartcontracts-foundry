# Ppopgi (뽑기) — Frontend Technical Specification (Etherlink Mainnet)
**Version:** v1.3
**Audience:** Frontend engineers, blockchain integrators  
**Goal:** Ship a smooth, correct, safe dApp UI that maps **1:1** to the deployed contracts on **Etherlink Mainnet**

---

## 0. Non-Negotiables

1. **On-chain truth only**
   - No simulated winners, fake timers, fake “recent activity”, or synthetic social proof.
   - Countdown timers are allowed, but must be derived from on-chain `deadline`.

2. **Never send an obviously reverting tx**
   - Preflight checks must prevent obvious reverts (wrong network, insufficient balances, allowance, not eligible state).
   - **Note:** some reverts are still possible due to **mempool races** (another user finalizes/buys first). Handle gracefully.

3. **Events first, RPC verification always**
   - Use events for live UX.
   - Always verify by reading contract state (websocket/RPC hiccups happen).

4. **Safety over convenience**
   - If any state is unclear, disable writes and prompt user to refresh/retry.

---

## 1. Network & Global Configuration

### 1.1 Target Network
- **Etherlink Mainnet**
- **Chain ID:** `42793`

### 1.2 Network Enforcement
If the user is on the wrong network:
- Disable: Create / Buy / Draw / Collect / Refund / Admin actions
- Show a single CTA: **“Switch to Etherlink”**
- Once switched, re-fetch:
  - chainId
  - account
  - balances
  - registry page

### 1.3 Canonical Addresses
These are constants in UI config:

- **USDC:** `0x796Ea11Fa2dD751eD01b53C372fFDB4AAa8f00F9`
- **Pyth Entropy:** `0x2880aB155794e7179c9eE2e38200202908C17B43`
- **Entropy Provider:** `0x52DeaA1c84233F7bb8C8A45baeDE41091c616506`

> **Note:** The Deployer also stores its own current defaults (`usdc`, `entropy`, `entropyProvider`, `feeRecipient`, `protocolFeePercent`).  
> The UI must display Deployer-configured addresses as the “current default config” for *new* raffles.

### 1.4 Units / Formatting Rules
- **USDC:** 6 decimals
- **XTZ / native:** 18 decimals (EVM native)
- `winningTicketIndex` is **0-based** on-chain; display **+1** in UI.

### 1.5 TOS Gate (Mandatory)
Block Create & Buy actions behind a checkbox:
- Must be explicitly checked at time of action
- Store acceptance in localStorage (per wallet+chain) but re-checkable

---

## 2. Contracts: Addresses & Responsibilities

### 2.1 LotteryRegistry (Forever Registry)
**Purpose**
- Keeps a forever list of registered lotteries.

**Storage / Public Reads**
- `owner() -> address`
- `allLotteries(uint256) -> address`
- `typeIdOf(address) -> uint256`
- `creatorOf(address) -> address`
- `registeredAt(address) -> uint64`
- `isRegistrar(address) -> bool`

**View Functions**
- `isRegisteredLottery(address) -> bool`
- `getAllLotteriesCount() -> uint256`
- `getAllLotteries(start, limit) -> address[]`
- `getLotteriesByTypeCount(typeId) -> uint256`
- `getLotteryByTypeAtIndex(typeId, index) -> address`
- `getLotteriesByType(typeId, start, limit) -> address[]`

**Events**
- `OwnershipTransferred(oldOwner, newOwner)`
- `RegistrarSet(registrar, authorized)`
- `LotteryRegistered(index, typeId, lottery, creator)`

---

### 2.2 SingleWinnerDeployer (Factory)
**Purpose**
- Creates and funds `LotterySingleWinner`, transfers ownership to Safe, registers in registry (best effort).

**Public Reads**
- `owner()`
- `registry() -> LotteryRegistry`
- `safeOwner() -> address`
- `SINGLE_WINNER_TYPE_ID() -> uint256` (const = 1)
- `usdc()`, `entropy()`, `entropyProvider()`, `feeRecipient()`, `protocolFeePercent()`

**Writes**
- `createSingleWinnerLottery(name, ticketPrice, winningPot, minTickets, maxTickets, durationSeconds, minPurchaseAmount) -> lotteryAddr`
- `rescueRegistration(lotteryAddr, creator)` (owner-only)
- `setConfig(usdc, entropy, provider, fee, percent)` (owner-only)
- `transferOwnership(newOwner)` (owner-only)

**Events**
- `LotteryDeployed(...)`
- `RegistrationFailed(lottery, creator)`
- `ConfigUpdated(...)`
- `DeployerOwnershipTransferred(...)`

---

### 2.3 LotterySingleWinner (Per-raffle instance)
**Purpose**
- Ticket sales + Entropy randomness + payouts for one raffle.

**Key Constants (UI must respect)**
- `MAX_BATCH_BUY = 1000`
- `HARD_CAP_TICKETS = 10_000_000`
- `PRIVILEGED_HATCH_DELAY = 1 days`
- `PUBLIC_HATCH_DELAY = 7 days`

**Core Reads**
- `status() -> uint8 enum`:
  - `0 FundingPending`
  - `1 Open`
  - `2 Drawing`
  - `3 Completed`
  - `4 Canceled`
- `name()`, `createdAt()`, `deadline()`
- `ticketPrice()`, `winningPot()`, `ticketRevenue()`
- `minTickets()`, `maxTickets()`, `minPurchaseAmount()`
- `winner()`
- `entropyRequestId()`, `drawingRequestedAt()`, `soldAtDrawing()`
- `soldAtCancel()`, `canceledAt()`
- `entropyProvider()` (current provider)
- `selectedProvider()` (provider used for current draw)
- `activeDrawings()`
- `ticketsOwned(user)`
- `claimableFunds(user)`, `claimableNative(user)`
- `totalReservedUSDC()`, `totalClaimableNative()`
- `creator()`, `feeRecipient()`, `protocolFeePercent()`
- `deployer()`
- `entropy()` (contract address)

**View Functions**
- `getSold() -> uint256`
- `ticketRanges(uint256) -> (buyer, upperBound)`

**Writes**
- `buyTickets(count)`
- `finalize()` payable
- `claimTicketRefund()`
- `withdrawFunds()`
- `withdrawNative()`
- `withdrawNativeTo(to)` (**Supported in v1.6**; allows withdrawing to a different address)
- `cancel()`
- `forceCancelStuck()`
- Owner-only: `sweepSurplus(to)`, `sweepNativeSurplus(to)`, `setEntropyProvider(p)`, `setEntropyContract(e)`, `pause()`, `unpause()`

---

## 3. Pages & Required Features

### 3.1 Explore (Raffles List)
**Goal:** Show all official raffles + indicate active vs closed.

**Data Sources**
1. Registry pagination:
   - `getAllLotteriesCount()`
   - `getAllLotteries(start, limit)`
2. For each address: read raffle contract:
   - `status()`, `deadline()`, `winningPot()`, `ticketPrice()`, `getSold()`, `maxTickets()`, `minTickets()`, `name()`, `deployer()`

#### 3.1.1 Verification & Badges (Updated)
**Do NOT equate “registered” with “official.”**

Define two badges:

1) **Official Verified**
- `LotteryRegistry.typeIdOf(lottery) == SINGLE_WINNER_TYPE_ID`
- AND `LotterySingleWinner(lottery).deployer() == OFFICIAL_DEPLOYER_ADDRESS` (or in an allowlist of official deployers)

2) **Registered**
- `LotteryRegistry.typeIdOf(lottery) > 0`
- BUT deployer is not in the allowlist

**Unlisted**
- Not in registry: do not show on Explore by default
- Allow “open by address” only via advanced entry (manual paste)

**Active definition**
- Active raffles: status `Open` or `Drawing`.

**Pagination**
- Implement pagination / infinite scroll based on registry count.
- Cache pages (memory) to avoid re-fetching on minor UI interactions.

---

### 3.2 Raffle Detail
**Goal:** One page per raffle address.

**Mandatory reads**
- `name`, `status`, `ticketPrice`, `winningPot`, `getSold()`, `deadline`
- `minTickets`, `maxTickets`, `minPurchaseAmount`
- `winner`, `entropyRequestId`, `drawingRequestedAt`, `selectedProvider`
- `ticketsOwned(user)`
- `claimableFunds(user)`, `claimableNative(user)`
- `soldAtCancel()` (if `status == Canceled`)
- `deployer()` (for badge)
- `creator()` (to block creator play)
- `entropy()` and `entropyProvider()` (for fee quoting + display)

**Derived UI values**
- `isExpired = now >= deadline`
- `isSoldOut = maxTickets > 0 && sold >= maxTickets`
- `isFinalizeEligible = status == Open && (isExpired || isSoldOut) && entropyRequestId == 0`

**Progress Bar Logic (Crucial)**
- If `status == Canceled`: display `soldAtCancel` / max
- Else: display `getSold()` / max

**Odds (UX)**
- `ticketsOwned / sold` (if sold > 0)

**Ticket ownership proof visualization (optional)**
- Read `ticketRanges(i)` progressively (never load all by default)

---

### 3.3 Create Raffle
**Write**
- `SingleWinnerDeployer.createSingleWinnerLottery(...)`

**Preflight checks (must)**
- Wallet connected
- Correct chainId
- USDC balance >= `winningPot`
- USDC allowance for **deployer** must be `>= winningPot`
- Validate deployer config:
  - read `protocolFeePercent()` and display
  - require `<= 20`
- Validate duration:
  - `>= 600` seconds
  - `<= 365 days`
- Validate `BatchTooCheap` condition:
  - `minEntry = (minPurchaseAmount == 0) ? 1 : minPurchaseAmount`
  - `requiredMinPrice = ceil(1_000_000 / minEntry)` (USDC base units)
  - require `ticketPrice >= requiredMinPrice`

**Post-success**
- Get `lotteryAddr` from tx logs (`LotteryDeployed`) or return value.
- Deep-link to `/lottery/<addr>`.

**Registry failure handling (mandatory)**
If tx emitted `RegistrationFailed(lottery, creator)`:
- Display a strong warning
- Show/copy the raffle address
- Save to localStorage as “Known raffle” (so user can find it later even if not listed)

---

### 3.4 Prize Counter (Claims Center)
**Goal:** Global place to collect funds/refunds across multiple raffles.

**Indexing strategy**
- Primary: index `PrizeAllocated(user, amount, reason)` events for the connected wallet.
- Also index (recommended for accuracy across devices):
  - `FundsClaimed(user, amount)`
  - `NativeClaimed(user, amount)`
- Secondary fallback: localStorage list of interacted raffles (created, purchased, visited).

**For each raffle in claims list**
- Read `claimableFunds(user)` and `claimableNative(user)` and display both.
- Enable:
  - `withdrawFunds()` if `claimableFunds > 0`
  - `withdrawNative()` if `claimableNative > 0`
  - Optional advanced: `withdrawNativeTo(to)` if user wants to collect Energy to a different address

**Collect All**
- Sequential transactions (one per withdrawal call).
- Display: “X claims = X signatures”
- If one tx fails due to state changes, stop and prompt refresh.

---

### 3.5 Admin (Safe only)
**Visibility**
- Only show admin tools if `connectedAccount == safeOwner` OR matches deployer owner / registry owner as appropriate.
- Otherwise hide (do not just disable).

**Admin actions**
- Factory config: `setConfig(...)`
- Rescue registration: `rescueRegistration(...)`
- Registry registrar management (optional UI): `setRegistrar(...)`
- Surplus sweeping:
  - `sweepSurplus(to)` (USDC)
  - `sweepNativeSurplus(to)` (native/XTZ)

**Admin preflight checks**
- Verify connected account before enabling admin action.
- Validate non-zero addresses.
- For rescue registration, pre-read:
  - `lotteryAddr.code.length > 0`
  - `LotterySingleWinner(lotteryAddr).deployer() == OFFICIAL_DEPLOYER_ADDRESS`
  - `LotterySingleWinner(lotteryAddr).owner() == safeOwner`

---

## 4. Transaction Flows & Preflight Checks

### 4.1 Wallet Connection
- Support EVM wallets (e.g., MetaMask).
- On connect:
  - chainId
  - account
  - balances (USDC + native)
  - preload registry page 0

### 4.2 ERC20 Approvals (USDC)
**Required approvals**
- Create: approve **deployer** for `winningPot`
- Play: approve **raffle** for `ticketPrice * count`

**UX**
- Show current allowance
- Offer approve exact / approve max
- Re-fetch allowance after approval confirmation

### 4.3 Play (Buy Tickets)
**Write:** `LotterySingleWinner.buyTickets(count)`

**Preflight must prevent**
- Wrong chain / not connected
- `status != Open`
- `now >= deadline`
- `count == 0`
- `count > 1000`
- `minPurchaseAmount > 0 && count < minPurchaseAmount`
- `maxTickets > 0 && sold + count > maxTickets`
- `sold + count > HARD_CAP_TICKETS`
- `msg.sender == creator` (block in UI)

**Cost**
- `totalCost = ticketPrice * count`

**Balance/Allowance**
- USDC balance >= totalCost
- Allowance to raffle >= totalCost

**After tx**
- Listen for `TicketsPurchased`
- Re-read:
  - `getSold()`
  - `ticketsOwned(user)`
  - `ticketRevenue()`

### 4.4 Draw (Finalize)
**Write:** `LotterySingleWinner.finalize()` payable

**Eligibility**
- `status == Open`
- `entropyRequestId == 0`
- AND (`isExpired` OR `isSoldOut`)

**Fee quoting (Updated)**
- Fee must be read from the lottery’s configured entropy & provider:
  - `fee = Entropy(lottery.entropy()).getFee(lottery.entropyProvider())`
- Display fee explicitly.

**Preflight**
- Ensure user native balance >= fee + gas buffer

**Send tx**
- Recommended: `value = fee` (exact)
- If UI uses `value > fee`, contract refunds excess; refunds may become `claimableNative` if immediate refund fails.

**After tx**
- Listen for `LotteryFinalized`
- Show Drawing state; poll:
  - `status()` until Completed or Canceled
  - `winner()` once Completed

### 4.5 Refund flow (Canceled)
Two-step:
1. `claimTicketRefund()` allocates USDC to `claimableFunds`
2. `withdrawFunds()` transfers USDC out

**Eligibility**
- status == `Canceled`
- `ticketsOwned(user) > 0` for `claimTicketRefund`
- `claimableFunds(user) > 0` for `withdrawFunds`

**Creator note (Updated)**
- Creator pot refund is **allocated automatically on cancel**.
- Creator only needs `withdrawFunds()` to collect it.

### 4.6 Collect (Withdrawals)
- `withdrawFunds()` for USDC
- `withdrawNative()` for native (XTZ)
- Optional advanced: `withdrawNativeTo(to)`

After withdrawal:
- Re-read claimables
- Update claims totals

---

## 5. Events & Indexing (Hybrid Strategy)

### 5.1 Must-index Events
**Factory**
- `LotteryDeployed(...)`
- `RegistrationFailed(lottery, creator)`
- `ConfigUpdated(...)` (for showing current defaults)

**Raffle**
- `TicketsPurchased(...)`
- `LotteryFinalized(...)`
- `WinnerPicked(...)`
- `LotteryCanceled(...)`
- `PrizeAllocated(user, amount, reason)`
- Recommended for multi-device accuracy:
  - `FundsClaimed(user, amount)`
  - `NativeClaimed(user, amount)`

### 5.2 RPC fallback
If events are missing:
- Always verify canonical state:
  - `status()`
  - `winner()`
  - `claimableFunds(user)`
  - `claimableNative(user)`
  - `getSold()`

### 5.3 localStorage fallback
Maintain a set keyed by `chainId + walletAddress`:
- raffles created
- raffles played
- raffles visited (optional)

---

## 6. Status → UI State Contract

- FundingPending (0)
  - disable play/draw
  - show “setting up”
- Open (1)
  - allow play
  - allow draw only if eligible
- Drawing (2)
  - disable play/draw
  - show “waiting for draw result” + poll
- Completed (3)
  - show winner
  - show collect buttons if claimable
- Canceled (4)
  - show refund flow (claimTicketRefund then withdrawFunds)
  - **Freeze sold count:** display `soldAtCancel`

---

## 7. Admin & Operational Considerations

### 7.1 Safe as Owner
- Owner-only methods require Safe execution.

### 7.2 Governance locks
- `setEntropyProvider` and `setEntropyContract` revert if `activeDrawings != 0`.
- UI must read `activeDrawings()` and disable those actions while > 0.

### 7.3 Emergency hatch
- `forceCancelStuck()` only works when `status == Drawing`.
- Delay rules:
  - privileged (owner or creator): after `drawingRequestedAt + 1 day`
  - public: after `drawingRequestedAt + 7 days`
- UI must display time remaining and disable until eligible.

---

## 8. Performance Requirements
- Avoid N+1 calls; use multicall batching for list rendering.
- Paginate and lazy load for large registries.
- Do not load all `ticketRanges` by default.

---

## 9. Security & UX Safety Requirements
- Always show exact token amounts and decimals.
- Never auto-send transactions; explicit click required.
- Handle race-condition failures gracefully: explain “Someone acted first—refresh and try again.”
- **Transparency without technical clutter:** show addresses/explorer links inside a “Details” modal, not in the main UI.

---

## 10. Error Handling (Contract-Derived)
Map custom errors to friendly copy in `frontend-ux-product-spec.md`.

**Important**
- Treat “Pausable: paused” and Ownable reverts as standard permission/paused UX states.
- For unexpected errors, show a “Refresh & retry” prompt and link to Details.

---

## 11. QA Checklist (Minimum for Release)

### Network
- [ ] Wrong network blocks all writes and offers switch CTA
- [ ] Correct network enables writes after refresh

### Create
- [ ] Approve flow works (exact + max)
- [ ] Deployment emits `LotteryDeployed` and deep-links
- [ ] If `RegistrationFailed`, address shown + stored
- [ ] Verification badge correctly checks deployer allowlist

### Play
- [ ] Preflight prevents known revert cases
- [ ] TicketsPurchased updates sold + owned
- [ ] Odds display updates correctly

### Draw
- [ ] Fee read uses `Entropy(lottery.entropy()).getFee(lottery.entropyProvider())`
- [ ] tx sends correct `value`
- [ ] UI transitions to Drawing, then to Completed via polling+events
- [ ] Handles race-condition failures with refresh prompt

### Claims
- [ ] PrizeAllocated indexing builds claims list
- [ ] FundsClaimed/NativeClaimed indexing improves accuracy across devices
- [ ] withdrawFunds reduces claimableFunds
- [ ] withdrawNative works, and handles fallback path (claimableNative)

### Canceled refunds
- [ ] claimTicketRefund sets claimableFunds
- [ ] withdrawFunds transfers refund
- [ ] UI shows frozen snapshot stats (soldAtCancel)
- [ ] Creator pot refund is shown as collectible without extra steps

### Admin
- [ ] Only visible to authorized account
- [ ] rescueRegistration guarded and validates target
- [ ] Surplus sweeps (Native + USDC) work

---

## 12. Implementation Notes (Recommended)
- Use a robust EVM library (viem / wagmi) with:
  - chain enforcement
  - typed ABIs
  - event watching + fallback polling
- Use multicall for list rendering.
- On each confirmed tx, refresh only relevant reads (not full app reload).

---

---

# Ppopgi (뽑기) — Frontend UX & Product Specification
**Version:** Final UX Gold (v1.1 + alignment patch)  
**Audience:** UI/UX designers, frontend developers  
**Network:** Etherlink (Tezos L2)  
**Tone:** Friendly, safe, playful, non-technical  
**Core Rule:** *Never make users feel like they are gambling or dealing with blockchain*

---

## 1. Product Vision
(unchanged)

---

## 2. Global Design Rules (Non-Negotiable)
(unchanged)

---

## 3. Sticky Language (Never Use Technical Terms)
(unchanged)

---

## 4. Global Top Bar (All Pages)
(unchanged)

---

## 5. Coin Cashier (Critical UX Element) — Updated

### Purpose
Explain **why two coins are needed**, without mentioning blockchain.

### Cashier Modal Content
Friendly explanation:

> **Welcome to the Coin Cashier 🏪**  
> 🎟 **Entry Coins** let you play raffles  
> ⚡ **Energy Coins** help the park run smoothly  
>
> **Sometimes Energy refunds arrive as a Collectible instead of instantly.**  
> If that happens, you can always **Collect** it from your Pocket.

### Actions
- “Get Entry Coins (USDC)”
- “Get Energy Coins (XTZ)”
- External redirect (e.g. Transak)
- No forced action

---

## 6. Mandatory Disclaimer (First Visit Only)
(unchanged)

---

## 7. Live Activity Banner (Global, Always Visible) — Clarification

### Content Rules
- Real events only for “wins”, “new raffle”, “ended without enough entries”
- Timestamp on every line
- Max 3 visible at once

### Session Welcome Message
- Welcome message is UI-only and not on-chain (allowed)
- Once per session via `sessionStorage`

---

## 8–17
All remaining UX sections unchanged, with one important addition:

## 18. Transparency Without Technical Clutter (New)

### Rule
We must be transparent without showing “blockchain-looking” data on the main UI.

### Pattern
- Add a small **“Details”** link (🔎) on:
  - Raffle cards (optional)
  - Raffle detail page (required)
  - Create confirmation screen (required)

### Details Modal Contents (plain language)
- “Game ID” (raffle address)
- “Rulebook” (verified contract page / explorer)
- “Entry Coin” (USDC address)
- “Draw Provider” (Entropy contract + provider)
- “Factory” (deployer address)
- “Official Verified” badge explanation (why this raffle is official)

This satisfies transparency while keeping the main UI friendly.

---