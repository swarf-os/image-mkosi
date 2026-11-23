#!/bin/bash
# Build the image. Full log in logs/build.log; prints OK or the useful errors.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
log=logs/build.log

if mkosi --force build >"$log" 2>&1; then
    echo "OK: build ($(ls mkosi.output/*.raw 2>/dev/null | head -1))"
else
    echo "ERROR: build failed, last lines of $log:"
    tail -n 40 "$log"
    exit 1
fi
