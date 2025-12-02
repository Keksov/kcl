#!/bin/bash
# 020_CommandLineOptionsDirectArgs.sh - Test TCustomApplication command-line option methods with real parameters
# This test verifies that argument handling works with actual script parameters ($@)
# demonstrating real-world usage without explicit SetArgs calls

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "020: TCustomApplication Command Line Options with Real Parameters"

# Test: FindOptionIndex with short option using real parameters
kt_test_start "FindOptionIndex with short option (real params)"
TCustomApplication.new myapp
set -- -v file.txt --verbose
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "FindOptionIndex finds short option at correct index"
else
    kt_test_fail "FindOptionIndex unexpected result: $result (expected 0)"
fi
myapp.delete

# Test: FindOptionIndex with long option using real parameters
kt_test_start "FindOptionIndex with long option (real params)"
TCustomApplication.new myapp
set -- -h file.txt --verbose data.txt
myapp.FindOptionIndex "" "verbose" 0
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "FindOptionIndex finds long option at correct index"
else
    kt_test_fail "FindOptionIndex unexpected result: $result (expected 2)"
fi
myapp.delete

# Test: FindOptionIndex with StartAt parameter using real parameters
kt_test_start "FindOptionIndex with StartAt parameter (real params)"
TCustomApplication.new myapp
set -- -v file.txt -v data.txt
myapp.FindOptionIndex "v" "" 1
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "FindOptionIndex with StartAt finds next occurrence"
else
    kt_test_fail "FindOptionIndex with StartAt unexpected result: $result (expected 2)"
fi
myapp.delete

# Test: FindOptionIndex returns -1 for non-existent option using real parameters
kt_test_start "FindOptionIndex returns -1 for non-existent option (real params)"
TCustomApplication.new myapp
set -- file.txt data.txt
myapp.FindOptionIndex "x" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "FindOptionIndex returns -1 for non-existent option"
else
    kt_test_fail "FindOptionIndex unexpected result: $result (expected -1)"
fi
myapp.delete

# Test: GetOptionValue with short option using real parameters
kt_test_start "GetOptionValue with short option (real params)"
TCustomApplication.new myapp
set -- -c config.ini file.txt
myapp.GetOptionValue "c" ""
value=$RESULT
if [[ "$value" == "config.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for short option"
else
    kt_test_fail "GetOptionValue unexpected result: $value (expected config.ini)"
fi
myapp.delete

# Test: GetOptionValue with long option using real parameters
kt_test_start "GetOptionValue with long option (real params)"
TCustomApplication.new myapp
set -- file.txt --config data.ini
myapp.GetOptionValue "" "config"
value=$RESULT
if [[ "$value" == "data.ini" ]]; then
    kt_test_pass "GetOptionValue returns correct value for long option"
else
    kt_test_fail "GetOptionValue unexpected result: $value (expected data.ini)"
fi
myapp.delete

# Test: GetOptionValue with both short and long forms using real parameters
kt_test_start "GetOptionValue with char and string (real params)"
TCustomApplication.new myapp
set -- -c test.conf file.txt
myapp.GetOptionValue "c" "config"
value=$RESULT
if [[ "$value" == "test.conf" ]]; then
    kt_test_pass "GetOptionValue with char and string returns value"
else
    kt_test_fail "GetOptionValue with char and string unexpected result: $value (expected test.conf)"
fi
myapp.delete

# Test: GetOptionValue returns empty for option without value using real parameters
kt_test_start "GetOptionValue returns empty for option without value (real params)"
TCustomApplication.new myapp
set -- -v -h file.txt
myapp.GetOptionValue "v" ""
value=$RESULT
if [[ -z "$value" ]]; then
    kt_test_pass "GetOptionValue returns empty when next arg is another option"
else
    kt_test_fail "GetOptionValue should return empty, got: $value"
fi
myapp.delete

# Test: HasOption with short option - found using real parameters
kt_test_start "HasOption finds short option (real params)"
TCustomApplication.new myapp
set -- -v file.txt
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing short option"
else
    kt_test_fail "HasOption unexpected result: $result (expected true)"
fi
myapp.delete

# Test: HasOption with long option - found using real parameters
kt_test_start "HasOption finds long option (real params)"
TCustomApplication.new myapp
set -- file.txt --verbose data.txt
myapp.HasOption "" "verbose"
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasOption returns true for existing long option"
else
    kt_test_fail "HasOption unexpected result: $result (expected true)"
fi
myapp.delete

# Test: HasOption returns false for non-existent option using real parameters
kt_test_start "HasOption returns false for non-existent option (real params)"
TCustomApplication.new myapp
set -- file.txt data.txt
myapp.HasOption "x" ""
result=$RESULT
if [[ "$result" == "false" ]]; then
    kt_test_pass "HasOption returns false for non-existent option"
else
    kt_test_fail "HasOption unexpected result: $result (expected false)"
fi
myapp.delete

# Test: HasOption with char and string using real parameters
kt_test_start "HasOption with char and string (real params)"
TCustomApplication.new myapp
set -- -v file.txt
myapp.HasOption "v" "verbose"
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasOption with char and string returns true"
else
    kt_test_fail "HasOption with char and string unexpected result: $result (expected true)"
fi
myapp.delete

# Test: CheckOptions with valid simple options using real parameters
kt_test_start "CheckOptions with valid simple options (real params)"
TCustomApplication.new myapp
set -- -h -v file.txt
myapp.CheckOptions "hv" "" "" "" "false"
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions returns no error for valid options"
else
    kt_test_fail "CheckOptions unexpected error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with invalid option using real parameters
kt_test_start "CheckOptions rejects invalid options (real params)"
TCustomApplication.new myapp
set -- -x invalid file.txt
myapp.CheckOptions "hv" "" "" "" "false"
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions detects invalid options"
else
    kt_test_fail "CheckOptions failed to detect invalid options"
fi
myapp.delete

kt_test_log "020_CommandLineOptionsDirectArgs.sh completed"
