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