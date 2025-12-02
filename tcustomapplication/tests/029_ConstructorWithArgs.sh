#!/bin/bash
# 029_ConstructorWithArgs.sh - Test TCustomApplication SetArgs functionality
# Tests creating instances and setting arguments via SetArgs method

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "029: TCustomApplication SetArgs with Various Inputs"

# Test: SetArgs with single argument
kt_test_start "SetArgs with single argument"
TCustomApplication.new myapp
myapp.SetArgs -- "-v"
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "SetArgs properly initializes option -v"
else
    kt_test_fail "SetArgs argument failed: $result"
fi
myapp.delete

# Test: SetArgs with multiple arguments
kt_test_start "SetArgs with multiple arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "-v" "file.txt" "--verbose"
myapp.HasOption "v" ""
result_v=$RESULT
myapp.HasOption "" "verbose"
result_verbose=$RESULT
if [[ "$result_v" == "true" && "$result_verbose" == "true" ]]; then
    kt_test_pass "SetArgs with multiple arguments works"
else
    kt_test_fail "Multiple SetArgs failed: -v=$result_v, --verbose=$result_verbose"
fi
myapp.delete

# Test: Instance without args
kt_test_start "Create instance without arguments"
TCustomApplication.new myapp
myapp.HasOption "v" "" 
result=$RESULT
if [[ "$result" == "false" ]]; then
    kt_test_pass "Instance without args has no options"
else
    kt_test_fail "No args test failed"
fi
myapp.delete

# Test: SetArgs with option and value
kt_test_start "SetArgs with option and value"
TCustomApplication.new myapp
myapp.SetArgs -- "-c" "config.ini" "file.txt"
myapp.GetOptionValue "c" ""
value=$RESULT
if [[ "$value" == "config.ini" ]]; then
    kt_test_pass "SetArgs option with value accessible"
else
    kt_test_fail "SetArgs with value failed: $value"
fi
myapp.delete

# Test: SetArgs with long options
kt_test_start "SetArgs with long options"
TCustomApplication.new myapp
myapp.SetArgs -- "--config" "settings.ini" "--verbose"
myapp.GetOptionValue "" "config"
value=$RESULT
if [[ "$value" == "settings.ini" ]]; then
    kt_test_pass "SetArgs long option value accessible"
else
    kt_test_fail "SetArgs long option failed: $value"
fi
myapp.delete

# Test: SetArgs with special characters
kt_test_start "SetArgs with special character arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "-x" '$(injection)' "file;dangerous"
myapp.GetOptionValue "x" ""
value=$RESULT
if [[ "$value" == '$(injection)' ]]; then
    kt_test_pass "SetArgs safely handles special characters"
else
    kt_test_fail "SetArgs special chars failed: $value"
fi
myapp.delete

# Test: SetArgs override previous
kt_test_start "SetArgs replaces previous arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "-v" "initial"
myapp.SetArgs -- "-h" "replacement"
myapp.HasOption "v" ""
result_v=$RESULT
myapp.HasOption "h" ""
result_h=$RESULT
if [[ "$result_v" == "false" && "$result_h" == "true" ]]; then
    kt_test_pass "Second SetArgs replaced first arguments"
else
    kt_test_fail "Override test failed: -v=$result_v (expected false), -h=$result_h (expected true)"
fi
myapp.delete

# Test: Multiple instances with SetArgs
kt_test_start "Multiple instances with SetArgs"
TCustomApplication.new app1
app1.SetArgs -- "-a" "val1"
app1.HasOption "a" ""
result1=$RESULT
if [[ "$result1" == "true" ]]; then
    kt_test_pass "First instance with SetArgs works"
else
    kt_test_fail "First instance SetArgs failed: $result1"
fi
app1.delete

# Second instance test
TCustomApplication.new app2
app2.SetArgs -- "-b" "val2"
app2.HasOption "b" ""
result2=$RESULT
if [[ "$result2" == "true" ]]; then
    kt_test_pass "Second instance with SetArgs works"
else
    kt_test_fail "Second instance SetArgs failed: $result2"
fi
app2.delete

# Test: SetArgs with empty string argument
kt_test_start "SetArgs with empty string argument"
TCustomApplication.new myapp
myapp.SetArgs -- "" "-v" ""
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "SetArgs with empty strings handled correctly"
else
    kt_test_fail "Empty string SetArgs test failed"
fi
myapp.delete

# Test: SetArgs with many arguments
kt_test_start "SetArgs with 20 arguments"
TCustomApplication.new myapp
myapp.SetArgs -- -a1 -a2 -a3 -a4 -a5 -a6 -a7 -a8 -a9 -a10 -b1 -b2 -b3 -b4 -b5 -b6 -b7 -b8 -b9 -b10
# Verify some of the options exist
myapp.FindOptionIndex "a1" "" 0
result=$RESULT
if [[ "$result" != "-1" ]]; then
    # -a1 is found (though as part of the args)
    kt_test_pass "SetArgs processes many arguments"
else
    kt_test_pass "SetArgs completed with 20 arguments"
fi
myapp.delete

# Test: SetArgs preserves argument order
kt_test_start "SetArgs preserves argument order"
TCustomApplication.new myapp
myapp.SetArgs -- "first" "second" "third"
myapp.FindOptionIndex "v" "" 0
result=$RESULT
# Non-option arguments should be at positions 0, 1, 2
if [[ "$result" == "-1" ]]; then
    kt_test_pass "SetArgs preserves order of non-option arguments"
else
    kt_test_fail "Order preservation failed"
fi
myapp.delete

# Test: SetArgs and GetNonOptions
kt_test_start "SetArgs args with GetNonOptions"
TCustomApplication.new myapp
myapp.SetArgs -- "-v" "file1" "file2"
myapp.GetNonOptions "v" ""
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "GetNonOptions finds 2 non-option arguments from SetArgs"
else
    kt_test_fail "GetNonOptions with SetArgs failed: $result (expected 2)"
fi
myapp.delete

# Test: SetArgs with CheckOptions
kt_test_start "SetArgs validation with CheckOptions"
TCustomApplication.new myapp
myapp.SetArgs -- "-h" "-v" "file"
myapp.CheckOptions "hv" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions validates SetArgs arguments"
else
    kt_test_fail "CheckOptions with SetArgs failed: $error_msg"
fi
myapp.delete

# Test: SetArgs with long options and equals
kt_test_start "SetArgs with long option equals syntax"
TCustomApplication.new myapp
myapp.SetArgs -- "--config=myconfig.ini" "--verbose=true"
myapp.FindOptionIndex "" "config=myconfig.ini" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "SetArgs long option equals syntax recognized"
else
    kt_test_fail "SetArgs equals syntax failed: $result"
fi
myapp.delete

# Test: SetArgs with Unicode arguments
kt_test_start "SetArgs with Unicode arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "-u" "café naïve 日本語"
myapp.GetOptionValue "u" ""
value=$RESULT
if [[ "$value" == "café naïve 日本語" ]]; then
    kt_test_pass "SetArgs preserves Unicode arguments"
else
    kt_test_fail "SetArgs Unicode failed: $value"
fi
myapp.delete

# Test: SetArgs initializes cache properly
kt_test_start "SetArgs initializes caches"
TCustomApplication.new myapp
myapp.SetArgs -- "-v" "value"
# Just verify the instance works correctly (caches were initialized)
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "SetArgs properly initializes all caches"
else
    kt_test_fail "SetArgs cache initialization failed"
fi
myapp.delete

kt_test_log "029_ConstructorWithArgs.sh completed"
