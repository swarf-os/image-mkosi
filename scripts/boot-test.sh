#!/bin/bash
# Boot the built image in a VM (qemu, KVM) with the test-only credentials in
# tests/credentials/, then check what the guest printed on its console.
# Full log in logs/boot.log; prints OK or the useful errors.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
log=logs/boot.log
timeout_s="${BOOT_TIMEOUT:-900}"

timeout --foreground "$timeout_s" \
    mkosi --credential="$PWD/tests/credentials" --console=read-only vm >"$log" 2>&1 </dev/null
rc=$?
# Strip terminal control sequences so the checks below see plain text.
sed -i -e 's/\x1b\[[0-9;?:]*[A-Za-z]//g' -e 's/\r//g' "$log"

errors=()
[[ $rc -eq 124 ]] && errors+=("VM did not power off within ${timeout_s}s")
grep -q 'CI-CHECK-END' "$log" || errors+=("check unit did not finish (no CI-CHECK-END)")

field() { sed -n "s/^.*CI-OSREL: $1=//p" "$log" | head -1 | tr -d '"'; }
[[ "$(field ID)" == swarf ]]          || errors+=("os-release ID is '$(field ID)', expected swarf")
[[ "$(field NAME)" == swarf ]]        || errors+=("os-release NAME is '$(field NAME)', expected swarf")
[[ "$(field PRETTY_NAME)" == swarf* ]] || errors+=("os-release PRETTY_NAME is '$(field PRETTY_NAME)'")

# /etc/issue may name swarf or print PRETTY_NAME from os-release (\S{PRETTY_NAME}).
grep -q -E 'CI-ISSUE: (swarf|\\S\{PRETTY_NAME\})' "$log" || errors+=("/etc/issue names neither swarf nor PRETTY_NAME")
grep -q 'CI-BOOT-TITLE: ' "$log" || errors+=("no boot entry title found")

# Criterion 6: only our name in os-release, issue and boot entries.
if grep -E 'CI-(OSREL|ISSUE|BOOT-TITLE): ' "$log" | grep -v '^.*CI-OSREL: ID_LIKE=' | grep -qi 'arch'; then
    errors+=("upstream name left in identity: $(grep -E 'CI-(OSREL|ISSUE|BOOT-TITLE): ' "$log" | grep -v 'ID_LIKE=' | grep -i arch | head -3 | tr '\n' ' ')")
fi
grep -q 'CI-BOOT-TITLE: .*swarf' "$log" || errors+=("boot entry title does not name swarf")

grep -q 'CI-HOSTNAME: swarf' "$log" || errors+=("hostname is not swarf: $(sed -n 's/^.*CI-HOSTNAME: //p' "$log" | head -1)")
grep -q 'CI-MOUNT: /usr .*erofs' "$log" || errors+=("/usr is not the EROFS partition")
grep -q 'CI-GETTY: active' "$log"     || errors+=("getty.target not active (no console login prompt)")
if grep -q 'CI-FAILED: ' "$log"; then
    errors+=("failed units: $(sed -n 's/^.*CI-FAILED: //p' "$log" | awk '{print $1}' | tr '\n' ' ')")
fi

if ((${#errors[@]})); then
    printf 'ERROR: %s\n' "${errors[@]}"
    echo "(full log: $log)"
    exit 1
fi
echo "OK: boot test ($(sed -n 's/^.*CI-OSREL: PRETTY_NAME=//p' "$log" | head -1 | tr -d '"'))"
