#!/bin/bash
# Format
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Format" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Simple string formatting
kt_test_start "Format - simple string substitution"
result=$(string.format "Hello %s" "World")
if [[ "$result" == "Hello World" ]]; then
    kt_test_pass "Format - simple string substitution"
else
    kt_test_fail "Format - simple string substitution (expected: 'Hello World', got: '$result')"
fi

# Test 2: Multiple string substitutions
kt_test_start "Format - multiple substitutions"
result=$(string.format "%s is %s" "This" "great")
if [[ "$result" == "This is great" ]]; then
    kt_test_pass "Format - multiple substitutions"
else
    kt_test_fail "Format - multiple substitutions (expected: 'This is great', got: '$result')"
fi

# Test 3: Integer substitution
kt_test_start "Format - integer substitution"
result=$(string.format "Number: %d" 42)
if [[ "$result" == "Number: 42" ]]; then
    kt_test_pass "Format - integer substitution"
else
    kt_test_fail "Format - integer substitution (expected: 'Number: 42', got: '$result')"
fi

# Test 4: Mixed substitutions
kt_test_start "Format - mixed types"
result=$(string.format "%s has %d apples" "John" 5)
if [[ "$result" == "John has 5 apples" ]]; then
    kt_test_pass "Format - mixed types"
else
    kt_test_fail "Format - mixed types (expected: 'John has 5 apples', got: '$result')"
fi

# Test 5: No substitutions
kt_test_start "Format - no placeholder"
result=$(string.format "Just a string")
if [[ "$result" == "Just a string" ]]; then
    kt_test_pass "Format - no placeholder"
else
    kt_test_fail "Format - no placeholder (expected: 'Just a string', got: '$result')"
fi

# Test 6: Empty format string
kt_test_start "Format - empty format string"
result=$(string.format "")
if [[ "$result" == "" ]]; then
    kt_test_pass "Format - empty format string"
else
    kt_test_fail "Format - empty format string (expected: '', got: '$result')"
fi

# Test 7: Escaped percent sign
kt_test_start "Format - escaped percent"
result=$(string.format "100%% complete")
if [[ "$result" == "100% complete" || "$result" == "100%% complete" ]]; then
    kt_test_pass "Format - escaped percent"
else
    kt_test_fail "Format - escaped percent (expected: '100% complete', got: '$result')"
fi

# Test 8: Three parameters
kt_test_start "Format - three parameters"
result=$(string.format "%s-%s-%s" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    kt_test_pass "Format - three parameters"
else
    kt_test_fail "Format - three parameters (expected: 'a-b-c', got: '$result')"
fi

# Test 9: String with special characters
kt_test_start "Format - special characters in format"
result=$(string.format "Email: %s@%s" "user" "example.com")
if [[ "$result" == "Email: user@example.com" ]]; then
    kt_test_pass "Format - special characters in format"
else
    kt_test_fail "Format - special characters in format (expected: 'Email: user@example.com', got: '$result')"
fi

# Test 10: Numeric string parameter
kt_test_start "Format - numeric string parameter"
result=$(string.format "ID: %s" "12345")
if [[ "$result" == "ID: 12345" ]]; then
    kt_test_pass "Format - numeric string parameter"
else
    kt_test_fail "Format - numeric string parameter (expected: 'ID: 12345', got: '$result')"
fi
