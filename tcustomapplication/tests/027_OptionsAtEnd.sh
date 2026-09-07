#!/bin/bash
# 027_OptionsAtEnd.sh - Test edge cases with options at end of arguments
# Tests options without values at end of argument list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "027: TCustomApplication Options at End"

# Test: Option at end with no value
kt_test_start "Option at end of arguments"
TCustomApplication.new myapp
myapp.SetArgs file.txt -v
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "Option at end is found"
else
    kt_test_fail "Option at end failed: $result"
fi
myapp.delete

# Test: Option at end returns -1 for GetNextArgValue
kt_test_start "GetOptionValue for option at end"
TCustomApplication.new myapp
myapp.SetArgs file.txt --verbose
myapp.GetOptionValue "" "verbose"
value=$RESULT
if [[ -z "$value" ]]; then
    kt_test_pass "Option at end has no value (empty string)"
else
    kt_test_fail "Option at end should have empty value, got: $value"
fi
myapp.delete

# Test: Multiple options at end
kt_test_start "Multiple options at end"
TCustomApplication.new myapp
myapp.SetArgs file.txt -v -h -d
myapp.FindOptionIndex "v" ""
result_v=$RESULT
myapp.FindOptionIndex "h" ""
result_h=$RESULT
myapp.FindOptionIndex "d" ""
result_d=$RESULT
if [[ "$result_v" == "2" && "$result_h" == "3" && "$result_d" == "4" ]]; then
    kt_test_pass "Multiple options at end all found"
else
    kt_test_fail "Multiple options at end failed: -v=$result_v, -h=$result_h, -d=$result_d"
fi
myapp.delete

# Test: Option with value followed by option without value
kt_test_start "Option with value followed by option without value"
TCustomApplication.new myapp
myapp.SetArgs -f file.txt -v
myapp.GetOptionValue "f" ""
val_f=$RESULT
myapp.GetOptionValue "v" ""
val_v=$RESULT
if [[ "$val_f" == "file.txt" && -z "$val_v" ]]; then
    kt_test_pass "Both options handled correctly at end sequence"
else
    kt_test_fail "Options sequence failed: -f=$val_f, -v=$val_v"
fi
myapp.delete

# Test: FindOptionIndex for last option
kt_test_start "FindOptionIndex returns correct index for last arg"
TCustomApplication.new myapp
myapp.SetArgs arg1 arg2 -x
myapp.FindOptionIndex "x" ""
result=$RESULT
if [[ "$result" == "3" ]]; then
    kt_test_pass "Last option gets correct index"
else
    kt_test_fail "Last option index wrong: $result (expected 3)"
fi
myapp.delete

# Test: Option expecting value at end - should fail
kt_test_start "Option expecting value placed at end"
TCustomApplication.new myapp
myapp.SetArgs -c config.ini -f
# -f expects a file argument but is at end
myapp.CheckOptions "c:f:" ""
error_msg=$RESULT
# -f is the last argument, so there is nothing to consume: SErrOptionNeeded at
# position 3. (The old assertion was `[[ -z x ]] || [[ -n x ]]`, a tautology.)
if [[ "$error_msg" == "Option at position 3 needs an argument : f" ]]; then
    kt_test_pass "a value-taking option at the end is reported by position"
else
    kt_test_fail "CheckOptions for a trailing 'f:' gave '$error_msg'"
fi
myapp.delete

# Test: GetNonOptions with trailing option
kt_test_start "GetNonOptions with trailing option"
TCustomApplication.new myapp
myapp.SetArgs file1 file2 -v
myapp.GetNonOptions "v" ""
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "GetNonOptions counts files, not trailing option"
else
    kt_test_fail "GetNonOptions with trailing failed: $result (expected 2)"
fi
myapp.delete

# Test: Only options, last is standalone
kt_test_start "Arguments with only options, last standalone"
TCustomApplication.new myapp
myapp.SetArgs -a val1 -b val2 -c
myapp.FindOptionIndex "c" ""
result=$RESULT
if [[ "$result" == "5" ]]; then
    kt_test_pass "Standalone option at end found at correct position"
else
    kt_test_fail "Position of standalone option wrong: $result (expected 5)"
fi
myapp.delete

# Test: Long option at end
kt_test_start "Long option at end"
TCustomApplication.new myapp
myapp.SetArgs file.txt --verbose
myapp.FindOptionIndex "" "verbose"
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "Long option at end found"
else
    kt_test_fail "Long option at end failed: $result (expected 2)"
fi
myapp.delete

# Test: Combined options at end
kt_test_start "Combined short options at end"
TCustomApplication.new myapp
myapp.SetArgs file.txt -vhd
# Combined options -vhd are parsed by CheckOptions as individual -v, -h, -d
myapp.CheckOptions "vhd" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "Combined options at end recognized by CheckOptions"
else
    kt_test_fail "Combined options at end failed: $error_msg"
fi
myapp.delete

# Test: Option with equals at end
kt_test_start "Long option with equals at end"
TCustomApplication.new myapp
myapp.SetArgs file.txt --output=result.txt
myapp.FindOptionIndex "" "output"
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "Equals-format option at end found"
else
    kt_test_fail "Equals option at end failed: $result (expected 2)"
fi
myapp.delete

# Test: Empty args array with option search
kt_test_start "Empty args - no options at end"
TCustomApplication.new myapp
myapp.SetArgs
myapp.FindOptionIndex "v" ""
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "Empty args returns -1 for non-existent option"
else
    kt_test_fail "Empty args test failed: $result"
fi
myapp.delete

# Test: Single option as only argument
kt_test_start "Single option as only argument"
TCustomApplication.new myapp
myapp.SetArgs -v
myapp.FindOptionIndex "v" ""
result=$RESULT
if [[ "$result" == "1" ]]; then
    kt_test_pass "Single option argument found at index 1"
else
    kt_test_fail "Single option argument failed: $result"
fi
myapp.delete

# Test: Single long option as only argument
kt_test_start "Single long option as only argument"
TCustomApplication.new myapp
myapp.SetArgs --verbose
myapp.FindOptionIndex "" "verbose"
result=$RESULT
if [[ "$result" == "1" ]]; then
    kt_test_pass "Single long option argument found"
else
    kt_test_fail "Single long option failed: $result"
fi
myapp.delete

# Test: GetOptionValues with option at end (no value)
kt_test_start "GetOptionValues for option at end"
TCustomApplication.new myapp
myapp.SetArgs -f f1 -f f2 -f
declare -a end_vals=()
myapp.GetOptionValues "f" "" end_vals
result=$RESULT
# FPC returns one entry per OCCURRENCE; the trailing -f contributes an empty one.
if [[ "$result" == "3" && -z "${end_vals[0]}" && "${end_vals[1]}" == "f2" && "${end_vals[2]}" == "f1" ]]; then
    kt_test_pass "three occurrences, the trailing one with an empty value"
else
    kt_test_fail "GetOptionValues at end failed: count=$result $(declare -p end_vals)"
fi
myapp.delete

kt_test_log "027_OptionsAtEnd.sh completed"
