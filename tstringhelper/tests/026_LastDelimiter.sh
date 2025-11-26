#!/bin/bash
# LastDelimiter
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "LastDelimiter" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Find last delimiter
kk_test_start "LastDelimiter - find last"
result=$(string.lastDelimiter "hello,world,test" ",")
if [[ "$result" == "11" ]]; then
    kk_test_pass "LastDelimiter - find last"
else
    kk_test_fail "LastDelimiter - find last (expected: 11, got: '$result')"
fi

# Test 2: Single delimiter
kk_test_start "LastDelimiter - single delimiter"
result=$(string.lastDelimiter "hello,world" ",")
if [[ "$result" == "5" ]]; then
    kk_test_pass "LastDelimiter - single delimiter"
else
    kk_test_fail "LastDelimiter - single delimiter (expected: 5, got: '$result')"
fi

# Test 3: No delimiter found
kk_test_start "LastDelimiter - no delimiter"
result=$(string.lastDelimiter "hello" ",")
if [[ "$result" == "0" || "$result" == "-1" ]]; then
    kk_test_pass "LastDelimiter - no delimiter"
else
    kk_test_fail "LastDelimiter - no delimiter (expected: 0 or -1, got: '$result')"
fi

# Test 4: Delimiter at end
kk_test_start "LastDelimiter - delimiter at end"
result=$(string.lastDelimiter "hello," ",")
if [[ "$result" == "5" ]]; then
    kk_test_pass "LastDelimiter - delimiter at end"
else
    kk_test_fail "LastDelimiter - delimiter at end (expected: 5, got: '$result')"
fi

# Test 5: Delimiter at start
kk_test_start "LastDelimiter - delimiter at start"
result=$(string.lastDelimiter ",hello" ",")
if [[ "$result" == "0" ]]; then
    kk_test_pass "LastDelimiter - delimiter at start"
else
    kk_test_fail "LastDelimiter - delimiter at start (expected: 0, got: '$result')"
fi

# Test 6: Multiple delimiters mixed
kk_test_start "LastDelimiter - multiple delimiters"
result=$(string.lastDelimiter "path/to/file.txt" "/")
if [[ "$result" == "7" ]]; then
    kk_test_pass "LastDelimiter - multiple delimiters"
else
    kk_test_fail "LastDelimiter - multiple delimiters (expected: 7, got: '$result')"
fi

# Test 7: Space delimiter
kk_test_start "LastDelimiter - space delimiter"
result=$(string.lastDelimiter "hello world test" " ")
if [[ "$result" == "11" ]]; then
    kk_test_pass "LastDelimiter - space delimiter"
else
    kk_test_fail "LastDelimiter - space delimiter (expected: 11, got: '$result')"
fi

# Test 8: Multiple character options
kk_test_start "LastDelimiter - multiple character options"
result=$(string.lastDelimiter "hello,world;test" ",;")
if [[ "$result" == "11" ]]; then
    kk_test_pass "LastDelimiter - multiple character options"
else
    kk_test_fail "LastDelimiter - multiple character options (expected: 11, got: '$result')"
fi

# Test 9: Single character string
kk_test_start "LastDelimiter - single character"
result=$(string.lastDelimiter "a" "a")
if [[ "$result" == "0" ]]; then
    kk_test_pass "LastDelimiter - single character"
else
    kk_test_fail "LastDelimiter - single character (expected: 0, got: '$result')"
fi

# Test 10: Colon delimiter
kk_test_start "LastDelimiter - colon delimiter"
result=$(string.lastDelimiter "host:port:extra" ":")
if [[ "$result" == "9" ]]; then
    kk_test_pass "LastDelimiter - colon delimiter"
else
    kk_test_fail "LastDelimiter - colon delimiter (expected: 9, got: '$result')"
fi

# Test 11: Delimiter set includes last char
kk_test_start "LastDelimiter - last is delimiter"
result=$(string.lastDelimiter "hello." ".")
if [[ "$result" == "5" ]]; then
    kk_test_pass "LastDelimiter - last is delimiter"
else
    kk_test_fail "LastDelimiter - last is delimiter (expected: 5, got: '$result')"
fi

# Test 12: Empty delimiter set
kk_test_start "LastDelimiter - empty delimiter"
result=$(string.lastDelimiter "hello" "")
if [[ "$result" == "0" || "$result" == "-1" ]]; then
    kk_test_pass "LastDelimiter - empty delimiter"
else
    kk_test_fail "LastDelimiter - empty delimiter (expected: 0 or -1, got: '$result')"
fi
