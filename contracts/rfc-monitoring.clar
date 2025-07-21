;; rfc-monitoring.clar
;; A smart contract to track and manage Request for Comments (RFC) proposals
;; on a decentralized platform, implementing proposal tracking, review, and bounty mechanisms.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-PROPOSAL-EXISTS (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-PROPOSAL-ALREADY-COMPLETED (err u104))
(define-constant ERR-REVIEW-EXISTS (err u105))
(define-constant ERR-REVIEW-NOT-FOUND (err u106))
(define-constant ERR-REVIEW-ALREADY-COMPLETED (err u107))
(define-constant ERR-INSUFFICIENT-FUNDS (err u108))
(define-constant ERR-PAYMENT-FAILED (err u109))
(define-constant ERR-INVALID-PARTICIPANT (err u110))
(define-constant ERR-NOT-PROPOSAL-PARTICIPANT (err u111))
(define-constant ERR-BOUNTY-ALREADY-RELEASED (err u112))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-PERCENTAGE u5) ;; 5% fee
(define-constant MIN-PROPOSAL-BOUNTY u1000000) ;; 1 STX minimum
(define-constant MIN-REVIEW-BOUNTY u500000) ;; 0.5 STX minimum

;; Data maps for RFC proposals
(define-map proposals
  { proposal-id: uint }
  {
    author: principal,
    title: (string-ascii 100),
    description: (string-utf8 1000),
    status: (string-ascii 20), ;; "draft", "review", "accepted", "rejected"
    bounty: uint,
    platform-fee: uint,
    created-at: uint
  }
)

;; Data maps for RFC reviews
(define-map reviews
  { review-id: uint }
  {
    proposal-id: uint,
    reviewer: principal,
    feedback: (string-utf8 2000),
    rating: uint,
    status: (string-ascii 20), ;; "pending", "completed"
    bounty: uint,
    platform-fee: uint,
    created-at: uint
  }
)

;; Counter variables for unique IDs
(define-data-var next-proposal-id uint u1)
(define-data-var next-review-id uint u1)

;; Map to track platform earnings
(define-data-var platform-earnings uint u0)

;; =============================
;; Private Functions
;; =============================

;; Calculate platform fee for a given amount
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE-PERCENTAGE) u100)
)

;; Check if sender is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; =============================
;; Read-only Functions
;; =============================

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Get review details
(define-read-only (get-review (review-id uint))
  (map-get? reviews { review-id: review-id })
)

;; Get platform earnings
(define-read-only (get-platform-earnings)
  (var-get platform-earnings)
)

;; =============================
;; Public Functions
;; =============================

;; Create a new RFC proposal with an optional review bounty
(define-public (create-proposal 
  (title (string-ascii 100)) 
  (description (string-utf8 1000)) 
  (bounty uint)
)
  (let (
    (proposal-id (var-get next-proposal-id))
    (platform-fee (calculate-platform-fee bounty))
    (reviewer-amount (- bounty platform-fee))
  )
    ;; Validate parameters
    (asserts! (>= bounty MIN-PROPOSAL-BOUNTY) ERR-INVALID-AMOUNT)
    
    ;; Record the proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        author: tx-sender,
        title: title,
        description: description,
        status: "draft",
        bounty: bounty,
        platform-fee: platform-fee,
        created-at: block-height
      }
    )
    
    ;; Increment proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Submit a review for an RFC proposal
(define-public (submit-review 
  (proposal-id uint) 
  (feedback (string-utf8 2000)) 
  (rating uint)
)
  (let (
    (review-id (var-get next-review-id))
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
    (platform-fee (calculate-platform-fee (get bounty proposal)))
    (reviewer-amount (- (get bounty proposal) platform-fee))
  )
    ;; Validate proposal status and review parameters
    (asserts! (is-eq (get status proposal) "draft") ERR-PROPOSAL-ALREADY-COMPLETED)
    (asserts! (not (is-eq tx-sender (get author proposal))) ERR-INVALID-PARTICIPANT)
    (asserts! (<= rating u10) ERR-INVALID-AMOUNT) ;; Assuming a 10-point rating scale
    
    ;; Record the review
    (map-set reviews
      { review-id: review-id }
      {
        proposal-id: proposal-id,
        reviewer: tx-sender,
        feedback: feedback,
        rating: rating,
        status: "pending",
        bounty: (get bounty proposal),
        platform-fee: platform-fee,
        created-at: block-height
      }
    )
    
    ;; Update proposal status to "review"
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { status: "review" })
    )
    
    ;; Increment review ID
    (var-set next-review-id (+ review-id u1))
    
    (ok review-id)
  )
)

;; Complete a review and release bounty (called by proposal author)
(define-public (complete-review (review-id uint))
  (match (map-get? reviews { review-id: review-id })
    review (let (
      (proposal (unwrap! (map-get? proposals { proposal-id: (get proposal-id review) }) ERR-PROPOSAL-NOT-FOUND))
    )
      ;; Ensure caller is the proposal author
      (asserts! (is-eq tx-sender (get author proposal)) ERR-NOT-AUTHORIZED)
      
      ;; Ensure review is still pending
      (asserts! (is-eq (get status review) "pending") ERR-REVIEW-ALREADY-COMPLETED)
      
      ;; Update review status
      (map-set reviews
        { review-id: review-id }
        (merge review { status: "completed" })
      )
      
      ;; Transfer bounty to reviewer
      (unwrap! 
        (as-contract (stx-transfer? 
          (- (get bounty review) (get platform-fee review)) 
          tx-sender 
          (get reviewer review)
        ))
        ERR-PAYMENT-FAILED
      )
      
      ;; Add platform fee to earnings
      (var-set platform-earnings (+ (var-get platform-earnings) (get platform-fee review)))
      
      ;; Update proposal status to "accepted"
      (map-set proposals
        { proposal-id: (get proposal-id review) }
        (merge proposal { status: "accepted" })
      )
      
      (ok true)
    )
    ERR-REVIEW-NOT-FOUND
  )
)

;; Withdraw platform earnings (only contract owner)
(define-public (withdraw-platform-earnings (amount uint))
  (begin
    ;; Ensure caller is contract owner
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Ensure amount is valid
    (asserts! (<= amount (var-get platform-earnings)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Transfer earnings
    (unwrap! 
      (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER))
      ERR-PAYMENT-FAILED
    )
    
    ;; Update platform earnings
    (var-set platform-earnings (- (var-get platform-earnings) amount))
    
    (ok true)
  )
)