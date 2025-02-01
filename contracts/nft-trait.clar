;; NFT Trait Definition
(define-trait nft-trait
    (
        ;; Last token ID
        (get-last-token-id () (response uint uint))

        ;; URI for token metadata
        (get-token-uri (uint) (response (optional (string-utf8 256)) uint))

        ;; Owner of the token
        (get-owner (uint) (response (optional principal) uint))
    )
)
