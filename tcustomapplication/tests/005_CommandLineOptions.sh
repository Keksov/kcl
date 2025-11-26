#!/bin/bash
# 005_CommandLineOptions.sh - Test TCustomApplication command-line option methods

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
myapp.SetArgs -- -v file.txt --verbose
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kk_test_pass "FindOptionIndex finds short option at correct index"
else
    kk_test_fail "FindOptionIndex unexpected result: $result (expected 0)"
fi
myapp.delete

# Test: FindOptionIndex with long option
kk_test_start "FindOptionIndex with long option"
TCustomApplication.new myapp
myapp.SetArgs -h file.txt --verbose data.txt
myapp.FindOptionIndex "" "verbose" 0
result=$RESULT
if [[ "$result" == "2" ]]; then
    kk_test_pass "FindOptionIndex finds long option at correct index"
else
    kk_test_fail "FindOptionIndex unexpected result: $result (expected 2)"
fi
myapp.delete

# Test: FindOptionIndex with StartAt parameter
kk_test_start "FindOptionIndex with StartAt parameter"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt -v data.txt
myapp.FindOptionIndex "v" "" 1
result=$RESULT
if [[ "$result" == "2" ]]; then
    kk_test_pass "FindOptionIndex with StartAt finds next occurrence"
else
    kk_test_fail "FindOptionIndex with StartAt unexpected result: $result (expected 2)"
fi
myapp.delete

# Test: FindOptionIndex returns -1 for non-existent option
kk_test_start "FindOptionIndex returns -1 for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs file.txt data.txt
myapp.FindOptionIndex "x" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kk_test_pass "FindOptionIndex returns -1 for non-existent option"
else
    kk_test_fail "FindOptionIndex unexpected result: $result (expected -1)"
fi
myapp.delete

# Test: GetOptionValue with short option
kk_test_start "GetOptionValue with short option"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini file.txt
myapp.GetOptionValue "c" ""
value=$RESULT
if [[ "$value" == "config.ini" ]]; then
    kk_test_pass "GetOptionValue returns correct value for short option"
else
    kk_test_fail "GetOptionValue unexpected result: $value (expected config.ini)"
fi
myapp.delete

# Test: GetOptionValue with long option
kk_test_start "GetOptionValue with long option"
TCustomApplication.new myapp
myapp.SetArgs file.txt --config data.ini
myapp.GetOptionValue "" "config"
value=$RESULT
if [[ "$value" == "data.ini" ]]; then
    kk_test_pass "GetOptionValue returns correct value for long option"
else
    kk_test_fail "GetOptionValue unexpected result: $value (expected data.ini)"
fi
myapp.delete

# Test: GetOptionValue with both short and long forms
kk_test_start "GetOptionValue with char and string"
TCustomApplication.new myapp
myapp.SetArgs -c test.conf file.txt
myapp.GetOptionValue "c" "config"
value=$RESULT
if [[ "$value" == "test.conf" ]]; then
    kk_test_pass "GetOptionValue with char and string returns value"
else
    kk_test_fail "GetOptionValue with char and string unexpected result: $value (expected test.conf)"
fi
myapp.delete

# Test: GetOptionValue returns empty for option without value
kk_test_start "GetOptionValue returns empty for option without value"
TCustomApplication.new myapp
myapp.SetArgs -v -h file.txt
myapp.GetOptionValue "v" ""
value=$RESULT
if [[ -z "$value" ]]; then
    kk_test_pass "GetOptionValue returns empty when next arg is another option"
else
    kk_test_fail "GetOptionValue should return empty, got: $value"
fi
myapp.delete

# Test: HasOption with short option - found
kk_test_start "HasOption finds short option"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kk_test_pass "HasOption returns true for existing short option"
else
    kk_test_fail "HasOption unexpected result: $result (expected true)"
fi
myapp.delete

# Test: HasOption with long option - found
kk_test_start "HasOption finds long option"
TCustomApplication.new myapp
myapp.SetArgs file.txt --verbose data.txt
myapp.HasOption "" "verbose"
result=$RESULT
if [[ "$result" == "true" ]]; then
    kk_test_pass "HasOption returns true for existing long option"
else
    kk_test_fail "HasOption unexpected result: $result (expected true)"
fi
myapp.delete

# Test: HasOption returns false for non-existent option
kk_test_start "HasOption returns false for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs file.txt data.txt
myapp.HasOption "x" ""
result=$RESULT
if [[ "$result" == "false" ]]; then
    kk_test_pass "HasOption returns false for non-existent option"
else
    kk_test_fail "HasOption unexpected result: $result (expected false)"
fi
myapp.delete

# Test: HasOption with char and string
kk_test_start "HasOption with char and string"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
myapp.HasOption "v" "verbose"
result=$RESULT
if [[ "$result" == "true" ]]; then
    kk_test_pass "HasOption with char and string returns true"
else
    kk_test_fail "HasOption with char and string unexpected result: $result (expected true)"
fi
myapp.delete

# Test: CheckOptions with valid simple options
kk_test_start "CheckOptions with valid simple options"
TCustomApplication.new myapp
myapp.SetArgs -h -v file.txt
myapp.CheckOptions "hv" "" "" "" "false"
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kk_test_pass "CheckOptions returns no error for valid options"
else
    kk_test_fail "CheckOptions unexpected error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with invalid option
kk_test_start "CheckOptions rejects invalid options"
TCustomApplication.new myapp
myapp.SetArgs -x invalid file.txt
myapp.CheckOptions "hv" "" "" "" "false"
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kk_test_pass "CheckOptions detects invalid options"
else
    kk_test_fail "CheckOptions failed to detect invalid options"
fi
myapp.delete

kk_test_log "005_CommandLineOptions.sh completed"
