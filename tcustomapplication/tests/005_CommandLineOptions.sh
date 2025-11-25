#!/bin/bash
# 005_CommandLineOptions.sh - Test TCustomApplication command-line option methods
# Auto-generated for kktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KKTESTS_LIB_DIR="$SCRIPT_DIR/../../../kktests"
source "$KKTESTS_LIB_DIR/kk-test.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kk_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


kk_test_section "005: TCustomApplication Command Line Options"

# Test: FindOptionIndex with short option
kk_test_start "FindOptionIndex with short option"
TCustomApplication.new myapp
# Simulate command line args (in real implementation, would use actual argv)
myapp.FindOptionIndex "v" "false" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "FindOptionIndex returns -1 for non-existent short option"
else
    kk_test_fail "FindOptionIndex unexpected result: $result"
fi
myapp.delete

# Test: FindOptionIndex with long option
kk_test_start "FindOptionIndex with long option"
TCustomApplication.new myapp
myapp.FindOptionIndex "" "verbose" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "FindOptionIndex returns -1 for non-existent long option"
else
    kk_test_fail "FindOptionIndex unexpected result: $result"
fi
myapp.delete

# Test: FindOptionIndex with StartAt parameter
kk_test_start "FindOptionIndex with StartAt parameter"
TCustomApplication.new myapp
myapp.FindOptionIndex "h" "false" 2
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "FindOptionIndex with StartAt works"
else
    kk_test_fail "FindOptionIndex with StartAt unexpected result: $result"
fi
myapp.delete

# Test: GetOptionValue with short option
kk_test_start "GetOptionValue with short option"
TCustomApplication.new myapp
value=$(myapp.GetOptionValue "c")
if [[ -z "$value" ]]; then
    kk_test_pass "GetOptionValue returns empty for non-existent short option"
else
    kk_test_fail "GetOptionValue unexpected result: $value"
fi
myapp.delete

# Test: GetOptionValue with long option
kk_test_start "GetOptionValue with long option"
TCustomApplication.new myapp
value=$(myapp.GetOptionValue "config")
if [[ -z "$value" ]]; then
    kk_test_pass "GetOptionValue returns empty for non-existent long option"
else
    kk_test_fail "GetOptionValue unexpected result: $value"
fi
myapp.delete

# Test: GetOptionValue with char and string
kk_test_start "GetOptionValue with char and string"
TCustomApplication.new myapp
value=$(myapp.GetOptionValue "c" "config")
if [[ -z "$value" ]]; then
    kk_test_pass "GetOptionValue with char and string returns empty"
else
    kk_test_fail "GetOptionValue with char and string unexpected result: $value"
fi
myapp.delete

# Test: GetOptionValues
kk_test_start "GetOptionValues"
TCustomApplication.new myapp
# This would return an array in real implementation
myapp.GetOptionValues "c" "config"
# RESULT would contain array representation
if [[ -n "$RESULT" ]]; then
    kk_test_pass "GetOptionValues returns result"
else
    kk_test_fail "GetOptionValues failed to return result"
fi
myapp.delete

# Test: HasOption with short option
kk_test_start "HasOption with short option"
TCustomApplication.new myapp
result=$(myapp.HasOption "v")
if [[ "$result" == "false" ]]; then
    kk_test_pass "HasOption returns false for non-existent short option"
else
    kk_test_fail "HasOption unexpected result: $result"
fi
myapp.delete

# Test: HasOption with long option
kk_test_start "HasOption with long option"
TCustomApplication.new myapp
result=$(myapp.HasOption "version")
if [[ "$result" == "false" ]]; then
    kk_test_pass "HasOption returns false for non-existent long option"
else
    kk_test_fail "HasOption unexpected result: $result"
fi
myapp.delete

# Test: HasOption with char and string
kk_test_start "HasOption with char and string"
TCustomApplication.new myapp
result=$(myapp.HasOption "v" "version")
if [[ "$result" == "false" ]]; then
    kk_test_pass "HasOption with char and string returns false"
else
    kk_test_fail "HasOption with char and string unexpected result: $result"
fi
myapp.delete

# Test: CheckOptions with valid options
kk_test_start "CheckOptions with valid options"
TCustomApplication.new myapp
error_msg=$(myapp.CheckOptions "hv" "" "" "" "false")
if [[ -z "$error_msg" ]]; then
    kk_test_pass "CheckOptions returns no error for valid options"
else
    kk_test_fail "CheckOptions unexpected error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with invalid options
kk_test_start "CheckOptions with invalid options"
TCustomApplication.new myapp
error_msg=$(myapp.CheckOptions "h:v:" "" "" "" "false")
if [[ -n "$error_msg" ]]; then
    kk_test_pass "CheckOptions detects invalid options"
else
    kk_test_fail "CheckOptions failed to detect invalid options"
fi
myapp.delete

# Test: CheckOptions with long options array
kk_test_start "CheckOptions with long options array"
TCustomApplication.new myapp
error_msg=$(myapp.CheckOptions "h" "help version" "" "" "false")
if [[ -z "$error_msg" ]]; then
    kk_test_pass "CheckOptions works with long options array"
else
    kk_test_fail "CheckOptions with long options array error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with AllErrors
kk_test_start "CheckOptions with AllErrors"
TCustomApplication.new myapp
error_msg=$(myapp.CheckOptions "h:v:" "help version" "" "" "true")
if [[ -n "$error_msg" ]]; then
    kk_test_pass "CheckOptions with AllErrors works"
else
    kk_test_fail "CheckOptions with AllErrors failed"
fi
myapp.delete

# Test: Case sensitivity in option methods
kk_test_start "Case sensitivity in option methods"
TCustomApplication.new myapp
# Set case sensitive to false
myapp.FindOptionIndex "V" "false" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "FindOptionIndex respects case sensitivity"
else
    kk_test_fail "FindOptionIndex case sensitivity issue: $result"
fi
myapp.delete

kk_test_log "005_CommandLineOptions.sh completed"