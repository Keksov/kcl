#!/bin/bash
# QuotedString.sh - Test string.quotedString method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Quote simple string
test_start "QuotedString - simple quote"
result=$(string.quotedString "hello")
if [[ "$result" == "'hello'" ]]; then
    test_pass "QuotedString - simple quote"
else
    test_fail "QuotedString - simple quote (expected: ''hello'', got: '$result')"
fi

# Test 2: Quote with internal quotes
test_start "QuotedString - internal quotes"
result=$(string.quotedString "it's")
if [[ "$result" == "'it''s'" || "$result" == "\"it's\"" ]]; then
    test_pass "QuotedString - internal quotes"
else
    test_fail "QuotedString - internal quotes (expected: ''it''''s'' or \"it's\", got: '$result')"
fi

# Test 3: Custom quote character
test_start "QuotedString - custom quote character"
result=$(string.quotedString "hello" '"')
if [[ "$result" == "\"hello\"" ]]; then
    test_pass "QuotedString - custom quote character"
else
    test_fail "QuotedString - custom quote character (expected: \"hello\", got: '$result')"
fi

# Test 4: Empty string
test_start "QuotedString - empty string"
result=$(string.quotedString "")
if [[ "$result" == "''" ]]; then
    test_pass "QuotedString - empty string"
else
    test_fail "QuotedString - empty string (expected: '''', got: '$result')"
fi

# Test 5: Single quote with apostrophe
test_start "QuotedString - apostrophe doubling"
result=$(string.quotedString "don't")
if [[ "$result" == "'don''t'" || "$result" == "\"don't\"" ]]; then
    test_pass "QuotedString - apostrophe doubling"
else
    test_fail "QuotedString - apostrophe doubling (expected: ''don''''t'' or \"don't\", got: '$result')"
fi

# Test 6: Multiple quotes
test_start "QuotedString - multiple quotes"
result=$(string.quotedString "''")
if [[ "$result" == "''''" || "$result" == "''''''" ]]; then
    test_pass "QuotedString - multiple quotes"
else
    test_fail "QuotedString - multiple quotes (expected: '''''' or '''''', got: '$result')"
fi

# Test 7: Double quote character
test_start "QuotedString - double quote custom"
result=$(string.quotedString "test" '"')
if [[ "$result" == "\"test\"" ]]; then
    test_pass "QuotedString - double quote custom"
else
    test_fail "QuotedString - double quote custom (expected: \"test\", got: '$result')"
fi

# Test 8: With spaces
test_start "QuotedString - with spaces"
result=$(string.quotedString "hello world")
if [[ "$result" == "'hello world'" ]]; then
    test_pass "QuotedString - with spaces"
else
    test_fail "QuotedString - with spaces (expected: ''hello world'', got: '$result')"
fi

# Test 9: With special characters
test_start "QuotedString - special characters"
result=$(string.quotedString "test@#$")
if [[ "$result" == "'test@#\$'" ]]; then
    test_pass "QuotedString - special characters"
else
    test_fail "QuotedString - special characters (expected: ''test@#$'', got: '$result')"
fi

# Test 10: Numeric string
test_start "QuotedString - numeric string"
result=$(string.quotedString "12345")
if [[ "$result" == "'12345'" ]]; then
    test_pass "QuotedString - numeric string"
else
    test_fail "QuotedString - numeric string (expected: ''12345'', got: '$result')"
fi
