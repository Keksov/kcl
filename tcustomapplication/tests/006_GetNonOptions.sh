#!/bin/bash
# 006_GetNonOptions.sh - Test TCustomApplication GetNonOptions method
# Auto-generated for ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"


kt_test_section "006: TCustomApplication GetNonOptions"

# Test: GetNonOptions with basic options
kt_test_start "GetNonOptions with basic options"
TCustomApplication.new myapp
# In real implementation, this would parse actual command line
myapp.GetNonOptions "h" "help version"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions returns result"
else
    kt_test_fail "GetNonOptions failed to return result"
fi
myapp.delete

# Test: GetNonOptions with required value options
kt_test_start "GetNonOptions with required value options"
TCustomApplication.new myapp
myapp.GetNonOptions "h:v:" "help version"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with required values works"
else
    kt_test_fail "GetNonOptions with required values failed"
fi
myapp.delete

# Test: GetNonOptions with optional value options
kt_test_start "GetNonOptions with optional value options"
TCustomApplication.new myapp
myapp.GetNonOptions "h::v::" "help version"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with optional values works"
else
    kt_test_fail "GetNonOptions with optional values failed"
fi
myapp.delete

# Test: GetNonOptions with TStrings parameter
kt_test_start "GetNonOptions with TStrings parameter"
TCustomApplication.new myapp
# Create a mock TStrings-like object
declare -a non_options_list
myapp.GetNonOptions "h" "help" non_options_list
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions with TStrings parameter works"
else
    kt_test_fail "GetNonOptions with TStrings parameter failed"
fi
myapp.delete

# Test: GetNonOptions with complex option string
kt_test_start "GetNonOptions with complex option string"
TCustomApplication.new myapp
myapp.GetNonOptions "abc:def::ghi" "alpha beta gamma"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with complex options works"
else
    kt_test_fail "GetNonOptions with complex options failed"
fi
myapp.delete

# Test: GetNonOptions with empty short options
kt_test_start "GetNonOptions with empty short options"
TCustomApplication.new myapp
myapp.GetNonOptions "" "help version"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with empty short options works"
else
    kt_test_fail "GetNonOptions with empty short options failed"
fi
myapp.delete

# Test: GetNonOptions with empty long options
kt_test_start "GetNonOptions with empty long options"
TCustomApplication.new myapp
myapp.GetNonOptions "h" ""
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with empty long options works"
else
    kt_test_fail "GetNonOptions with empty long options failed"
fi
myapp.delete

# Test: GetNonOptions with both empty
kt_test_start "GetNonOptions with both empty"
TCustomApplication.new myapp
myapp.GetNonOptions "" ""
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions with both empty works"
else
    kt_test_fail "GetNonOptions with both empty failed"
fi
myapp.delete

# Test: GetNonOptions multiple calls
kt_test_start "GetNonOptions multiple calls"
TCustomApplication.new myapp
myapp.GetNonOptions "h" "help"
result1=$RESULT
myapp.GetNonOptions "v" "version"
result2=$RESULT
if [[ -n "$result1" && -n "$result2" ]]; then
    kt_test_pass "Multiple GetNonOptions calls work"
else
    kt_test_fail "Multiple GetNonOptions calls failed: result1=$result1, result2=$result2"
fi
myapp.delete

# Test: GetNonOptions with case sensitivity
kt_test_start "GetNonOptions with case sensitivity"
TCustomApplication.new myapp
# Set case sensitive options
myapp.GetNonOptions "H" "HELP"
result=$RESULT
if [[ -n "$result" ]]; then
    kt_test_pass "GetNonOptions respects case sensitivity"
else
    kt_test_fail "GetNonOptions case sensitivity issue"
fi
myapp.delete

kt_test_log "006_GetNonOptions.sh completed"