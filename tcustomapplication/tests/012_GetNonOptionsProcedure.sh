#!/bin/bash
# 012_GetNonOptionsProcedure.sh - Test TCustomApplication GetNonOptions procedure overload
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


kt_test_section "012: TCustomApplication GetNonOptions Procedure Overload"

# Test: GetNonOptions procedure with basic options
kt_test_start "GetNonOptions procedure with basic options"
TCustomApplication.new myapp
declare -a non_options_list
myapp.GetNonOptions "h" "help version" non_options_list
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with basic options works"
else
    kt_test_fail "GetNonOptions procedure with basic options failed"
fi
myapp.delete

# Test: GetNonOptions procedure with required value options
kt_test_start "GetNonOptions procedure with required value options"
TCustomApplication.new myapp
declare -a non_options_req
myapp.GetNonOptions "h:v:" "help version" non_options_req
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with required values works"
else
    kt_test_fail "GetNonOptions procedure with required values failed"
fi
myapp.delete

# Test: GetNonOptions procedure with optional value options
kt_test_start "GetNonOptions procedure with optional value options"
TCustomApplication.new myapp
declare -a non_options_opt
myapp.GetNonOptions "h::v::" "help version" non_options_opt
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with optional values works"
else
    kt_test_fail "GetNonOptions procedure with optional values failed"
fi
myapp.delete

# Test: GetNonOptions procedure with complex option string
kt_test_start "GetNonOptions procedure with complex option string"
TCustomApplication.new myapp
declare -a non_options_complex
myapp.GetNonOptions "abc:def::ghi" "alpha beta gamma" non_options_complex
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with complex options works"
else
    kt_test_fail "GetNonOptions procedure with complex options failed"
fi
myapp.delete

# Test: GetNonOptions procedure with empty short options
kt_test_start "GetNonOptions procedure with empty short options"
TCustomApplication.new myapp
declare -a non_options_empty_short
myapp.GetNonOptions "" "help version" non_options_empty_short
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with empty short options works"
else
    kt_test_fail "GetNonOptions procedure with empty short options failed"
fi
myapp.delete

# Test: GetNonOptions procedure with empty long options
kt_test_start "GetNonOptions procedure with empty long options"
TCustomApplication.new myapp
declare -a non_options_empty_long
myapp.GetNonOptions "h" "" non_options_empty_long
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with empty long options works"
else
    kt_test_fail "GetNonOptions procedure with empty long options failed"
fi
myapp.delete

# Test: GetNonOptions procedure with both empty
kt_test_start "GetNonOptions procedure with both empty"
TCustomApplication.new myapp
declare -a non_options_both_empty
myapp.GetNonOptions "" "" non_options_both_empty
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure with both empty works"
else
    kt_test_fail "GetNonOptions procedure with both empty failed"
fi
myapp.delete

# Test: GetNonOptions procedure multiple calls
kt_test_start "GetNonOptions procedure multiple calls"
TCustomApplication.new myapp
declare -a non_options1
declare -a non_options2
myapp.GetNonOptions "h" "help" non_options1
myapp.GetNonOptions "v" "version" non_options2
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "Multiple GetNonOptions procedure calls work"
else
    kt_test_fail "Multiple GetNonOptions procedure calls failed"
fi
myapp.delete

# Test: GetNonOptions procedure with case sensitivity
kt_test_start "GetNonOptions procedure with case sensitivity"
TCustomApplication.new myapp
declare -a non_options_case
myapp.GetNonOptions "H" "HELP" non_options_case
result=$?
if [[ $result -eq 0 ]]; then
    kt_test_pass "GetNonOptions procedure respects case sensitivity"
else
    kt_test_fail "GetNonOptions procedure case sensitivity issue"
fi
myapp.delete

kt_test_log "012_GetNonOptionsProcedure.sh completed"