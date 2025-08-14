;; Uniswap v1-style AMM DEX for Stacks
;; Implements constant product market maker (x * y = k)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-liquidity (err u101))
(define-constant err-insufficient-amount (err u102))
(define-constant err-slippage-tolerance (err u103))
(define-constant err-invalid-token (err u104))
(define-constant err-transfer-failed (err u105))
(define-constant err-already-initialized (err u106))
(define-constant err-not-initialized (err u107))

;; Data Variables
(define-data-var stx-reserve uint u0)
(define-data-var token-reserve uint u0)
(define-data-var total-supply uint u0)
(define-data-var initialized bool false)

;; Token contract reference (SIP-010)
(define-data-var token-contract principal .token)

;; LP token balances
(define-map lp-balances principal uint)

;; Events
(define-map swap-events 
  { tx-id: uint }
  { 
    user: principal,
    stx-in: uint,
    token-out: uint,
    stx-out: uint,
    token-in: uint,
    block-height: uint
  }
)

(define-data-var event-nonce uint u0)

;; SIP-010 trait definition
(define-trait sip-010-token
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-name () (response (string-ascii 32) uint))
    (get-symbol () (response (string-ascii 32) uint))
    (get-decimals () (response uint uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Helper Functions

;; Get minimum of two numbers
(define-private (min (a uint) (b uint))
  (if (< a b) a b))

;; Read-only functions

(define-read-only (get-reserves)
  {
    stx-reserve: (var-get stx-reserve),
    token-reserve: (var-get token-reserve)
  }
)

(define-read-only (get-lp-balance (user principal))
  (default-to u0 (map-get? lp-balances user))
)

(define-read-only (get-total-supply)
  (var-get total-supply)
)

(define-read-only (is-initialized)
  (var-get initialized)
)

(define-read-only (get-token-contract)
  (var-get token-contract)
)

;; Calculate output amount for swap (with 0.3% fee)
(define-read-only (get-amount-out (amount-in uint) (reserve-in uint) (reserve-out uint))
  (if (or (is-eq amount-in u0) (is-eq reserve-in u0) (is-eq reserve-out u0))
    u0
    (let (
      (amount-in-with-fee (* amount-in u997))
      (numerator (* amount-in-with-fee reserve-out))
      (denominator (+ (* reserve-in u1000) amount-in-with-fee))
    )
    (/ numerator denominator)))
)

;; Calculate input amount needed for desired output
(define-read-only (get-amount-in (amount-out uint) (reserve-in uint) (reserve-out uint))
  (if (or (is-eq amount-out u0) (is-eq reserve-in u0) (is-eq reserve-out u0))
    u0
    (let (
      (numerator (* (* reserve-in amount-out) u1000))
      (denominator (* (- reserve-out amount-out) u997))
    )
    (+ (/ numerator denominator) u1)))
)

;; Quote function for adding liquidity
(define-read-only (quote (amount-a uint) (reserve-a uint) (reserve-b uint))
  (if (is-eq reserve-a u0)
    u0
    (/ (* amount-a reserve-b) reserve-a))
)

;; Public functions

;; Initialize the pool with initial liquidity
(define-public (initialize (token-trait <sip-010-token>) (stx-amount uint) (token-amount uint))
  (let (
    ;; Use minimum of the two amounts as initial liquidity (simpler approach)
    (liquidity (min stx-amount token-amount))
  )
    (asserts! (not (var-get initialized)) err-already-initialized)
    (asserts! (> stx-amount u0) err-insufficient-amount)
    (asserts! (> token-amount u0) err-insufficient-amount)
    (asserts! (> liquidity u0) err-insufficient-liquidity)
    
    ;; Set the token contract
    (var-set token-contract (contract-of token-trait))
    
    ;; Transfer tokens from user
    (try! (contract-call? token-trait transfer token-amount tx-sender (as-contract tx-sender) none))
    
    ;; Update reserves
    (var-set stx-reserve stx-amount)
    (var-set token-reserve token-amount)
    (var-set total-supply liquidity)
    (var-set initialized true)
    
    ;; Mint LP tokens to user
    (map-set lp-balances tx-sender liquidity)
    
    (ok liquidity)
  )
)

;; Add liquidity to the pool
(define-public (add-liquidity (token-trait <sip-010-token>) (stx-amount uint) (token-amount uint) (min-liquidity uint))
  (let (
    (current-stx-reserve (var-get stx-reserve))
    (current-token-reserve (var-get token-reserve))
    (current-total-supply (var-get total-supply))
    (liquidity (min 
                 (/ (* stx-amount current-total-supply) current-stx-reserve)
                 (/ (* token-amount current-total-supply) current-token-reserve)))
    (current-lp-balance (get-lp-balance tx-sender))
  )
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq (contract-of token-trait) (var-get token-contract)) err-invalid-token)
    (asserts! (> stx-amount u0) err-insufficient-amount)
    (asserts! (> token-amount u0) err-insufficient-amount)
    (asserts! (>= liquidity min-liquidity) err-slippage-tolerance)
    
    ;; Transfer tokens from user
    (try! (contract-call? token-trait transfer token-amount tx-sender (as-contract tx-sender) none))
    
    ;; Update reserves
    (var-set stx-reserve (+ current-stx-reserve stx-amount))
    (var-set token-reserve (+ current-token-reserve token-amount))
    (var-set total-supply (+ current-total-supply liquidity))
    
    ;; Update LP balance
    (map-set lp-balances tx-sender (+ current-lp-balance liquidity))
    
    (ok liquidity)
  )
)

;; Remove liquidity from the pool
(define-public (remove-liquidity (token-trait <sip-010-token>) (liquidity uint) (min-stx uint) (min-tokens uint))
  (let (
    (current-stx-reserve (var-get stx-reserve))
    (current-token-reserve (var-get token-reserve))
    (current-total-supply (var-get total-supply))
    (current-lp-balance (get-lp-balance tx-sender))
    (stx-amount (/ (* liquidity current-stx-reserve) current-total-supply))
    (token-amount (/ (* liquidity current-token-reserve) current-total-supply))
  )
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq (contract-of token-trait) (var-get token-contract)) err-invalid-token)
    (asserts! (> liquidity u0) err-insufficient-amount)
    (asserts! (>= current-lp-balance liquidity) err-insufficient-liquidity)
    (asserts! (>= stx-amount min-stx) err-slippage-tolerance)
    (asserts! (>= token-amount min-tokens) err-slippage-tolerance)
    
    ;; Update reserves
    (var-set stx-reserve (- current-stx-reserve stx-amount))
    (var-set token-reserve (- current-token-reserve token-amount))
    (var-set total-supply (- current-total-supply liquidity))
    
    ;; Update LP balance
    (map-set lp-balances tx-sender (- current-lp-balance liquidity))
    
    ;; Transfer STX to user
    (try! (as-contract (stx-transfer? stx-amount tx-sender tx-sender)))
    
    ;; Transfer tokens to user
    (try! (as-contract (contract-call? token-trait transfer token-amount tx-sender tx-sender none)))
    
    (ok { stx: stx-amount, tokens: token-amount })
  )
)

;; Swap STX for tokens
(define-public (swap-stx-for-tokens (token-trait <sip-010-token>) (stx-amount uint) (min-tokens uint))
  (let (
    (current-stx-reserve (var-get stx-reserve))
    (current-token-reserve (var-get token-reserve))
    (tokens-out (get-amount-out stx-amount current-stx-reserve current-token-reserve))
    (nonce (var-get event-nonce))
  )
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq (contract-of token-trait) (var-get token-contract)) err-invalid-token)
    (asserts! (> stx-amount u0) err-insufficient-amount)
    (asserts! (>= tokens-out min-tokens) err-slippage-tolerance)
    (asserts! (< tokens-out current-token-reserve) err-insufficient-liquidity)
    
    ;; Update reserves
    (var-set stx-reserve (+ current-stx-reserve stx-amount))
    (var-set token-reserve (- current-token-reserve tokens-out))
    
    ;; Transfer tokens to user
    (try! (as-contract (contract-call? token-trait transfer tokens-out tx-sender tx-sender none)))
    
    ;; Log swap event
    (map-set swap-events 
      { tx-id: nonce }
      { 
        user: tx-sender,
        stx-in: stx-amount,
        token-out: tokens-out,
        stx-out: u0,
        token-in: u0,
        block-height: block-height
      }
    )
    (var-set event-nonce (+ nonce u1))
    
    (ok tokens-out)
  )
)

;; Swap tokens for STX
(define-public (swap-tokens-for-stx (token-trait <sip-010-token>) (token-amount uint) (min-stx uint))
  (let (
    (current-stx-reserve (var-get stx-reserve))
    (current-token-reserve (var-get token-reserve))
    (stx-out (get-amount-out token-amount current-token-reserve current-stx-reserve))
    (nonce (var-get event-nonce))
  )
    (asserts! (var-get initialized) err-not-initialized)
    (asserts! (is-eq (contract-of token-trait) (var-get token-contract)) err-invalid-token)
    (asserts! (> token-amount u0) err-insufficient-amount)
    (asserts! (>= stx-out min-stx) err-slippage-tolerance)
    (asserts! (< stx-out current-stx-reserve) err-insufficient-liquidity)
    
    ;; Transfer tokens from user
    (try! (contract-call? token-trait transfer token-amount tx-sender (as-contract tx-sender) none))
    
    ;; Update reserves
    (var-set stx-reserve (- current-stx-reserve stx-out))
    (var-set token-reserve (+ current-token-reserve token-amount))
    
    ;; Transfer STX to user
    (try! (as-contract (stx-transfer? stx-out tx-sender tx-sender)))
    
    ;; Log swap event
    (map-set swap-events 
      { tx-id: nonce }
      { 
        user: tx-sender,
        stx-in: u0,
        token-out: u0,
        stx-out: stx-out,
        token-in: token-amount,
        block-height: block-height
      }
    )
    (var-set event-nonce (+ nonce u1))
    
    (ok stx-out)
  )
)