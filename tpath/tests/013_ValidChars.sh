#!/bin/bash
# ValidChars
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ValidChars" "$SCRIPT_DIR" "$@"

# Source tpath if needed
TPATH_DIR="$SCRIPT_DIR/.."
[[ -f "$TPATH_DIR/tpath.sh" ]] && source "$TPATH_DIR/tpath.sh"


# Test 1: HasValidFileNameChars - valid filename
kt_test_start "HasValidFileNameChars with valid filename"
result=$(tpath.hasValidFileNameChars "valid_file.txt")
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasValidFileNameChars with valid filename"
else
    kt_test_fail "HasValidFileNameChars with valid filename (expected: true, got: '$result')"
fi

# Test 2: HasValidFileNameChars - invalid filename with /
kt_test_start "HasValidFileNameChars with invalid filename (/)"
result=$(tpath.hasValidFileNameChars "invalid/file.txt")
if [[ "$result" == "false" ]]; then
    kt_test_pass "HasValidFileNameChars with invalid filename (/)"
else
    kt_test_fail "HasValidFileNameChars with invalid filename (/) (expected: false, got: '$result')"
fi

# Test 3: HasValidFileNameChars - with wildcards allowed
kt_test_start "HasValidFileNameChars with wildcards allowed"
result=$(tpath.hasValidFileNameChars "file*.txt" "true")
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasValidFileNameChars with wildcards allowed"
else
    kt_test_fail "HasValidFileNameChars with wildcards allowed (expected: true, got: '$result')"
fi

# Test 4: HasValidFileNameChars - with wildcards not allowed
kt_test_start "HasValidFileNameChars with wildcards not allowed"
result=$(tpath.hasValidFileNameChars "file*.txt" "false")
if [[ "$result" == "false" ]]; then
    kt_test_pass "HasValidFileNameChars with wildcards not allowed"
else
    kt_test_fail "HasValidFileNameChars with wildcards not allowed (expected: false, got: '$result')"
fi

# Test 5: HasValidPathChars - valid path
kt_test_start "HasValidPathChars with valid path"
result=$(tpath.hasValidPathChars "/valid/path/file.txt")
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasValidPathChars with valid path"
else
    kt_test_fail "HasValidPathChars with valid path (expected: true, got: '$result')"
fi

# Test 6: HasValidPathChars - with wildcards not allowed
kt_test_start "HasValidPathChars with wildcards not allowed"
result=$(tpath.hasValidPathChars "/path/file*.txt" "false")
if [[ "$result" == "false" ]]; then
    kt_test_pass "HasValidPathChars with wildcards not allowed"
else
    kt_test_fail "HasValidPathChars with wildcards not allowed (expected: false, got: '$result')"
fi

# Test 7: IsValidFileNameChar - valid char
kt_test_start "IsValidFileNameChar with valid char"
result=$(tpath.isValidFileNameChar "a")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsValidFileNameChar with valid char"
else
    kt_test_fail "IsValidFileNameChar with valid char (expected: true, got: '$result')"
fi

# Test 8: IsValidFileNameChar - invalid char /
kt_test_start "IsValidFileNameChar with invalid char /"
result=$(tpath.isValidFileNameChar "/")
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsValidFileNameChar with invalid char /"
else
    kt_test_fail "IsValidFileNameChar with invalid char / (expected: false, got: '$result')"
fi

# Test 9: IsValidFileNameChar - control char
kt_test_start "IsValidFileNameChar with control char"
result=$(tpath.isValidFileNameChar $'\x01')
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsValidFileNameChar with control char"
else
    kt_test_fail "IsValidFileNameChar with control char (expected: false, got: '$result')"
fi

# Test 10: IsValidPathChar - valid char
kt_test_start "IsValidPathChar with valid char"
result=$(tpath.isValidPathChar "a")
if [[ "$result" == "true" ]]; then
    kt_test_pass "IsValidPathChar with valid char"
else
    kt_test_fail "IsValidPathChar with valid char (expected: true, got: '$result')"
fi

# Test 11: IsValidPathChar - control char
kt_test_start "IsValidPathChar with control char"
result=$(tpath.isValidPathChar $'\x01')
if [[ "$result" == "false" ]]; then
    kt_test_pass "IsValidPathChar with control char"
else
    kt_test_fail "IsValidPathChar with control char (expected: false, got: '$result')"
fi

# Test 12: Empty string handling
kt_test_start "Character validation with empty string"
result1=$(tpath.hasValidFileNameChars "")
result2=$(tpath.hasValidPathChars "")
if [[ "$result1" == "true" ]] && [[ "$result2" == "true" ]]; then
    kt_test_pass "Character validation with empty string"
else
    kt_test_fail "Character validation with empty string (expected both true, got: '$result1', '$result2')"
fi
