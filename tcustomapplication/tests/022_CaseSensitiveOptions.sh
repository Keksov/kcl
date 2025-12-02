#!/bin/bash
# 022_CaseSensitiveOptions.sh - Test TCustomApplication case-sensitive option handling
# Tests the CaseSensitiveOptions property behavior

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "022: TCustomApplication Case-Sensitive Options"

# Test: Case-sensitive by default - different cases treated differently
kt_test_start "Case-sensitive: -V and -v are different (default)"
TCustomApplication.new myapp
myapp.SetArgs -- -V file.txt -v data.txt
myapp.FindOptionIndex "V" "" 0
result_upper=$RESULT
myapp.FindOptionIndex "v" "" 0
result_lower=$RESULT
if [[ "$result_upper" == "0" && "$result_lower" == "2" ]]; then
    kt_test_pass "Case-sensitive mode treats -V and -v differently"
else
    kt_test_fail "Case-sensitive test failed: -V at $result_upper (expected 0), -v at $result_lower (expected 2)"
fi
myapp.delete

# Test: FindOptionIndex finds exact case match only (case-sensitive)
kt_test_start "FindOptionIndex respects case in case-sensitive mode"
TCustomApplication.new myapp
myapp.SetArgs -- -M input.txt -m output.txt
myapp.FindOptionIndex "M" "" 0
result_upper=$RESULT
myapp.FindOptionIndex "m" "" 0
result_lower=$RESULT
if [[ "$result_upper" == "0" && "$result_lower" == "2" ]]; then
    kt_test_pass "FindOptionIndex correctly distinguishes -M from -m"
else
    kt_test_fail "FindOptionIndex case sensitivity failed: -M at $result_upper, -m at $result_lower"
fi
myapp.delete

# Test: GetOptionValue with case-sensitive matching
kt_test_start "GetOptionValue with case-sensitive options"
TCustomApplication.new myapp
myapp.SetArgs -- -D debug_val -d debug_lower
myapp.GetOptionValue "D" ""
val_upper=$RESULT
myapp.GetOptionValue "d" ""
val_lower=$RESULT
if [[ "$val_upper" == "debug_val" && "$val_lower" == "debug_lower" ]]; then
    kt_test_pass "GetOptionValue respects case sensitivity"
else
    kt_test_fail "GetOptionValue case test failed: -D=$val_upper, -d=$val_lower"
fi
myapp.delete

# Test: HasOption with case sensitivity
kt_test_start "HasOption respects case sensitivity"
TCustomApplication.new myapp
myapp.SetArgs -- -A arg1
myapp.HasOption "A" ""
result_A=$RESULT
myapp.HasOption "a" ""
result_a=$RESULT
if [[ "$result_A" == "true" && "$result_a" == "false" ]]; then
    kt_test_pass "HasOption correctly differentiates cases"
else
    kt_test_fail "HasOption case test failed: -A=$result_A (expected true), -a=$result_a (expected false)"
fi
myapp.delete

# Test: CheckOptions with multiple cases of same letter
kt_test_start "CheckOptions validates case-sensitive short options"
TCustomApplication.new myapp
myapp.SetArgs -- -A value1 -a value2
myapp.CheckOptions "Aa" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions accepts both -A and -a when both specified"
else
    kt_test_fail "CheckOptions case test failed: $error_msg"
fi
myapp.delete

# Test: Case-sensitive long options
kt_test_start "Long options with case differences"
TCustomApplication.new myapp
myapp.SetArgs -- --Verbose output1 --verbose output2
myapp.FindOptionIndex "" "Verbose" 0
result_upper=$RESULT
myapp.FindOptionIndex "" "verbose" 0
result_lower=$RESULT
if [[ "$result_upper" == "0" && "$result_lower" == "2" ]]; then
    kt_test_pass "Long options are case-sensitive"
else
    kt_test_fail "Long option case test failed: --Verbose at $result_upper, --verbose at $result_lower"
fi
myapp.delete

# Test: GetOptionValues with case sensitivity
kt_test_start "GetOptionValues respects case sensitivity"
TCustomApplication.new myapp
myapp.SetArgs -- -F file1 -f file2 -F file3
myapp.GetOptionValues "F" ""
result_F=$RESULT
myapp.GetOptionValues "f" ""
result_f=$RESULT
# -F should find 2 values, -f should find 1 value
if [[ "$result_F" == "2:"* && "$result_f" == "1:"* ]]; then
    kt_test_pass "GetOptionValues distinguishes -F from -f"
else
    kt_test_fail "GetOptionValues case test failed: -F=$result_F (expected 2), -f=$result_f (expected 1)"
fi
myapp.delete

# Test: Mixed case in command line with case-sensitive mode
kt_test_start "Mixed case options handling (case-sensitive)"
TCustomApplication.new myapp
myapp.SetArgs -- -A val_A -b val_b -C val_C -d val_d
myapp.CheckOptions "AbCd" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "Case-sensitive mode handles mixed case options correctly"
else
    kt_test_fail "Mixed case test failed: $error_msg"
fi
myapp.delete

# Test: Property CaseSensitiveOptions is accessible
kt_test_start "CaseSensitiveOptions property is readable"
TCustomApplication.new myapp
case_sensitive=$(myapp.CaseSensitiveOptions)
if [[ "$case_sensitive" == "true" ]]; then
    kt_test_pass "CaseSensitiveOptions default is true"
else
    kt_test_fail "CaseSensitiveOptions unexpected value: $case_sensitive"
fi
myapp.delete

# Test: Setting CaseSensitiveOptions to false
kt_test_start "CaseSensitiveOptions can be set to false"
TCustomApplication.new myapp
myapp.property CaseSensitiveOptions = "false"
case_sensitive=$(myapp.CaseSensitiveOptions)
if [[ "$case_sensitive" == "false" ]]; then
    kt_test_pass "CaseSensitiveOptions can be changed to false"
else
    kt_test_fail "CaseSensitiveOptions failed to set: $case_sensitive"
fi
myapp.delete

kt_test_log "022_CaseSensitiveOptions.sh completed"
