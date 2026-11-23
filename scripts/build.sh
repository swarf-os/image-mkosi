#!/bin/bash
# Build the image. Full log in logs/build.log; prints OK or the useful errors.
#
# Packages are kept in mkosi.pkgcache/ (picked up by mkosi automatically),
# repository metadata in mkosi.cache/*.metadata.cache (CacheDirectory=), the
# tools tree in mkosi.tools/. The CI keeps both
# between runs. Our packages come from a fixed Arch Linux Archive date, so
# cached metadata never goes stale: once it exists, later tries skip the
# metadata sync (--cache-only=metadata), which is what the archive keeps
# timing out on.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs mkosi.pkgcache
log=logs/build.log
: >"$log"

build() { mkosi "$@" --force build >>"$log" 2>&1; }

ok=0
for try in 1 2 3; do
    args=()
    if compgen -G 'mkosi.cache/*.metadata.cache' >/dev/null; then
        args=(--cache-only=metadata)
    fi
    echo "try $try: mkosi ${args[*]} build" >>"$log"
    if build "${args[@]}"; then ok=1; break; fi
    # Cached metadata missing or incomplete: let the next try sync it.
    if tail -n 30 "$log" | grep -q 'failed retrieving file\|failed to synchronize'; then
        sleep 30
        continue
    fi
    break
done

if [[ $ok -eq 1 ]]; then
    echo "OK: build ($(ls mkosi.output/*.raw 2>/dev/null | head -1))"
else
    echo "ERROR: build failed, last lines of $log:"
    tail -n 40 "$log"
    exit 1
fi
