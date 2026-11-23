#!/bin/bash
# Build the image. Full log in logs/build.log; prints OK or the useful errors.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
log=logs/build.log
: >"$log"

build() { mkosi --force build >>"$log" 2>&1; }

# One retry when the package mirror failed a download (the Arch Linux Archive
# is a single volunteer host); any other failure is reported at once.
if build; then
    ok=1
elif grep -q 'failed retrieving file' "$log"; then
    echo "retry: package download failed, building again" >>"$log"
    build && ok=1
fi

if [[ ${ok:-0} -eq 1 ]]; then
    echo "OK: build ($(ls mkosi.output/*.raw 2>/dev/null | head -1))"
else
    echo "ERROR: build failed, last lines of $log:"
    tail -n 40 "$log"
    exit 1
fi
