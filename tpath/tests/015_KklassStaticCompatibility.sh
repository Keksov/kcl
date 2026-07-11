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

# The getter methods are the PUBLIC API for the constants; the backing
# __TPATH_* globals are readonly so no other library can overwrite them.
kt_test_start "constant getters return the readonly __TPATH_* values"
if [[ "$(tpath.getDirectorySeparatorChar)" == "$__TPATH_DIRECTORY_SEPARATOR_CHAR" \
   && "$(tpath.getAltDirectorySeparatorChar)" == "$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR" \
   && "$(tpath.getPathSeparator)" == "$__TPATH_PATH_SEPARATOR" \
   && "$(tpath.getVolumeSeparatorChar)" == "$__TPATH_VOLUME_SEPARATOR_CHAR" \
   && "$(tpath.getExtensionSeparatorChar)" == "$__TPATH_EXTENSION_SEPARATOR_CHAR" ]]; then
    kt_test_pass "constant getters return the readonly __TPATH_* values"
else
    kt_test_fail "constant getters mismatch the __TPATH_* globals"
fi

kt_test_start "tpath constants are readonly (writes fail loudly)"
if (__TPATH_DIRECTORY_SEPARATOR_CHAR="x") 2>/dev/null; then
    kt_test_fail "tpath constants are readonly (write unexpectedly succeeded)"
else
    kt_test_pass "tpath constants are readonly (writes fail loudly)"
fi

kt_test_start "re-sourcing tpath.sh is safe (guard skips readonly re-assignment)"
if source "$TPATH_DIR/tpath.sh" 2>/dev/null && [[ "$(tpath.getExtensionSeparatorChar)" == "." ]]; then
    kt_test_pass "re-sourcing tpath.sh is safe (guard skips readonly re-assignment)"
else
    kt_test_fail "re-sourcing tpath.sh failed or broke the class"
fi