#!/usr/bin/env bash
# Kklass static compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KklassStaticCompatibility" "$SCRIPT_DIR" "$@"

TFILE_DIR="$SCRIPT_DIR/.."
[[ -f "$TFILE_DIR/tfile.sh" ]] && source "$TFILE_DIR/tfile.sh"

kt_test_start "TFile methods are registered as kklass static methods"
expected_methods=(exists copy readAllText writeAllBytes integerToFileAttributes)
missing_methods=()

for expected_method in "${expected_methods[@]}"; do
    found=false
    for registered_method in "${tfile_class_static_methods[@]}"; do
        if [[ "$registered_method" == "$expected_method" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != "true" ]]; then
        missing_methods+=("$expected_method")
    fi
done

if (( ${#tfile_class_static_methods[@]} > 0 && ${#missing_methods[@]} == 0 )); then
    kt_test_pass "TFile methods are registered as kklass static methods"
else
    kt_test_fail "TFile kklass metadata missing methods: ${missing_methods[*]:-(none)}; registered count: ${#tfile_class_static_methods[@]}"
fi

kt_test_start "TFile public methods preserve failure status after kklass registration"
if tfile.copy "$SCRIPT_DIR/.tmp/no-source-file" "$SCRIPT_DIR/.tmp/no-dest-file" >/dev/null 2>&1; then
    kt_test_fail "TFile public methods preserve failure status after kklass registration"
else
    kt_test_pass "TFile public methods preserve failure status after kklass registration"
fi

# Regression (Pascal DSL port): a fall-through failure — the body's last command
# fails without an explicit `return` — must reach the caller. The thin static
# dispatcher used to clobber this status with 0 (kklass/tests/114 covers the
# core mechanism; this pins the tfile-level symptom).
kt_test_start "TFile fall-through failure status reaches the caller"
if tfile.getCreationTime "/nonexistent_tfile_dsl_$$" >/dev/null 2>&1; then
    kt_test_fail "TFile fall-through failure status reaches the caller (got 0, want non-zero)"
else
    kt_test_pass "TFile fall-through failure status reaches the caller"
fi

# Perf contract: tfile has NO static vars, so its dispatchers must stay thin —
# no funsub / scratch-file capture on any bash (see the header note in tfile.sh).
kt_test_start "TFile dispatchers are thin (no capture overhead)"
decl="$(declare -f tfile.exists)"
if [[ "$decl" == *"__kk_static_out"* || "$decl" == *'REPLY=${'* ]]; then
    kt_test_fail "TFile dispatchers are thin (capturing dispatcher found — a static var was added?)"
else
    kt_test_pass "TFile dispatchers are thin (no capture overhead)"
fi

# (image I1b: TFILE_USE_CP is set by the settings hook tfile._settings and is
# no longer readonly — a load image re-runs hooks after putting their
# variables back, which readonly forbids; a readonly value is kept)
kt_test_start "TFILE_USE_CP is set by the settings hook (true/false) and re-sourcing is guarded"
if [[ "$TFILE_USE_CP" =~ ^(true|false)$ ]] && source "$TFILE_DIR/tfile.sh" 2>/dev/null \
   && [[ "$(tfile.exists /)" =~ ^(true|false)$ ]]; then
    kt_test_pass "TFILE_USE_CP=$TFILE_USE_CP, re-source clean"
else
    kt_test_fail "TFILE_USE_CP='${TFILE_USE_CP-<unset>}' or re-sourcing tfile.sh failed or broke the class"
fi

kt_test_start "under set -eu: kk.unit --forget tfile + a re-source recomputes TFILE_USE_CP; a value made readonly before the load is kept, and its reload does not fail"
if ! kt_need_timeout; then kt_test_pass "SKIP: $KT_TIMEOUT_WHY"
else
out="$("$KT_TIMEOUT" -k 5 60 "$BASH" -c '
set -eu
source "$1/tfile.sh"
a=$TFILE_USE_CP
TFILE_USE_CP=stale
kk.unit --forget tfile
source "$1/tfile.sh"
b=$TFILE_USE_CP
kk.unit --forget tfile
readonly TFILE_USE_CP=false
source "$1/tfile.sh"
kk.unit --forget tfile
source "$1/tfile.sh"
tfile.exists "$1/tfile.sh"
printf "%s|%s|%s|%s" "$a" "$b" "$TFILE_USE_CP" "$RESULT"' _ "$TFILE_DIR" 2>&1 </dev/null)"; rc=$?
if [[ $rc -eq 0 && "$out" =~ ^(true|false)\|(true|false)\|false\|true$ && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "rc=$rc out='$out'"
fi
fi   # kt_need_timeout