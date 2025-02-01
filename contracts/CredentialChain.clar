;; CredentialChain: Dynamic Academic Credential Evolution System
;; Author: [Your Name]
;; Version: 1.0.0

;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-CREDENTIAL (err u101))
(define-constant ERR-INSUFFICIENT-POINTS (err u102))
(define-constant ERR-ALREADY-VERIFIED (err u103))
(define-constant ERR-INVALID-VERIFIER (err u104))

;; Data Variables
(define-data-var minimum-verifiers uint u3)
(define-data-var upgrade-cooldown uint u144) ;; ~24 hours in blocks

;; Data Maps
(define-map Verifiers
    principal
    {
        status: bool,
        verification-count: uint,
        last-verification: uint
    })

(define-map CredentialTypes 
    { credential-id: uint } 
    { 
        name: (string-ascii 50),
        level: uint,
        required-points: uint,
        verification-threshold: uint,
        cooldown-period: uint,
        active: bool
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
            verifier: principal
        })
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
        active: bool
    }))
    (get active credential))

;; Read-Only Functions
(define-read-only (get-credential-type (credential-id uint))
    (map-get? CredentialTypes { credential-id: credential-id }))

(define-read-only (get-user-credential (user principal) (credential-id uint))
    (map-get? UserCredentials { user: user, credential-id: credential-id }))

(define-read-only (is-authorized-verifier (verifier principal))
    (default-to 
        false
        (get status (map-get? Verifiers verifier))))

;; Public Functions
(define-public (set-credential-type 
        (credential-id uint) 
        (name (string-ascii 50)) 
        (required-points uint)
        (verification-threshold uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (ok (map-set CredentialTypes 
            { credential-id: credential-id }
            {
                name: name,
                level: u1,
                required-points: required-points,
                verification-threshold: verification-threshold,
                cooldown-period: (var-get upgrade-cooldown),
                active: true
            }))))

(define-public (set-verifier (verifier principal) (status bool))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (ok (map-set Verifiers 
            verifier
            {
                status: status,
                verification-count: u0,
                last-verification: u0
            }))))

(define-public (submit-achievement 
        (user principal) 
        (credential-id uint) 
        (points uint)
        (verifier principal))
    (let (
        (credential (unwrap! (get-credential-type credential-id) ERR-INVALID-CREDENTIAL))
        (current-data (default-to 
            {
                current-level: u1,
                points: u0,
                last-updated: u0,
                verifications: (list),
                achievement-log: (list)
            } 
            (get-user-credential user credential-id))))
        (begin
            (asserts! (is-authorized-verifier verifier) ERR-INVALID-VERIFIER)
            (asserts! (is-active credential) ERR-INVALID-CREDENTIAL)
            (ok (map-set UserCredentials 
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
                                    verifier: verifier
                                }) 
                            u20))
                    }))))))

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
            (ok (map-set UserCredentials 
                { user: user, credential-id: credential-id }
                (merge current-data 
                    {
                        current-level: (+ (get current-level current-data) u1),
                        points: u0,
                        last-updated: block-height,
                        verifications: (list),
                        achievement-log: (list)
                    }))))))

;; Initialize contract
(define-public (initialize (new-cooldown uint) (new-min-verifiers uint))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set upgrade-cooldown new-cooldown)
        (var-set minimum-verifiers new-min-verifiers)
        (ok true)))
        