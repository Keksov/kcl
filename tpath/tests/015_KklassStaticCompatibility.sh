#!/bin/bash
# Kklass static compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "KklassStaticCompatibility" "$SCRIPT_DIR" "$@"

TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"

kt_test_start "TPath methods are registered as kklass static methods"
expected_methods=(combine getFileName getDirectorySeparatorChar getAttributes matchesPattern)
missing_methods=()

for expected_method in "${expected_methods[@]}"; do
    found=false
    for registered_method in "${tpath_class_static_methods[@]}"; do
        if [[ "$registered_method" == "$expected_method" ]]; then
            found=true
            break
        fi
    done

    if [[ "$found" != "true" ]]; then
        missing_methods+=("$expected_method")
    fi
done

if (( ${#tpath_class_static_methods[@]} > 0 && ${#missing_methods[@]} == 0 )); then
    kt_test_pass "TPath methods are registered as kklass static methods"
else
    kt_test_fail "TPath kklass metadata missing methods: ${missing_methods[*]:-(none)}; registered count: ${#tpath_class_static_methods[@]}"
fi