# Molten

**Molten** is a Uniswap v1–style Automated Market Maker (AMM) decentralized exchange for the Stacks blockchain, implementing the constant product formula `x * y = k`.

It allows trustless swapping between STX and a SIP-010 fungible token, with liquidity provided by users in exchange for LP tokens.

---

## Features

- **Constant Product Market Maker** — Pricing based on the `x * y = k` invariant.
- **Liquidity Provision** — Add or remove liquidity for STX and a SIP-010 token.
- **Trustless Swaps** — Swap STX ↔ Token directly on-chain with no intermediaries.
- **LP Tokens** — Represent ownership share of the pool’s reserves.
- **Swap Event Logging** — On-chain records of swaps with block height.
- **0.3% Trading Fee** — Fees stay in the pool for liquidity providers.

---

## Contract Overview

### Public Functions

- `initialize(token-trait, stx-amount, token-amount)`  
  Creates the pool with initial liquidity.

- `add-liquidity(token-trait, stx-amount, token-amount, min-liquidity)`  
  Adds liquidity to the pool, mints LP tokens.

- `remove-liquidity(token-trait, liquidity, min-stx, min-tokens)`  
  Burns LP tokens, returns proportional reserves.

- `swap-stx-for-tokens(token-trait, stx-amount, min-tokens)`  
  Swaps STX for tokens.

- `swap-tokens-for-stx(token-trait, token-amount, min-stx)`  
  Swaps tokens for STX.

---

### Read-Only Functions

- `get-reserves()` — Returns current STX and token reserves.
- `get-lp-balance(user)` — Returns LP token balance for a user.
- `get-total-supply()` — Returns total LP tokens in circulation.
- `is-initialized()` — Checks if pool has been initialized.
- `get-token-contract()` — Returns the pool’s token contract.
- `get-amount-out(amount-in, reserve-in, reserve-out)` — Swap quote (output amount).
- `get-amount-in(amount-out, reserve-in, reserve-out)` — Swap quote (input amount).
- `quote(amount-a, reserve-a, reserve-b)` — Proportional token quote for liquidity addition.

---

## Fees

- **0.3% per swap**  
  Implemented by multiplying the input amount by `997` instead of `1000` in the formula.

---

## Deployment

1. Deploy your SIP-010 compliant fungible token contract.
2. Deploy `Molten` contract.
3. Call `initialize()` with desired STX and token amounts.

---

## Example Flow

```text
Alice initializes pool:
- 10,000 STX
- 5,000 TOKEN

Bob adds liquidity:
- 2,000 STX
- 1,000 TOKEN
- Receives LP tokens

Charlie swaps:
- 500 STX → ~247 TOKEN (after fee & slippage)

Bob removes liquidity:
- Burns LP tokens
- Gets proportional STX & TOKEN back
