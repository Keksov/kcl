#!/bin/bash
# CopyTo
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CopyTo" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Copy substring into destination array
kt_test_start "CopyTo - substring into destination array"
destination=(x x x x x)
output_file="$(mktemp)"
string.copyTo "abcdef" 2 destination 1 3 > "$output_file"
status=$?
output="$(<"$output_file")"
rm -f "$output_file"
result="${destination[*]}"
if [[ $status -eq 0 && "$output" == "" && "$result" == "x c d e x" ]]; then
    kt_test_pass "CopyTo - substring into destination array"
else
    kt_test_fail "CopyTo - substring into destination array (expected destination: 'x c d e x' and no output, got destination: '$result', output: '$output', status: $status)"
fi
