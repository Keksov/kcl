#!/bin/bash
# GetHashCode.sh - Test string.getHashCode method

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: Get hash code for string
test_start "GetHashCode - basic hash"
result=$(string.getHashCode "hello")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - basic hash"
else
    test_fail "GetHashCode - basic hash (expected: integer, got: '$result')"
fi

# Test 2: Equal strings produce equal hash codes
test_start "GetHashCode - equal strings same hash"
hash1=$(string.getHashCode "test")
hash2=$(string.getHashCode "test")
if [[ "$hash1" == "$hash2" ]]; then
    test_pass "GetHashCode - equal strings same hash"
else
    test_fail "GetHashCode - equal strings same hash (hash1: $hash1, hash2: $hash2)"
fi

# Test 3: Different strings may have different hash codes
test_start "GetHashCode - different strings"
hash1=$(string.getHashCode "apple")
hash2=$(string.getHashCode "banana")
if [[ "$hash1" != "$hash2" ]]; then
    test_pass "GetHashCode - different strings"
else
    test_fail "GetHashCode - different strings (both: $hash1)"
fi

# Test 4: Empty string hash code
test_start "GetHashCode - empty string"
result=$(string.getHashCode "")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - empty string"
else
    test_fail "GetHashCode - empty string (expected: integer, got: '$result')"
fi

# Test 5: Case-sensitive hashing (different case should give different hash)
test_start "GetHashCode - case sensitive"
hash1=$(string.getHashCode "Hello")
hash2=$(string.getHashCode "hello")
# In Sydney version, case-sensitive strings should have different hashes
if [[ "$hash1" != "$hash2" ]]; then
    test_pass "GetHashCode - case sensitive"
else
    test_fail "GetHashCode - case sensitive (both: $hash1)"
fi

# Test 6: String with spaces
test_start "GetHashCode - with spaces"
result=$(string.getHashCode "hello world")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - with spaces"
else
    test_fail "GetHashCode - with spaces (expected: integer, got: '$result')"
fi

# Test 7: Numeric string
test_start "GetHashCode - numeric string"
result=$(string.getHashCode "123456")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - numeric string"
else
    test_fail "GetHashCode - numeric string (expected: integer, got: '$result')"
fi

# Test 8: Special characters
test_start "GetHashCode - special characters"
result=$(string.getHashCode "hello@world#123")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - special characters"
else
    test_fail "GetHashCode - special characters (expected: integer, got: '$result')"
fi

# Test 9: Single character
test_start "GetHashCode - single character"
result=$(string.getHashCode "a")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - single character"
else
    test_fail "GetHashCode - single character (expected: integer, got: '$result')"
fi

# Test 10: Long string
test_start "GetHashCode - long string"
result=$(string.getHashCode "This is a very long string with many characters to test the hash code function")
if [[ -n "$result" && "$result" =~ ^[0-9-]+$ ]]; then
    test_pass "GetHashCode - long string"
else
    test_fail "GetHashCode - long string (expected: integer, got: '$result')"
fi
