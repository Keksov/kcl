#!/bin/bash
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

kt_test_start "TFILE_USE_CP is readonly and re-sourcing is guarded"
if (TFILE_USE_CP="x") 2>/dev/null; then
    kt_test_fail "TFILE_USE_CP is readonly (write unexpectedly succeeded)"
elif source "$TFILE_DIR/tfile.sh" 2>/dev/null && [[ "$(tfile.exists /)" =~ ^(true|false)$ ]]; then
    kt_test_pass "TFILE_USE_CP is readonly and re-sourcing is guarded"
else
    kt_test_fail "re-sourcing tfile.sh failed or broke the class"
fi