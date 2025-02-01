;; CredentialChain: Dynamic Academic Credential Evolution System
;; Version: 2.0.0 (2025 Edition)

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-CREDENTIAL (err u101))
(define-constant ERR-INSUFFICIENT-POINTS (err u102))
(define-constant ERR-INVALID-VERIFIER (err u103))
(define-constant ERR-PAUSED (err u104))
(define-constant ERR-INVALID-TOKEN (err u105))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var token-uri (string-utf8 256) u"")
(define-data-var minimum-verifiers uint u3)
(define-data-var upgrade-cooldown uint u144)
(define-data-var contract-paused bool false)

;; Data Maps
(define-map token-owners 
    uint 
    { owner: principal })

(define-map verifiers
    principal
    {
        active: bool,
        verification-count: uint,
        last-verification: uint,
        reputation: uint
    })

(define-map credential-types 
    uint 
    { 
        name: (string-ascii 50),
        required-points: uint,
        verification-threshold: uint,
        active: bool,
        metadata: (string-utf8 256)
    })

(define-map user-credentials 
    { user: principal, credential-id: uint } 
    {
        level: uint,
        points: uint,
        last-updated: uint,
        verifications: (list 10 principal),
        token-id: (optional uint)
    })

;; Private Functions
(define-private (is-admin)
    (is-eq tx-sender CONTRACT-OWNER))

(define-private (is-verifier (account principal))
    (default-to 
        false
        (get active (map-get? verifiers account))))

(define-private (is-active-credential (credential-id uint))
    (match (map-get? credential-types credential-id)
        credential (and 
            (get active credential)
            (not (var-get contract-paused)))
        false))

(define-private (can-upgrade 
        (user principal) 
        (credential-id uint))
    (match (map-get? user-credentials { user: user, credential-id: credential-id })
        credential (and
            (match (map-get? credential-types credential-id)
                type (>= (get points credential) (get required-points type))
                false)
            (>= (len (get verifications credential)) (var-get minimum-verifiers)))
        false))

;; Read-Only Functions
(define-read-only (get-token-owner (token-id uint))
    (ok (match (map-get? token-owners token-id)
        owner (some (get owner owner))
        none)))

(define-read-only (get-token-uri (token-id uint))
    (ok (some (var-get token-uri))))

(define-read-only (get-user-credential (user principal) (credential-id uint))
    (map-get? user-credentials { user: user, credential-id: credential-id }))

;; Public Functions
(define-public (add-credential-type 
        (id uint) 
        (name (string-ascii 50))
        (required-points uint)
        (verification-threshold uint)
        (metadata (string-utf8 256)))
    (begin
        (asserts! (is-admin) ERR-NOT-AUTHORIZED)
        (asserts! (not (var-get contract-paused)) ERR-PAUSED)
        (map-set credential-types id
            {
                name: name,
                required-points: required-points,
                verification-threshold: verification-threshold,
                active: true,
                metadata: metadata
            })
        (ok true)))

(define-public (set-verifier 
        (account principal) 
        (active bool))
    (begin
        (asserts! (is-admin) ERR-NOT-AUTHORIZED)
        (map-set verifiers account
            {
                active: active,
                verification-count: u0,
                last-verification: u0,
                reputation: u100
            })
        (ok true)))

(define-public (add-verification 
        (user principal) 
        (credential-id uint) 
        (points uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-PAUSED)
        (asserts! (is-verifier tx-sender) ERR-INVALID-VERIFIER)
        (asserts! (is-active-credential credential-id) ERR-INVALID-CREDENTIAL)
        
        (match (get-user-credential user credential-id)
            existing 
                (map-set user-credentials 
                    { user: user, credential-id: credential-id }
                    {
                        level: (get level existing),
                        points: (+ (get points existing) points),
                        last-updated: block-height,
                        verifications: (unwrap-panic 
                            (as-max-len? 
                                (append (get verifications existing) tx-sender)
                                u10)),
                        token-id: (get token-id existing)
                    })
            ;; If no existing record, create new
            (map-set user-credentials
                { user: user, credential-id: credential-id }
                {
                    level: u1,
                    points: points,
                    last-updated: block-height,
                    verifications: (list tx-sender),
                    token-id: none
                }))
        (ok true)))

(define-public (upgrade-credential 
        (credential-id uint))
    (begin
        (asserts! (not (var-get contract-paused)) ERR-PAUSED)
        (asserts! (is-active-credential credential-id) ERR-INVALID-CREDENTIAL)
        (asserts! (can-upgrade tx-sender credential-id) ERR-INSUFFICIENT-POINTS)
        
        (let ((new-token-id (+ (var-get last-token-id) u1)))
            (map-set token-owners new-token-id { owner: tx-sender })
            (var-set last-token-id new-token-id)
            
            (match (get-user-credential tx-sender credential-id)
                existing 
                    (map-set user-credentials 
                        { user: tx-sender, credential-id: credential-id }
                        {
                            level: (+ (get level existing) u1),
                            points: u0,
                            last-updated: block-height,
                            verifications: (list),
                            token-id: (some new-token-id)
                        })
                    (err ERR-INVALID-CREDENTIAL)))
        (ok true)))

;; Admin Functions
(define-public (pause-contract)
    (begin
        (asserts! (is-admin) ERR-NOT-AUTHORIZED)
        (var-set contract-paused true)
        (ok true)))

(define-public (resume-contract)
    (begin
        (asserts! (is-admin) ERR-NOT-AUTHORIZED)
        (var-set contract-paused false)
        (ok true)))
