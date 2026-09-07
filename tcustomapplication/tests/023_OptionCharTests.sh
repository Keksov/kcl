#!/bin/bash
# 023_OptionCharTests.sh - Test TCustomApplication with different option characters
# Tests the OptionChar property to use alternative prefix characters

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "023: TCustomApplication OptionChar Tests"

# Test: Default OptionChar is "-"
kt_test_start "Default OptionChar is dash"
TCustomApplication.new myapp
option_char=$(myapp.OptionChar)
if [[ "$option_char" == "-" ]]; then
    kt_test_pass "Default OptionChar is '-'"
else
    kt_test_fail "Default OptionChar unexpected: $option_char"
fi
myapp.delete

# Test: OptionChar can be changed to "+"
kt_test_start "OptionChar can be set to plus"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
option_char=$(myapp.OptionChar)
if [[ "$option_char" == "+" ]]; then
    kt_test_pass "OptionChar can be changed to '+'"
else
    kt_test_fail "OptionChar change failed: $option_char"
fi
myapp.delete

# Test: OptionChar can be changed to "/"
kt_test_start "OptionChar can be set to slash"
TCustomApplication.new myapp
myapp.property OptionChar = "/"
option_char=$(myapp.OptionChar)
if [[ "$option_char" == "/" ]]; then
    kt_test_pass "OptionChar can be changed to '/'"
else
    kt_test_fail "OptionChar change failed: $option_char"
fi
myapp.delete

# Test: FindOptionIndex with "+" as OptionChar
kt_test_start "FindOptionIndex recognizes + as option prefix"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +v file.txt ++verbose
myapp.FindOptionIndex "v" ""
result=$RESULT
if [[ "$result" == "1" ]]; then
    kt_test_pass "FindOptionIndex works with + prefix"
else
    kt_test_fail "FindOptionIndex with + failed: $result (expected 1)"
fi
myapp.delete

# Test: FindOptionIndex with "/" as OptionChar
kt_test_start "FindOptionIndex recognizes / as option prefix"
TCustomApplication.new myapp
myapp.property OptionChar = "/"
myapp.SetArgs /v file.txt //verbose
myapp.FindOptionIndex "v" ""
result=$RESULT
if [[ "$result" == "1" ]]; then
    kt_test_pass "FindOptionIndex works with / prefix"
else
    kt_test_fail "FindOptionIndex with / failed: $result (expected 1)"
fi
myapp.delete

# Test: GetOptionValue with custom OptionChar "+"
kt_test_start "GetOptionValue with + as OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +c config.ini file.txt
myapp.GetOptionValue "c" ""
value=$RESULT
if [[ "$value" == "config.ini" ]]; then
    kt_test_pass "GetOptionValue works with + prefix"
else
    kt_test_fail "GetOptionValue with + failed: $value"
fi
myapp.delete

# Test: HasOption with "/" as OptionChar
kt_test_start "HasOption with / as OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "/"
myapp.SetArgs /h file.txt
myapp.HasOption "h" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "HasOption works with / prefix"
else
    kt_test_fail "HasOption with / failed: $result"
fi
myapp.delete

# Test: Long options with custom OptionChar "+"
kt_test_start "Long options with ++ prefix"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs file.txt ++verbose data.txt
# Arguments: 0=file.txt, 1=++verbose, 2=data.txt
myapp.FindOptionIndex "" "verbose"
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "Long options work with ++ prefix"
else
    kt_test_fail "Long options with ++ failed: $result (expected 2)"
fi
myapp.delete

# Test: CheckOptions with custom OptionChar
kt_test_start "CheckOptions validates options with custom OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +h +v file.txt
myapp.CheckOptions "hv" ""
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions works with custom OptionChar"
else
    kt_test_fail "CheckOptions with custom OptionChar failed: $error_msg"
fi
myapp.delete

# Test: GetNonOptions with custom OptionChar
kt_test_start "GetNonOptions with custom OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +v file1.txt file2.txt +h
myapp.GetNonOptions "vh" ""
result=$RESULT
# Should find file1.txt and file2.txt as non-options
if [[ "$result" == "2" ]]; then
    kt_test_pass "GetNonOptions works with custom OptionChar"
else
    kt_test_fail "GetNonOptions with custom OptionChar failed: $result (expected 2)"
fi
myapp.delete

# Test: Mixed OptionChar doesn't affect recognition
kt_test_start "OptionChar change doesn't affect dash-prefixed args"
TCustomApplication.new myapp
myapp.property OptionChar = "/"
myapp.SetArgs -v file.txt  # Using - but app expects /
myapp.FindOptionIndex "v" ""
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "Changed OptionChar correctly ignores different prefix"
else
    kt_test_fail "OptionChar distinction failed: found at $result (expected -1)"
fi
myapp.delete

# Test: GetOptionValues with custom OptionChar
kt_test_start "GetOptionValues with + as OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +f file1 +f file2 +f file3
declare -a oc_vals=()
myapp.GetOptionValues "f" "" oc_vals
result=$RESULT
# FPC GetOptionAtIndex compares the next argument's first character with
# OptionChar, so a '+' prefix is honoured there too (the report's A15 note that
# FPC hard-codes '-' is wrong: custapp.pp uses the OptionChar property).
if [[ "$result" == "3" && "${oc_vals[*]}" == "file3 file2 file1" ]]; then
    kt_test_pass "GetOptionValues works with custom OptionChar"
else
    kt_test_fail "GetOptionValues with custom OptionChar failed: $result (${oc_vals[*]:-})"
fi
myapp.delete

kt_test_start "a value starting with the custom OptionChar is not a value"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs +c +v
myapp.GetOptionValue "c" ""
plus_value=$RESULT
myapp.SetArgs +c -v
myapp.GetOptionValue "c" ""
dash_value=$RESULT
if [[ -z "$plus_value" && "$dash_value" == "-v" ]]; then
    kt_test_pass "GetOptionAtIndex compares against OptionChar, not a hard-coded '-'"
else
    kt_test_fail "OptionChar in GetOptionAtIndex: '+c +v'='$plus_value' (expected empty), '+c -v'='$dash_value' (expected -v)"
fi
myapp.delete

# Test: OptionChar with long option equals syntax
kt_test_start "Long options with = and custom OptionChar"
TCustomApplication.new myapp
myapp.property OptionChar = "+"
myapp.SetArgs ++config=value.conf
myapp.FindOptionIndex "" "config"
result=$RESULT
myapp.GetOptionValue "" "config"
value=$RESULT
if [[ "$result" == "1" && "$value" == "value.conf" ]]; then
    kt_test_pass "Long option with = works with custom OptionChar"
else
    kt_test_fail "Long option with custom OptionChar and =: index=$result (expected 1), value='$value' (expected value.conf)"
fi
myapp.delete

kt_test_log "023_OptionCharTests.sh completed"
