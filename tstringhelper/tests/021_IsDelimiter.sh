#!/bin/bash
# IsDelimiter
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IsDelimiter" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Character is a delimiter
kt_test_start "IsDelimiter - character is delimiter"
result=$(string.isDelimiter "is" 5 " ")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsDelimiter - character is delimiter"
else
    kt_test_fail "IsDelimiter - character is delimiter (expected: true, got: '$result')"
fi

# Test 2: Character is not a delimiter
kt_test_start "IsDelimiter - character is not delimiter"
result=$(string.isDelimiter "is" 0 " ")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsDelimiter - character is not delimiter"
else
    kt_test_fail "IsDelimiter - character is not delimiter (expected: false, got: '$result')"
fi

# Test 3: Multiple delimiter options
kt_test_start "IsDelimiter - multiple delimiters"
result=$(string.isDelimiter "hello,world" 5 ",;:")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - multiple delimiters"
else
    kt_test_fail "IsDelimiter - multiple delimiters (expected: true, got: '$result')"
fi

# Test 4: Space is delimiter
kt_test_start "IsDelimiter - space is delimiter"
result=$(string.isDelimiter "hello world" 5 " ")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - space is delimiter"
else
    kt_test_fail "IsDelimiter - space is delimiter (expected: true, got: '$result')"
fi

# Test 5: Comma is delimiter
kt_test_start "IsDelimiter - comma is delimiter"
result=$(string.isDelimiter "a,b,c" 1 ",")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - comma is delimiter"
else
    kt_test_fail "IsDelimiter - comma is delimiter (expected: true, got: '$result')"
fi

# Test 6: Character at start
kt_test_start "IsDelimiter - character at start"
result=$(string.isDelimiter "This is a string" 0 "T")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - character at start"
else
    kt_test_fail "IsDelimiter - character at start (expected: true, got: '$result')"
fi

# Test 7: Character at end
kt_test_start "IsDelimiter - character at end"
result=$(string.isDelimiter "test." 4 ".")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - character at end"
else
    kt_test_fail "IsDelimiter - character at end (expected: true, got: '$result')"
fi

# Test 8: Semicolon as delimiter
kt_test_start "IsDelimiter - semicolon as delimiter"
result=$(string.isDelimiter "a;b;c" 1 ";")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - semicolon as delimiter"
else
    kt_test_fail "IsDelimiter - semicolon as delimiter (expected: true, got: '$result')"
fi

# Test 9: Tab as delimiter
kt_test_start "IsDelimiter - tab as delimiter"
result=$(string.isDelimiter "hello	world" 5 "	")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - tab as delimiter"
else
    kt_test_fail "IsDelimiter - tab as delimiter (expected: true, got: '$result')"
fi

# Test 10: Colon as delimiter
kt_test_start "IsDelimiter - colon as delimiter"
result=$(string.isDelimiter "host:port" 4 ":")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsDelimiter - colon as delimiter"
else
    kt_test_fail "IsDelimiter - colon as delimiter (expected: true, got: '$result')"
fi

# Test 11: Character not in delimiter set
kt_test_start "IsDelimiter - character not in set"
result=$(string.isDelimiter "hello" 1 ",;:")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsDelimiter - character not in set"
else
    kt_test_fail "IsDelimiter - character not in set (expected: false, got: '$result')"
fi

# Test 12: Empty delimiter set
kt_test_start "IsDelimiter - empty delimiter set"
result=$(string.isDelimiter "hello" 1 "")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsDelimiter - empty delimiter set"
else
    kt_test_fail "IsDelimiter - empty delimiter set (expected: false, got: '$result')"
fi
