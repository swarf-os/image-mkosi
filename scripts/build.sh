#!/bin/bash
# Build the image. Full log in logs/build.log; prints OK or the useful errors.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
log=logs/build.log
: >"$log"

build() { mkosi --force build >>"$log" 2>&1; }

# Up to two retries when the package mirror failed a download (the Arch Linux
# Archive is a single volunteer host); any other failure is reported at once.
# Packages already downloaded stay in mkosi.cache, so each try gets further.
for try in 1 2 3; do
    if build; then ok=1; break; fi
    tail -n 30 "$log" | grep -q 'failed retrieving file\|failed to synchronize' || break
    echo "retry $try: package download failed, building again in 30s" >>"$log"
    sleep 30
done

if [[ ${ok:-0} -eq 1 ]]; then
    echo "OK: build ($(ls mkosi.output/*.raw 2>/dev/null | head -1))"
else
    echo "ERROR: build failed, last lines of $log:"
    tail -n 40 "$log"
    exit 1
fi
