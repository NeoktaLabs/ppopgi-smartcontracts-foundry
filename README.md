# Ppopgi (뽑기) — Smart Contracts

This repository contains the core smart contracts powering **Ppopgi**, a fully on-chain raffle platform built on **Etherlink (Tezos L2)**.

Each raffle is deployed as its own contract instance, ensuring isolation, transparency, and deterministic behavior. There is no custodial backend and no off-chain manipulation of outcomes.

## What’s inside
- **LotteryRegistry** — a minimal, permanent registry of all official raffles
- **SingleWinnerDeployer** — a factory contract used to deploy new raffles
- **LotterySingleWinner** — one raffle = one contract instance

## Key Properties
- Verifiable randomness via **Pyth Entropy**
- Pull-based payouts (users withdraw their own funds)
- Permissionless finalization (anyone can trigger eligible draws)
- Refund and cancellation mechanisms with on-chain snapshots
- Strict accounting to prevent fund leakage

## Technology
- Solidity (EVM compatible)
- Etherlink Mainnet (Chain ID 42793)
- USDC (6 decimals)
- Pyth Entropy for randomness

## Important Notice
These contracts were designed, implemented, and reviewed with the help of **AI agents**.  
They are extensively tested and documented but remain **experimental** and **unaudited**.

Use at your own risk and only with funds you are comfortable with
