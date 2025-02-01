;; CredentialChain: Dynamic Academic Credential Evolution System
;; Version: 1.1.0
;; Implements local NFT trait

;; Traits
(use-trait nft-trait .nft-trait.nft-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-CREDENTIAL (err u101))
(define-constant ERR-INSUFFICIENT-POINTS (err u102))
(define-constant ERR-ALREADY-VERIFIED (err u103))
(define-constant ERR-INVALID-VERIFIER (err u104))
(define-constant ERR-EXPIRED-VERIFICATION (err u105))
(define-constant ERR-COOLDOWN-ACTIVE (err u106))
(define-constant VERIFICATION-EXPIRY u10000) ;; ~7 days in blocks

;; SIP-009 NFT Data Variables
(define-data-var last-token-id uint u0)
(define-data-var token-uri (string-utf8 256) u"")

;; Data Variables
(define-data-var minimum-verifiers uint u3)
(define-data-var upgrade-cooldown uint u144) ;; ~24 hours in blocks
(define-data-var paused bool false)

;; Data Maps
(define-map Verifiers
    principal
    {
        status: bool,
        verification-count: uint,
        last-verification: uint,
        reputation-score: uint,
        specializations: (list 5 uint)
    })

(define-map CredentialTypes 
    { credential-id: uint } 
    { 
        name: (string-ascii 50),
        level: uint,
        required-points: uint,
        verification-threshold: uint,
        cooldown-period: uint,
        active: bool,
        metadata-uri: (optional (string-utf8 256))
    })

(define-map UserCredentials 
    { user: principal, credential-id: uint } 
    {
        current-level: uint,
        points: uint,
        last-updated: uint,
        verifications: (list 10 principal),
        achievement-log: (list 20 {
            timestamp: uint,
            points: uint,
            verifier: principal,
            evidence-hash: (optional (buff 32))
        }),
        token-id: (optional uint)
    })

;; Events
(define-data-var last-event-id uint u0)

(define-map Events
    uint
    {
        event-type: (string-ascii 20),
        user: principal,
        credential-id: uint,
        timestamp: uint,
        data: (optional (string-utf8 256))
    })

;; Private Functions
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner))

(define-private (is-active (credential {
        name: (string-ascii 50),
        level: uint,
        required-points: uint,
        verification-threshold: uint,
        cooldown-period: uint,
        active: bool,
        metadata-uri: (optional (string-utf8 256))
    }))
    (and 
        (get active credential)
        (not (var-get paused))))

(define-private (log-event 
        (event-type (string-ascii 20))
        (user principal)
        (credential-id uint)
        (data (optional (string-utf8 256))))
    (begin
        (var-set last-event-id (+ (var-get last-event-id) u1))
        (map-set Events
            (var-get last-event-id)
            {
                event-type: event-type,
                user: user,
                credential-id: credential-id,
                timestamp: block-height,
                data: data
            })
        (var-get last-event-id)))

(define-private (mint-credential-nft (user principal) (credential-id uint))
    (let ((new-id (+ (var-get last-token-id) u1)))
        (begin
            (var-set last-token-id new-id)
            (map-set token-owners new-id { owner: user })
            (map-set UserCredentials
                { user: user, credential-id: credential-id }
                (merge (unwrap-panic (get-user-credential user credential-id))
                    { token-id: (some new-id) }))
            new-id)))

;; Read-Only Functions
(define-read-only (get-credential-type (credential-id uint))
    (map-get? CredentialTypes { credential-id: credential-id }))

(define-read-only (get-user-credential (user principal) (credential-id uint))
    (map-get? UserCredentials { user: user, credential-id: credential-id }))

(define-read-only (is-authorized-verifier (verifier principal))
    (default-to 
        false
        (get status (map-get? Verifiers verifier))))

(define-read-only (get-verifier-reputation (verifier principal))
    (default-to
        u0
        (get reputation-score (map-get? Verifiers verifier))))

;; SIP-009 NFT Functions
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id)))

(define-read-only (get-token-uri (token-id uint))
    (ok (var-get token-uri)))

(define-map token-owners
    uint 
    { owner: principal })

(define-read-only (get-owner (token-id uint))
    (ok (get owner 
        (default-to 
            { owner: tx-sender }
            (map-get? token-owners token-id)))))

;; Public Functions
(define-public (set-credential-type 
        (credential-id uint) 
        (name (string-ascii 50)) 
        (required-points uint)
        (verification-threshold uint)
        (metadata-uri (optional (string-utf8 256))))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
        (ok (map-set CredentialTypes 
            { credential-id: credential-id }
            {
                name: name,
                level: u1,
                required-points: required-points,
                verification-threshold: verification-threshold,
                cooldown-period: (var-get upgrade-cooldown),
                active: true,
                metadata-uri: metadata-uri
            }))))

(define-public (set-verifier 
        (verifier principal) 
        (status bool)
        (specializations (list 5 uint)))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (ok (map-set Verifiers 
            verifier
            {
                status: status,
                verification-count: u0,
                last-verification: u0,
                reputation-score: u100,
                specializations: specializations
            }))))

(define-public (submit-achievement 
        (user principal) 
        (credential-id uint) 
        (points uint)
        (verifier principal)
        (evidence-hash (optional (buff 32))))
    (let (
        (credential (unwrap! (get-credential-type credential-id) ERR-INVALID-CREDENTIAL))
        (current-data (default-to 
            {
                current-level: u1,
                points: u0,
                last-updated: u0,
                verifications: (list),
                achievement-log: (list),
                token-id: none
            } 
            (get-user-credential user credential-id))))
        (begin
            (asserts! (is-authorized-verifier verifier) ERR-INVALID-VERIFIER)
            (asserts! (is-active credential) ERR-INVALID-CREDENTIAL)
            (asserts! (> (get reputation-score (unwrap! (map-get? Verifiers verifier) ERR-INVALID-VERIFIER)) u50) ERR-INVALID-VERIFIER)
            (try! (map-set UserCredentials 
                { user: user, credential-id: credential-id }
                (merge current-data 
                    {
                        points: (+ (get points current-data) points),
                        last-updated: block-height,
                        achievement-log: (unwrap-panic (as-max-len? 
                            (append 
                                (get achievement-log current-data) 
                                {
                                    timestamp: block-height,
                                    points: points,
                                    verifier: verifier,
                                    evidence-hash: evidence-hash
                                }) 
                            u20))
                    })))
            (log-event "achievement" user credential-id none)
            (ok true))))

(define-public (check-upgrade-eligibility (user principal) (credential-id uint))
    (let (
        (credential (unwrap! (get-credential-type credential-id) ERR-INVALID-CREDENTIAL))
        (user-data (unwrap! (get-user-credential user credential-id) ERR-INVALID-CREDENTIAL)))
        (ok (and
            (>= (get points user-data) (get required-points credential))
            (>= (len (get verifications user-data)) (get verification-threshold credential))
            (>= (- block-height (get last-updated user-data)) (get cooldown-period credential))))))

(define-public (upgrade-credential (user principal) (credential-id uint))
    (let (
        (can-upgrade (unwrap-panic (check-upgrade-eligibility user credential-id)))
        (current-data (unwrap! (get-user-credential user credential-id) ERR-INVALID-CREDENTIAL)))
        (begin
            (asserts! can-upgrade ERR-INSUFFICIENT-POINTS)
            (try! (map-set UserCredentials 
                { user: user, credential-id: credential-id }
                (merge current-data 
                    {
                        current-level: (+ (get current-level current-data) u1),
                        points: u0,
                        last-updated: block-height,
                        verifications: (list),
                        achievement-log: (list)
                    })))
            (mint-credential-nft user credential-id)
            (log-event "upgrade" user credential-id none)
            (ok true))))

;; Emergency Functions
(define-public (pause)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set paused true)
        (log-event "pause" contract-owner u0 none)
        (ok true)))

(define-public (unpause)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set paused false)
        (log-event "unpause" contract-owner u0 none)
        (ok true)))
