;; Lumina  Exchange - Enlightenment transmission work


;; ==================== KNOWLEDGE STORAGE MAPS ====================
;; Maps to track participant wisdom credits and offerings
(define-map wisdom-credit-balance principal uint)    ;; Participant's available wisdom credits
(define-map knowledge-token-balance principal uint)  ;; Participant's available token balance
(define-map wisdom-offerings {sage: principal} {insights: uint, value: uint})

;; ==================== WISDOM QUALITY VERIFICATION ====================
(define-map wisdom-masters principal bool)
(define-map premium-wisdom-offerings {sage: principal} {insights: uint, value: uint, verified: bool})

;; ==================== ECOSYSTEM PARAMETERS ====================
(define-data-var insight-base-value uint u10)  
(define-data-var participant-wisdom-threshold uint u100) 
(define-data-var nexus-commission-rate uint u10)
(define-data-var collective-wisdom-pool uint u0) 
(define-data-var wisdom-capacity-ceiling uint u1000) 

;; ==================== CONFIGURATION CONSTANTS ====================
(define-constant contract-governor tx-sender)
(define-constant err-unauthorized (err u400))
(define-constant err-insufficient-wisdom-credits (err u401))
(define-constant err-invalid-insight-amount (err u402))
(define-constant err-pricing-invalid (err u403))
(define-constant err-nexus-capacity-exceeded (err u404))
(define-constant err-operation-forbidden (err u405))
(define-constant err-knowledge-pool-limit (err u406))
(define-constant err-zero-quantity (err u407))
(define-constant err-fee-limit-exceeded (err u408))
(define-constant err-parameter-zero (err u409))
(define-constant err-capacity-not-reducible (err u410))
(define-constant err-not-wisdom-master (err u411))
(define-constant err-feedback-below-minimum (err u412))
(define-constant err-feedback-above-maximum (err u413))
(define-constant err-incentive-below-minimum (err u414))
(define-constant err-incentive-above-maximum (err u415))

;; ==================== COLLECTIVE LEARNING SESSIONS ====================
(define-map learning-circles uint {facilitator: principal, participants: (list 10 principal), duration: uint, contribution: uint, status: (string-ascii 20)})
(define-data-var circle-counter uint u0)

;; ==================== SAGE REPUTATION SYSTEM ====================
(define-map sage-evaluation {wisdom-provider: principal, seeker: principal} uint)
(define-map sage-reputation principal {wisdom-points: uint, evaluation-count: uint})

;; ==================== WISDOM PACKAGE BUNDLES ====================
(define-map wisdom-bundles {sage: principal} {insights: uint, value: uint, incentive-rate: uint})

;; ==================== UTILITY FUNCTIONS ====================
(define-private (update-wisdom-pool (insight-delta int))
  (let (
    (current-pool-size (var-get collective-wisdom-pool))
    (new-pool-size (if (< insight-delta 0)
                     ;; When removing insights, ensure non-negative result
                     (if (>= current-pool-size (to-uint (- 0 insight-delta)))
                         (- current-pool-size (to-uint (- 0 insight-delta)))
                         u0)
                     ;; When adding insights
                     (+ current-pool-size (to-uint insight-delta))))
  )
    ;; Verify we don't exceed the maximum capacity
    (asserts! (<= new-pool-size (var-get wisdom-capacity-ceiling)) err-nexus-capacity-exceeded)
    ;; Update the collective pool size
    (var-set collective-wisdom-pool new-pool-size)
    (ok true)))

(define-private (calculate-nexus-fee (exchange-value uint))
  (let ((commission-percent (var-get nexus-commission-rate)))
    (/ (* exchange-value commission-percent) u100)))

;; ==================== CORE PROTOCOL FUNCTIONS ====================

;; Register new wisdom credits in participant's account
(define-public (acquire-wisdom-credits (insights uint))
  (let (
    (participant tx-sender)
    (current-insights (default-to u0 (map-get? wisdom-credit-balance participant)))
    (max-allowed (var-get participant-wisdom-threshold))
    (acquisition-cost (* insights (var-get insight-base-value)))
    (participant-tokens (default-to u0 (map-get? knowledge-token-balance participant)))
  )
    ;; Verify the input parameters
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (<= (+ current-insights insights) max-allowed) err-knowledge-pool-limit)
    (asserts! (>= participant-tokens acquisition-cost) err-insufficient-wisdom-credits)

    ;; Update participant's wisdom and token balances
    (map-set wisdom-credit-balance participant (+ current-insights insights))
    (map-set knowledge-token-balance participant (- participant-tokens acquisition-cost))

    ;; Transfer tokens to the governor's balance
    (map-set knowledge-token-balance contract-governor (+ (default-to u0 (map-get? knowledge-token-balance contract-governor)) acquisition-cost))

    (ok true)))

;; Make wisdom insights available for others to acquire
(define-public (share-wisdom-insights (insights uint) (value uint))
  (let (
    (current-insights (default-to u0 (map-get? wisdom-credit-balance tx-sender)))
    (previously-shared (get insights (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: tx-sender}))))
    (total-shared (+ insights previously-shared))
  )
    ;; Validate the input parameters
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (> value u0) err-pricing-invalid)
    (asserts! (>= current-insights total-shared) err-insufficient-wisdom-credits)

    ;; Update the collective wisdom pool
    (try! (update-wisdom-pool (to-int insights)))

    ;; Update the available wisdom insights map
    (map-set wisdom-offerings {sage: tx-sender} {insights: total-shared, value: value})

    (ok true)))

;; Seek wisdom from another participant
(define-public (seek-wisdom (sage principal) (insights uint))
  (let (
    (offering (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: sage})))
    (exchange-value (* insights (get value offering)))
    (nexus-fee (calculate-nexus-fee exchange-value))
    (total-cost (+ exchange-value nexus-fee))
    (sage-insights (default-to u0 (map-get? wisdom-credit-balance sage)))
    (seeker-tokens (default-to u0 (map-get? knowledge-token-balance tx-sender)))
    (sage-tokens (default-to u0 (map-get? knowledge-token-balance sage)))
  )
    ;; Verify exchange conditions
    (asserts! (not (is-eq tx-sender sage)) err-operation-forbidden)
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (>= (get insights offering) insights) err-insufficient-wisdom-credits)
    (asserts! (>= sage-insights insights) err-insufficient-wisdom-credits)
    (asserts! (>= seeker-tokens total-cost) err-insufficient-wisdom-credits)

    ;; Update sage's wisdom balance and available offerings
    (map-set wisdom-credit-balance sage (- sage-insights insights))
    (map-set wisdom-offerings {sage: sage} 
             {insights: (- (get insights offering) insights), value: (get value offering)})

    ;; Update token balances for the exchange
    (map-set knowledge-token-balance tx-sender (- seeker-tokens total-cost))
    (map-set knowledge-token-balance sage (+ sage-tokens exchange-value))
    (map-set wisdom-credit-balance tx-sender (+ (default-to u0 (map-get? wisdom-credit-balance tx-sender)) insights))

    ;; Add commission to governor balance
    (map-set knowledge-token-balance contract-governor (+ (default-to u0 (map-get? knowledge-token-balance contract-governor)) nexus-fee))

    (ok true)))

;; Share verified premium wisdom insights (requires wisdom master status)
(define-public (share-premium-wisdom (insights uint) (value uint))
  (let (
    (current-insights (default-to u0 (map-get? wisdom-credit-balance tx-sender)))
    (is-wisdom-master (default-to false (map-get? wisdom-masters tx-sender)))
    (previously-shared (get insights (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: tx-sender}))))
    (total-shared (+ insights previously-shared))
  )
    ;; Validate the input parameters
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (> value u0) err-pricing-invalid)
    (asserts! is-wisdom-master err-not-wisdom-master)
    (asserts! (>= current-insights total-shared) err-insufficient-wisdom-credits)

    ;; Update the collective wisdom pool
    (try! (update-wisdom-pool (to-int insights)))

    ;; Update regular wisdom offerings
    (map-set wisdom-offerings {sage: tx-sender} {insights: total-shared, value: value})

    ;; Update premium wisdom offerings
    (map-set premium-wisdom-offerings {sage: tx-sender} {insights: insights, value: value, verified: true})

    (ok true)))

;; Create a wisdom bundle with incentive rate
(define-public (create-wisdom-bundle (insights uint) (value uint) (incentive-rate uint))
  (let (
    (current-insights (default-to u0 (map-get? wisdom-credit-balance tx-sender)))
    (previously-shared (get insights (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: tx-sender}))))
    (current-bundle (default-to {insights: u0, value: u0, incentive-rate: u0} (map-get? wisdom-bundles {sage: tx-sender})))
    (total-shared (+ insights previously-shared))
    (total-bundled-insights (+ insights (get insights current-bundle)))
  )
    ;; Validate the input parameters
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (> value u0) err-pricing-invalid)
    (asserts! (> incentive-rate u0) err-incentive-below-minimum)
    (asserts! (<= incentive-rate u50) err-incentive-above-maximum)
    (asserts! (>= current-insights total-shared) err-insufficient-wisdom-credits)

    ;; Update the collective wisdom pool
    (try! (update-wisdom-pool (to-int insights)))

    ;; Update wisdom availability
    (map-set wisdom-offerings {sage: tx-sender} {insights: total-shared, value: value})

    ;; Create or update the bundle offering
    (map-set wisdom-bundles {sage: tx-sender} {
      insights: total-bundled-insights, 
      value: value, 
      incentive-rate: incentive-rate
    })

    (ok true)))

;; Create a collective wisdom circle
(define-public (create-wisdom-circle (participants (list 10 principal)) (duration uint) (contribution uint))
  (let (
    (current-insights (default-to u0 (map-get? wisdom-credit-balance tx-sender)))
    (circle-id (var-get circle-counter))
    (participant-count (len participants))
    (total-circle-insights (* duration participant-count))
  )
    ;; Validate the input parameters
    (asserts! (> duration u0) err-invalid-insight-amount)
    (asserts! (> contribution u0) err-pricing-invalid)
    (asserts! (>= current-insights total-circle-insights) err-insufficient-wisdom-credits)

    ;; Update the wisdom pool
    (try! (update-wisdom-pool (to-int total-circle-insights)))

    ;; Update facilitator's wisdom balance
    (map-set wisdom-credit-balance tx-sender (- current-insights total-circle-insights))

    ;; Increment the circle counter
    (var-set circle-counter (+ circle-id u1))

    (ok circle-id)))

;; Provide feedback for a wisdom provider
(define-public (rate-wisdom-provider (sage principal) (rating uint))
  (let (
    (sage-metrics (default-to {wisdom-points: u0, evaluation-count: u0} (map-get? sage-reputation sage)))
    (current-points (get wisdom-points sage-metrics))
    (current-count (get evaluation-count sage-metrics))
    (updated-points (+ current-points rating))
    (updated-count (+ current-count u1))
  )
    ;; Validate the input parameters
    (asserts! (not (is-eq tx-sender sage)) err-operation-forbidden)
    (asserts! (>= rating u1) err-feedback-below-minimum)
    (asserts! (<= rating u5) err-feedback-above-maximum)

    ;; Update the sage's reputation data
    (map-set sage-evaluation {wisdom-provider: sage, seeker: tx-sender} rating)
    (map-set sage-reputation sage {wisdom-points: updated-points, evaluation-count: updated-count})

    (ok true)))

;; Deposit knowledge tokens into the nexus
(define-public (deposit-knowledge-tokens (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? knowledge-token-balance tx-sender)))
    (new-balance (+ current-balance amount))
  )
    ;; Validate the input parameter
    (asserts! (> amount u0) err-zero-quantity)

    ;; Transfer tokens from sender to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    ;; Update participant's token balance in the nexus
    (map-set knowledge-token-balance tx-sender new-balance)

    (ok true)))

;; Withdraw knowledge tokens from the nexus
(define-public (withdraw-knowledge-tokens (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? knowledge-token-balance tx-sender)))
    (contract-balance (as-contract (stx-get-balance tx-sender)))
  )
    ;; Validate the input parameter
    (asserts! (> amount u0) err-zero-quantity)
    (asserts! (>= current-balance amount) err-insufficient-wisdom-credits)
    (asserts! (>= contract-balance amount) err-insufficient-wisdom-credits)

    ;; Transfer tokens from contract to participant
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))

    ;; Update participant's token balance in the nexus
    (map-set knowledge-token-balance tx-sender (- current-balance amount))

    (ok true)))

;; Reclaim shared wisdom that hasn't been acquired
(define-public (reclaim-shared-wisdom (insights uint))
  (let (
    (offering (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: tx-sender})))
    (available-insights (get insights offering))
    (participant-insights (default-to u0 (map-get? wisdom-credit-balance tx-sender)))
  )
    ;; Validate the input parameter
    (asserts! (> insights u0) err-invalid-insight-amount)
    (asserts! (>= available-insights insights) err-insufficient-wisdom-credits)

    ;; Update the participant's shared wisdom
    (map-set wisdom-offerings {sage: tx-sender} {
      insights: (- available-insights insights),
      value: (get value offering)
    })

    ;; Update participant's wisdom balance
    (map-set wisdom-credit-balance tx-sender (+ participant-insights insights))

    ;; Handle premium offerings if applicable
    (if (is-some (map-get? premium-wisdom-offerings {sage: tx-sender}))
        (let (
          (premium-offering (unwrap-panic (map-get? premium-wisdom-offerings {sage: tx-sender})))
          (premium-insights (get insights premium-offering))
        )
          (if (>= premium-insights insights)
              (map-set premium-wisdom-offerings {sage: tx-sender} {
                insights: (- premium-insights insights),
                value: (get value premium-offering),
                verified: (get verified premium-offering)
              })
              (map-delete premium-wisdom-offerings {sage: tx-sender})
          )
        )
        true
    )
    (ok true)))

;; Update nexus parameters (governance function)
(define-public (configure-nexus-parameters (new-insight-value uint) 
                                           (new-commission-rate uint) 
                                           (new-participant-threshold uint) 
                                           (new-wisdom-ceiling uint))
  (begin
    ;; Verify governance authority
    (asserts! (is-eq tx-sender contract-governor) err-unauthorized)

    ;; Validate the input parameters
    (asserts! (> new-insight-value u0) err-pricing-invalid)
    (asserts! (<= new-commission-rate u30) err-fee-limit-exceeded)
    (asserts! (> new-participant-threshold u0) err-parameter-zero)
    (asserts! (>= new-wisdom-ceiling (var-get collective-wisdom-pool)) err-capacity-not-reducible)

    ;; Update the nexus parameters
    (var-set insight-base-value new-insight-value)
    (var-set nexus-commission-rate new-commission-rate)
    (var-set participant-wisdom-threshold new-participant-threshold)
    (var-set wisdom-capacity-ceiling new-wisdom-ceiling)

    (ok true)))

;; Grant wisdom master status to a participant (governance function)
(define-public (certify-wisdom-master (participant principal))
  (begin
    ;; Verify governance authority
    (asserts! (is-eq tx-sender contract-governor) err-unauthorized)
    (ok true)))


;; Calculate average rating for a wisdom provider (read-only function)
(define-read-only (get-sage-average-rating (sage principal))
  (let (
    (reputation (default-to {wisdom-points: u0, evaluation-count: u0} (map-get? sage-reputation sage)))
    (total-points (get wisdom-points reputation))
    (total-evaluations (get evaluation-count reputation))
  )
    (if (> total-evaluations u0)
        (/ total-points total-evaluations)
        u0)
  ))

;; Query available wisdom from a provider (read-only function)
(define-read-only (get-available-wisdom (sage principal))
  (default-to {insights: u0, value: u0} (map-get? wisdom-offerings {sage: sage})))

;; Query if a participant is a certified wisdom master (read-only function)
(define-read-only (is-certified-wisdom-master (participant principal))
  (default-to false (map-get? wisdom-masters participant)))

