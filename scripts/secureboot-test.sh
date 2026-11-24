#!/bin/bash
# Secure Boot and signed /usr: tampered images must not boot (SPEC section 11,
# test 3 and criterion 5). Each case boots a modified copy of the built
# image (scripts/tamper.py) in the same VM as scripts/boot-test.sh: OVMF with
# Secure Boot in setup mode, so systemd-boot first enrolls our keys from the
# ESP, then must refuse what was changed. uki-control goes through the same
# copy path unchanged and must boot, so a refusal is not a broken harness.
# Logs in logs/secureboot-*.log; prints OK or the useful errors.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
timeout_s="${NEG_TIMEOUT:-180}"

shopt -s nullglob
images=(mkosi.output/swarf_*_x86-64.raw)
if ((${#images[@]} != 1)); then
    echo "ERROR: expected one disk image in mkosi.output/, found: ${images[*]:-none}"
    exit 1
fi
img="${images[0]}"
pristine="$img.pristine"
work="$(mktemp -d)"
mv "$img" "$pristine"
trap 'rm -f "$img"; mv "$pristine" "$img"; rm -rf "$work"' EXIT

errors=()
: >logs/secureboot.log
for case in uki-control uki-modified uki-other-key usr-modified usr-other-key; do
    log="logs/secureboot-$case.log"
    rm -f "$img"
    if ! what="$(mkosi box -- python3 scripts/tamper.py "$case" "$pristine" "$img" "$work" 2>"$log")"; then
        errors+=("$case: could not prepare the image: $(tail -n 3 "$log" | tr '\n' ' ')")
        continue
    fi
    echo "case $case: $what" >>"$log"
    timeout -k 15 "$timeout_s" \
        mkosi --credential="$PWD/tests/credentials" --console=read-only --ephemeral=yes vm >>"$log" 2>&1 </dev/null
    sed -i -e 's/\x1b\[[0-9;?:]*[A-Za-z]//g' -e 's/\r//g' "$log"

    booted=no
    grep -q 'CI-CHECK-END' "$log" && booted=yes
    evidence="$(grep -i -m 3 -E 'security violation|access denied|verity|corrupt|signature|image policy' "$log" | grep -v '^case ' | tr -s ' \n' ' ')"

    case "$case" in
        uki-control)
            [[ $booted == yes ]] || errors+=("$case: unchanged copy did not boot, the test harness is broken")
            grep -q 'CI-SECUREBOOT: enabled' "$log" || errors+=("$case: Secure Boot not enabled in the guest")
            ;;
        uki-*)
            [[ $booted == no ]] || errors+=("$case: booted, Secure Boot did not refuse the UKI")
            # Refused by the firmware: the kernel and the initrd never ran.
            grep -q 'Welcome to ' "$log" && errors+=("$case: the initrd started, the UKI was not refused by the firmware")
            ;;
        usr-*)
            [[ $booted == no ]] || errors+=("$case: booted, the changed /usr was not refused")
            ;;
    esac
    echo "$case: booted=$booted; ${evidence:-no refusal message on the console}" >>logs/secureboot.log
done

if ((${#errors[@]})); then
    printf 'ERROR: %s\n' "${errors[@]}"
    echo "(logs: logs/secureboot-*.log, summary in logs/secureboot.log)"
    exit 1
fi
echo "OK: Secure Boot tests (5 cases, see logs/secureboot.log)"
