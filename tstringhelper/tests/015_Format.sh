#!/bin/bash
# Format
# Auto-migrated to kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

kk_test_init "Format" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Simple string formatting
kk_test_start "Format - simple string substitution"
result=$(string.format "Hello %s" "World")
if [[ "$result" == "Hello World" ]]; then
    kk_test_pass "Format - simple string substitution"
else
    kk_test_fail "Format - simple string substitution (expected: 'Hello World', got: '$result')"
fi

# Test 2: Multiple string substitutions
kk_test_start "Format - multiple substitutions"
result=$(string.format "%s is %s" "This" "great")
if [[ "$result" == "This is great" ]]; then
    kk_test_pass "Format - multiple substitutions"
else
    kk_test_fail "Format - multiple substitutions (expected: 'This is great', got: '$result')"
fi

# Test 3: Integer substitution
kk_test_start "Format - integer substitution"
result=$(string.format "Number: %d" 42)
if [[ "$result" == "Number: 42" ]]; then
    kk_test_pass "Format - integer substitution"
else
    kk_test_fail "Format - integer substitution (expected: 'Number: 42', got: '$result')"
fi

# Test 4: Mixed substitutions
kk_test_start "Format - mixed types"
result=$(string.format "%s has %d apples" "John" 5)
if [[ "$result" == "John has 5 apples" ]]; then
    kk_test_pass "Format - mixed types"
else
    kk_test_fail "Format - mixed types (expected: 'John has 5 apples', got: '$result')"
fi

# Test 5: No substitutions
kk_test_start "Format - no placeholder"
result=$(string.format "Just a string")
if [[ "$result" == "Just a string" ]]; then
    kk_test_pass "Format - no placeholder"
else
    kk_test_fail "Format - no placeholder (expected: 'Just a string', got: '$result')"
fi

# Test 6: Empty format string
kk_test_start "Format - empty format string"
result=$(string.format "")
if [[ "$result" == "" ]]; then
    kk_test_pass "Format - empty format string"
else
    kk_test_fail "Format - empty format string (expected: '', got: '$result')"
fi

# Test 7: Escaped percent sign
kk_test_start "Format - escaped percent"
result=$(string.format "100%% complete")
if [[ "$result" == "100% complete" || "$result" == "100%% complete" ]]; then
    kk_test_pass "Format - escaped percent"
else
    kk_test_fail "Format - escaped percent (expected: '100% complete', got: '$result')"
fi

# Test 8: Three parameters
kk_test_start "Format - three parameters"
result=$(string.format "%s-%s-%s" "a" "b" "c")
if [[ "$result" == "a-b-c" ]]; then
    kk_test_pass "Format - three parameters"
else
    kk_test_fail "Format - three parameters (expected: 'a-b-c', got: '$result')"
fi

# Test 9: String with special characters
kk_test_start "Format - special characters in format"
result=$(string.format "Email: %s@%s" "user" "example.com")
if [[ "$result" == "Email: user@example.com" ]]; then
    kk_test_pass "Format - special characters in format"
else
    kk_test_fail "Format - special characters in format (expected: 'Email: user@example.com', got: '$result')"
fi

# Test 10: Numeric string parameter
kk_test_start "Format - numeric string parameter"
result=$(string.format "ID: %s" "12345")
if [[ "$result" == "ID: 12345" ]]; then
    kk_test_pass "Format - numeric string parameter"
else
    kk_test_fail "Format - numeric string parameter (expected: 'ID: 12345', got: '$result')"
fi
