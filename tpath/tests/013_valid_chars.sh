#!/bin/bash
# 013_valid_chars.sh - Test TPath character validation methods

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
parse_args "$@"

# Test 1: HasValidFileNameChars - valid filename
test_start "HasValidFileNameChars with valid filename"
result=$(tpath.hasValidFileNameChars "valid_file.txt")
if [[ "$result" == "true" ]]; then
    test_pass "HasValidFileNameChars with valid filename"
else
    test_fail "HasValidFileNameChars with valid filename (expected: true, got: '$result')"
fi

# Test 2: HasValidFileNameChars - invalid filename with /
test_start "HasValidFileNameChars with invalid filename (/)"
result=$(tpath.hasValidFileNameChars "invalid/file.txt")
if [[ "$result" == "false" ]]; then
    test_pass "HasValidFileNameChars with invalid filename (/)"
else
    test_fail "HasValidFileNameChars with invalid filename (/) (expected: false, got: '$result')"
fi

# Test 3: HasValidFileNameChars - with wildcards allowed
test_start "HasValidFileNameChars with wildcards allowed"
result=$(tpath.hasValidFileNameChars "file*.txt" "true")
if [[ "$result" == "true" ]]; then
    test_pass "HasValidFileNameChars with wildcards allowed"
else
    test_fail "HasValidFileNameChars with wildcards allowed (expected: true, got: '$result')"
fi

# Test 4: HasValidFileNameChars - with wildcards not allowed
test_start "HasValidFileNameChars with wildcards not allowed"
result=$(tpath.hasValidFileNameChars "file*.txt" "false")
if [[ "$result" == "false" ]]; then
    test_pass "HasValidFileNameChars with wildcards not allowed"
else
    test_fail "HasValidFileNameChars with wildcards not allowed (expected: false, got: '$result')"
fi

# Test 5: HasValidPathChars - valid path
test_start "HasValidPathChars with valid path"
result=$(tpath.hasValidPathChars "/valid/path/file.txt")
if [[ "$result" == "true" ]]; then
    test_pass "HasValidPathChars with valid path"
else
    test_fail "HasValidPathChars with valid path (expected: true, got: '$result')"
fi

# Test 6: HasValidPathChars - with wildcards not allowed
test_start "HasValidPathChars with wildcards not allowed"
result=$(tpath.hasValidPathChars "/path/file*.txt" "false")
if [[ "$result" == "false" ]]; then
    test_pass "HasValidPathChars with wildcards not allowed"
else
    test_fail "HasValidPathChars with wildcards not allowed (expected: false, got: '$result')"
fi

# Test 7: IsValidFileNameChar - valid char
test_start "IsValidFileNameChar with valid char"
result=$(tpath.isValidFileNameChar "a")
if [[ "$result" == "true" ]]; then
    test_pass "IsValidFileNameChar with valid char"
else
    test_fail "IsValidFileNameChar with valid char (expected: true, got: '$result')"
fi

# Test 8: IsValidFileNameChar - invalid char /
test_start "IsValidFileNameChar with invalid char /"
result=$(tpath.isValidFileNameChar "/")
if [[ "$result" == "false" ]]; then
    test_pass "IsValidFileNameChar with invalid char /"
else
    test_fail "IsValidFileNameChar with invalid char / (expected: false, got: '$result')"
fi

# Test 9: IsValidFileNameChar - control char
test_start "IsValidFileNameChar with control char"
result=$(tpath.isValidFileNameChar $'\x01')
if [[ "$result" == "false" ]]; then
    test_pass "IsValidFileNameChar with control char"
else
    test_fail "IsValidFileNameChar with control char (expected: false, got: '$result')"
fi

# Test 10: IsValidPathChar - valid char
test_start "IsValidPathChar with valid char"
result=$(tpath.isValidPathChar "a")
if [[ "$result" == "true" ]]; then
    test_pass "IsValidPathChar with valid char"
else
    test_fail "IsValidPathChar with valid char (expected: true, got: '$result')"
fi

# Test 11: IsValidPathChar - control char
test_start "IsValidPathChar with control char"
result=$(tpath.isValidPathChar $'\x01')
if [[ "$result" == "false" ]]; then
    test_pass "IsValidPathChar with control char"
else
    test_fail "IsValidPathChar with control char (expected: false, got: '$result')"
fi

# Test 12: Empty string handling
test_start "Character validation with empty string"
result1=$(tpath.hasValidFileNameChars "")
result2=$(tpath.hasValidPathChars "")
if [[ "$result1" == "true" ]] && [[ "$result2" == "true" ]]; then
    test_pass "Character validation with empty string"
else
    test_fail "Character validation with empty string (expected both true, got: '$result1', '$result2')"
fi
