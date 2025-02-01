;; Dynamic Academic Credential System
;; Core smart contract for managing evolving academic credentials

(define-data-var admin principal tx-sender)

;; Define credential types
(define-map credential-types 
  { credential-id: uint } 
  { 
    name: (string-ascii 50),
    level: uint,
    required-points: uint
  }
)

;; Store user credentials
(define-map user-credentials 
  { user: principal, credential-id: uint } 
  {
    current-level: uint,
    points: uint,
    last-updated: uint,
    verification-status: bool
  }
)

;; Store skill progressions
(define-map skill-progressions
  { user: principal, skill-id: uint }
  {
    points: uint,
    last-updated: uint,
    verifications: (list 10 principal)
  }
)

;; Add a new credential type
(define-public (add-credential-type (id uint) (name (string-ascii 50)) (level uint) (required-points uint))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) (err u1))
    (ok (map-set credential-types { credential-id: id } 
      { 
        name: name,
        level: level,
        required-points: required-points
      }))
  )
)

;; Update user skill progression
(define-public (update-skill-progression 
    (user principal) 
    (skill-id uint) 
    (points-earned uint)
    (verification principal))
  (let (
    (current-progression (default-to 
      { 
        points: u0,
        last-updated: u0,
        verifications: (list)
      }
      (map-get? skill-progressions { user: user, skill-id: skill-id })))
  )
  (begin
    (asserts! (is-some (map-get? credential-types { credential-id: skill-id })) (err u2))
    (ok (map-set skill-progressions 
      { user: user, skill-id: skill-id }
      {
        points: (+ (get points current-progression) points-earned),
        last-updated: block-height,
        verifications: (unwrap-panic (as-max-len? 
          (append (get verifications current-progression) verification) u10))
      }
    )))
  )
)

;; Check if credential can be upgraded
(define-public (check-credential-upgrade (user principal) (credential-id uint))
  (let (
    (user-cred (unwrap-panic (map-get? user-credentials { user: user, credential-id: credential-id })))
    (cred-type (unwrap-panic (map-get? credential-types { credential-id: credential-id })))
  )
  (if (>= (get points user-cred) (get required-points cred-type))
    (ok true)
    (ok false)
  ))
)

;; Upgrade credential
(define-public (upgrade-credential (user principal) (credential-id uint))
  (let (
    (can-upgrade (unwrap-panic (check-credential-upgrade user credential-id)))
    (current-cred (unwrap-panic (map-get? user-credentials { user: user, credential-id: credential-id })))
  )
  (begin
    (asserts! can-upgrade (err u3))
    (ok (map-set user-credentials 
      { user: user, credential-id: credential-id }
      {
        current-level: (+ (get current-level current-cred) u1),
        points: u0,
        last-updated: block-height,
        verification-status: true
      }
    )))
  )
)
