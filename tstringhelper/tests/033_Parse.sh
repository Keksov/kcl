#!/bin/bash
# Parse
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Parse" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Parse integer
kk_test_start "Parse - integer"
result=$(string.parse 42)
if [[ "$result" == "42" ]]; then
    kk_test_pass "Parse - integer"
else
    kk_test_fail "Parse - integer (expected: '42', got: '$result')"
fi

# Test 2: Parse zero
kk_test_start "Parse - zero"
result=$(string.parse 0)
if [[ "$result" == "0" ]]; then
    kk_test_pass "Parse - zero"
else
    kk_test_fail "Parse - zero (expected: '0', got: '$result')"
fi

# Test 3: Parse negative integer
kk_test_start "Parse - negative integer"
result=$(string.parse -123)
if [[ "$result" == "-123" ]]; then
    kk_test_pass "Parse - negative integer"
else
    kk_test_fail "Parse - negative integer (expected: '-123', got: '$result')"
fi

# Test 4: Parse boolean true
kk_test_start "Parse - boolean true"
result=$(string.parse "true")
if [[ "$result" == "true" || "$result" == "True" ]]; then
    kk_test_pass "Parse - boolean true"
else
    kk_test_fail "Parse - boolean true (expected: 'true' or 'True', got: '$result')"
fi

# Test 5: Parse boolean false
kk_test_start "Parse - boolean false"
result=$(string.parse "false")
if [[ "$result" == "false" || "$result" == "False" ]]; then
    kk_test_pass "Parse - boolean false"
else
    kk_test_fail "Parse - boolean false (expected: 'false' or 'False', got: '$result')"
fi

# Test 6: Parse floating point
kk_test_start "Parse - floating point"
result=$(string.parse 3.14)
if [[ "$result" == "3.14" ]]; then
    kk_test_pass "Parse - floating point"
else
    kk_test_fail "Parse - floating point (expected: '3.14', got: '$result')"
fi

# Test 7: Parse scientific notation
kk_test_start "Parse - scientific notation"
result=$(string.parse 1.23e-4)
if [[ "$result" == *"1.23"* ]]; then
    kk_test_pass "Parse - scientific notation"
else
    kk_test_fail "Parse - scientific notation (expected: contains '1.23', got: '$result')"
fi

# Test 8: Parse large integer
kk_test_start "Parse - large integer"
result=$(string.parse 9223372036854775807)
if [[ "$result" == "9223372036854775807" ]]; then
    kk_test_pass "Parse - large integer"
else
    kk_test_fail "Parse - large integer (expected: '9223372036854775807', got: '$result')"
fi

# Test 9: Parse Int64
kk_test_start "Parse - Int64"
result=$(string.parse 1234567890)
if [[ "$result" == "1234567890" ]]; then
    kk_test_pass "Parse - Int64"
else
    kk_test_fail "Parse - Int64 (expected: '1234567890', got: '$result')"
fi

# Test 10: Parse negative float
kk_test_start "Parse - negative float"
result=$(string.parse -2.718)
if [[ "$result" == "-2.718" ]]; then
    kk_test_pass "Parse - negative float"
else
    kk_test_fail "Parse - negative float (expected: '-2.718', got: '$result')"
fi
