#!/bin/bash
# Put the signing key and certificate where mkosi looks for them (mkosi.key,
# mkosi.crt next to mkosi.conf; both in .gitignore, never committed).
#
# From the repository secrets SWARF_SIGNING_KEY and SWARF_SIGNING_CERT when
# they are set: throw-away keys made for this test bench with `mkosi genkey`,
# replaced by the real keys when hosting is decided (SPEC O-5).
# Without them (a pull request from a fork, or before the secrets exist), a
# key is made for this run only, so the signing path is still tested; a push
# to main refuses that, since a key made per build proves nothing (SPEC section 7).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${SIGNING_KEY:-}" && -n "${SIGNING_CERT:-}" ]]; then
    (umask 077; printf '%s\n' "$SIGNING_KEY" >mkosi.key)
    printf '%s\n' "$SIGNING_CERT" >mkosi.crt
    # The key must match the certificate, or every signature check fails later.
    if ! cmp -s <(openssl pkey -in mkosi.key -pubout) <(openssl x509 -in mkosi.crt -noout -pubkey); then
        echo "ERROR: SWARF_SIGNING_KEY does not match SWARF_SIGNING_CERT"
        exit 1
    fi
    echo "OK: signing keys from repository secrets ($(openssl x509 -in mkosi.crt -noout -subject -enddate | tr '\n' ' '))"
elif [[ "${ON_MAIN:-false}" == true ]]; then
    echo "ERROR: secrets SWARF_SIGNING_KEY and SWARF_SIGNING_CERT are not set; main is only built with them"
    exit 1
else
    mkdir -p logs
    mkosi --genkey-common-name="swarf CI run key (no secret)" --genkey-valid-days=2 genkey >logs/genkey.log 2>&1
    echo "::warning::SWARF_SIGNING_KEY/SWARF_SIGNING_CERT not available: signed with a key made for this run only"
fi
