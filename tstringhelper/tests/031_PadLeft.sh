#!/bin/bash
# PadLeft
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "PadLeft" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Pad to wider width
kt_test_start "PadLeft - pad with spaces"
result=$(string.padLeft "hello" 10)
if [[ "$result" == "     hello" ]]; then
    kt_test_pass "PadLeft - pad with spaces"
else
    kt_test_fail "PadLeft - pad with spaces (expected: '     hello', got: '$result')"
fi

# Test 2: String already at width
kt_test_start "PadLeft - already at width"
result=$(string.padLeft "hello" 5)
if [[ "$result" == "hello" ]]; then
    kt_test_pass "PadLeft - already at width"
else
    kt_test_fail "PadLeft - already at width (expected: 'hello', got: '$result')"
fi

# Test 3: String longer than width
kt_test_start "PadLeft - longer than width"
result=$(string.padLeft "hello world" 5)
if [[ "$result" == "hello world" ]]; then
    kt_test_pass "PadLeft - longer than width"
else
    kt_test_fail "PadLeft - longer than width (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string padding
kt_test_start "PadLeft - empty string"
result=$(string.padLeft "" 5)
if [[ "$result" == "     " ]]; then
    kt_test_pass "PadLeft - empty string"
else
    kt_test_fail "PadLeft - empty string (expected: '     ', got: '$result')"
fi

# Test 5: Custom padding character
kt_test_start "PadLeft - custom character"
result=$(string.padLeft "42" 5 "*")
if [[ "$result" == "***42" ]]; then
    kt_test_pass "PadLeft - custom character"
else
    kt_test_fail "PadLeft - custom character (expected: '***42', got: '$result')"
fi

# Test 6: Pad with zero
kt_test_start "PadLeft - pad with zero"
result=$(string.padLeft "123" 6 "0")
if [[ "$result" == "000123" ]]; then
    kt_test_pass "PadLeft - pad with zero"
else
    kt_test_fail "PadLeft - pad with zero (expected: '000123', got: '$result')"
fi

# Test 7: Single character padding
kt_test_start "PadLeft - single character"
result=$(string.padLeft "x" 4 "-")
if [[ "$result" == "---x" ]]; then
    kt_test_pass "PadLeft - single character"
else
    kt_test_fail "PadLeft - single character (expected: '---x', got: '$result')"
fi

# Test 8: Width of 1
kt_test_start "PadLeft - width of 1"
result=$(string.padLeft "a" 1)
if [[ "$result" == "a" ]]; then
    kt_test_pass "PadLeft - width of 1"
else
    kt_test_fail "PadLeft - width of 1 (expected: 'a', got: '$result')"
fi

# Test 9: Large padding
kt_test_start "PadLeft - large padding"
result=$(string.padLeft "a" 10 "+")
if [[ "$result" == "+++++++++a" ]]; then
    kt_test_pass "PadLeft - large padding"
else
    kt_test_fail "PadLeft - large padding (expected: '+++++++++a', got: '$result')"
fi

# Test 10: Dot character padding
kt_test_start "PadLeft - dot padding"
result=$(string.padLeft "test" 8 ".")
if [[ "$result" == "....test" ]]; then
    kt_test_pass "PadLeft - dot padding"
else
    kt_test_fail "PadLeft - dot padding (expected: '....test', got: '$result')"
fi
