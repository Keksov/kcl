#!/bin/bash
# Join
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Join" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Join two strings
kk_test_start "Join - two strings"
result=$(string.join "," "hello" "world")
if [[ "$result" == "hello,world" ]]; then
    kk_test_pass "Join - two strings"
else
    kk_test_fail "Join - two strings (expected: 'hello,world', got: '$result')"
fi

# Test 2: Join three strings
kk_test_start "Join - three strings"
result=$(string.join "-" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    kk_test_pass "Join - three strings"
else
    kk_test_fail "Join - three strings (expected: 'a-b-c', got: '$result')"
fi

# Test 3: Empty separator
kk_test_start "Join - empty separator"
result=$(string.join "" "hello" "world")
if [[ "$result" == "helloworld" ]]; then
    kk_test_pass "Join - empty separator"
else
    kk_test_fail "Join - empty separator (expected: 'helloworld', got: '$result')"
fi

# Test 4: Space separator
kk_test_start "Join - space separator"
result=$(string.join " " "hello" "world")
if [[ "$result" == "hello world" ]]; then
    kk_test_pass "Join - space separator"
else
    kk_test_fail "Join - space separator (expected: 'hello world', got: '$result')"
fi

# Test 5: Empty string in array
kk_test_start "Join - empty string in array"
result=$(string.join "," "hello" "" "world")
if [[ "$result" == "hello,,world" ]]; then
    kk_test_pass "Join - empty string in array"
else
    kk_test_fail "Join - empty string in array (expected: 'hello,,world', got: '$result')"
fi

# Test 6: Single string
kk_test_start "Join - single string"
result=$(string.join "," "hello")
if [[ "$result" == "hello" ]]; then
    kk_test_pass "Join - single string"
else
    kk_test_fail "Join - single string (expected: 'hello', got: '$result')"
fi

# Test 7: Numeric separator
kk_test_start "Join - numeric separator"
result=$(string.join "|" "one" "two" "three")
if [[ "$result" == "one|two|three" ]]; then
    kk_test_pass "Join - numeric separator"
else
    kk_test_fail "Join - numeric separator (expected: 'one|two|three', got: '$result')"
fi

# Test 8: Multiple character separator
kk_test_start "Join - multiple character separator"
result=$(string.join "::" "a" "b" "c")
if [[ "$result" == "a::b::c" ]]; then
    kk_test_pass "Join - multiple character separator"
else
    kk_test_fail "Join - multiple character separator (expected: 'a::b::c', got: '$result')"
fi

# Test 9: Join with numeric strings
kk_test_start "Join - numeric strings"
result=$(string.join "-" "1" "2" "3")
if [[ "$result" == "1-2-3" ]]; then
    kk_test_pass "Join - numeric strings"
else
    kk_test_fail "Join - numeric strings (expected: '1-2-3', got: '$result')"
fi

# Test 10: Join with special characters
kk_test_start "Join - special characters"
result=$(string.join "," "hello@" "world#" "test!")
if [[ "$result" == "hello@,world#,test!" ]]; then
    kk_test_pass "Join - special characters"
else
    kk_test_fail "Join - special characters (expected: 'hello@,world#,test!', got: '$result')"
fi

# Test 11: Join many strings
kk_test_start "Join - many strings"
result=$(string.join "," "a" "b" "c" "d" "e" "f")
if [[ "$result" == "a,b,c,d,e,f" ]]; then
    kk_test_pass "Join - many strings"
else
    kk_test_fail "Join - many strings (expected: 'a,b,c,d,e,f', got: '$result')"
fi

# Test 12: Separator with spaces
kk_test_start "Join - separator with spaces"
result=$(string.join " and " "hello" "world")
if [[ "$result" == "hello and world" ]]; then
    kk_test_pass "Join - separator with spaces"
else
    kk_test_fail "Join - separator with spaces (expected: 'hello and world', got: '$result')"
fi
