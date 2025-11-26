#!/bin/bash
# Insert
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Insert" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Insert at start
kk_test_start "Insert - at start"
result=$(string.insert "world" 0 "hello ")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "Insert - at start"
else
    kk_test_fail "Insert - at start (expected: 'hello world', got: '$result')"
fi

# Test 2: Insert in middle
kk_test_start "Insert - in middle"
result=$(string.insert "heo" 2 "ll")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Insert - in middle"
else
    kk_test_fail "Insert - in middle (expected: 'hello', got: '$result')"
fi

# Test 3: Insert at end
kk_test_start "Insert - at end"
result=$(string.insert "hello" 5 " world")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "Insert - at end"
else
    kk_test_fail "Insert - at end (expected: 'hello world', got: '$result')"
fi

# Test 4: Insert empty string
kk_test_start "Insert - empty string"
result=$(string.insert "hello" 2 "")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Insert - empty string"
else
    kk_test_fail "Insert - empty string (expected: 'hello', got: '$result')"
fi

# Test 5: Insert into empty string
kk_test_start "Insert - into empty string"
result=$(string.insert "" 0 "hello")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Insert - into empty string"
else
    kk_test_fail "Insert - into empty string (expected: 'hello', got: '$result')"
fi

# Test 6: Insert multiple characters
kk_test_start "Insert - multiple characters"
result=$(string.insert "heo" 2 "lll")
if [[ "$result" == "helllo" ]]; then
    kk_test_pass "Insert - multiple characters"
else
    kk_test_fail "Insert - multiple characters (expected: 'hellloeo', got: '$result')"
fi

# Test 7: Insert with spaces
kk_test_start "Insert - with spaces"
result=$(string.insert "hello world" 5 "  ")
if [[ "$result" == "hello   world" ]]; then
    kk_test_pass "Insert - with spaces"
else
    kk_test_fail "Insert - with spaces (expected: 'hello   world', got: '$result')"
fi

# Test 8: Insert special characters
kk_test_start "Insert - special characters"
result=$(string.insert "hello@" 5 ".")
if [[ "$result" == "hello.@" ]]; then
    kk_test_pass "Insert - special characters"
else
    kk_test_fail "Insert - special characters (expected: 'hello.@', got: '$result')"
fi

# Test 9: Insert numeric string
kk_test_start "Insert - numeric string"
result=$(string.insert "123" 1 "00")
if [[ "$result" == "10023" ]]; then
    kk_test_pass "Insert - numeric string"
else
    kk_test_fail "Insert - numeric string (expected: '10023', got: '$result')"
fi

# Test 10: Insert at position equal to length
kk_test_start "Insert - at position equal to length"
result=$(string.insert "test" 4 "ing")
if [[ "$result" == "testing" ]]; then
    kk_test_pass "Insert - at position equal to length"
else
    kk_test_fail "Insert - at position equal to length (expected: 'testing', got: '$result')"
fi

# Test 11: Insert long string
kk_test_start "Insert - long string insertion"
result=$(string.insert "beginning end" 10 "middle ")
if [[ "$result" == "beginning middle end" ]]; then
    kk_test_pass "Insert - long string insertion"
else
    kk_test_fail "Insert - long string insertion (expected: 'beginning middle end', got: '$result')"
fi

# Test 12: Single character insertion
kk_test_start "Insert - single character"
result=$(string.insert "hllo" 1 "e")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Insert - single character"
else
    kk_test_fail "Insert - single character (expected: 'hello', got: '$result')"
fi
