#!/bin/bash
# PadLeft
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "PadLeft" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Pad to wider width
kk_test_start "PadLeft - pad with spaces"
result=$(string.padLeft "hello" 10)
if [[ "$result" == "     hello" ]]; then
    kk_test_pass "PadLeft - pad with spaces"
else
    kk_test_fail "PadLeft - pad with spaces (expected: '     hello', got: '$result')"
fi

# Test 2: String already at width
kk_test_start "PadLeft - already at width"
result=$(string.padLeft "hello" 5)
if [[ "$result" == "hello" ]]; then
    kk_test_pass "PadLeft - already at width"
else
    kk_test_fail "PadLeft - already at width (expected: 'hello', got: '$result')"
fi

# Test 3: String longer than width
kk_test_start "PadLeft - longer than width"
result=$(string.padLeft "hello world" 5)
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "PadLeft - longer than width"
else
    kk_test_fail "PadLeft - longer than width (expected: 'hello world', got: '$result')"
fi

# Test 4: Empty string padding
kk_test_start "PadLeft - empty string"
result=$(string.padLeft "" 5)
if [[ "$result" == "     " ]]; then
    kk_test_pass "PadLeft - empty string"
else
    kk_test_fail "PadLeft - empty string (expected: '     ', got: '$result')"
fi

# Test 5: Custom padding character
kk_test_start "PadLeft - custom character"
result=$(string.padLeft "42" 5 "*")
if [[ "$result" == "***42" ]]; then
    kk_test_pass "PadLeft - custom character"
else
    kk_test_fail "PadLeft - custom character (expected: '***42', got: '$result')"
fi

# Test 6: Pad with zero
kk_test_start "PadLeft - pad with zero"
result=$(string.padLeft "123" 6 "0")
if [[ "$result" == "000123" ]]; then
    kk_test_pass "PadLeft - pad with zero"
else
    kk_test_fail "PadLeft - pad with zero (expected: '000123', got: '$result')"
fi

# Test 7: Single character padding
kk_test_start "PadLeft - single character"
result=$(string.padLeft "x" 4 "-")
if [[ "$result" == "---x" ]]; then
    kk_test_pass "PadLeft - single character"
else
    kk_test_fail "PadLeft - single character (expected: '---x', got: '$result')"
fi

# Test 8: Width of 1
kk_test_start "PadLeft - width of 1"
result=$(string.padLeft "a" 1)
if [[ "$result" == "a" ]]; then
    kk_test_pass "PadLeft - width of 1"
else
    kk_test_fail "PadLeft - width of 1 (expected: 'a', got: '$result')"
fi

# Test 9: Large padding
kk_test_start "PadLeft - large padding"
result=$(string.padLeft "a" 10 "+")
if [[ "$result" == "+++++++++a" ]]; then
    kk_test_pass "PadLeft - large padding"
else
    kk_test_fail "PadLeft - large padding (expected: '+++++++++a', got: '$result')"
fi

# Test 10: Dot character padding
kk_test_start "PadLeft - dot padding"
result=$(string.padLeft "test" 8 ".")
if [[ "$result" == "....test" ]]; then
    kk_test_pass "PadLeft - dot padding"
else
    kk_test_fail "PadLeft - dot padding (expected: '....test', got: '$result')"
fi
