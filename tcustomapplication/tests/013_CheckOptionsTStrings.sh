#!/bin/bash
# 013_CheckOptionsTStrings.sh - Test TCustomApplication CheckOptions overloads with TStrings parameters
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


kt_test_section "013: TCustomApplication CheckOptions with TStrings Parameters"

# Test: CheckOptions with TStrings Longopts (array parameters)
kt_test_start "CheckOptions with TStrings Longopts array"
TCustomApplication.new myapp
# Set command-line arguments with proper format
myapp.SetArgs --help --version
# Create mock TStrings for Longopts
declare -a longopts_list=("help" "version" "verbose")
declare -a opts_list
declare -a nonopts_list
myapp.CheckOptions "" longopts_list opts_list nonopts_list
error_msg=$RESULT
# FPC fills Opts with `name=value` for the options that actually TOOK a value
# and with nothing else, so two switches leave it empty.
if [[ -z "$error_msg" && ${#opts_list[@]} -eq 0 && ${#nonopts_list[@]} -eq 0 ]]; then
    kt_test_pass "no error, and two switches add nothing to Opts"
else
    kt_test_fail "CheckOptions with TStrings arrays: err='$error_msg' opts=(${opts_list[*]:-}) non=(${nonopts_list[*]:-})"
fi
myapp.delete

kt_test_start "CheckOptions fills Opts with name=value for options that took one"
TCustomApplication.new myapp
myapp.SetArgs --config=data.ini -o out.txt --help rest.txt
declare -a longopts_val=("config:" "help")
declare -a opts_val=() nonopts_val=()
myapp.CheckOptions "o:" longopts_val opts_val nonopts_val
error_msg=$RESULT
if [[ -z "$error_msg" && "${opts_val[*]}" == "config=data.ini o=out.txt" && "${nonopts_val[*]}" == "rest.txt" ]]; then
    kt_test_pass "Opts=(config=data.ini o=out.txt), NonOpts=(rest.txt)"
else
    kt_test_fail "Opts/NonOpts wrong: err='$error_msg' opts=(${opts_val[*]:-}) non=(${nonopts_val[*]:-})"
fi
myapp.delete

# Test: CheckOptions with TStrings Longopts and invalid options
kt_test_start "CheckOptions with TStrings detects invalid long option"
TCustomApplication.new myapp
myapp.SetArgs --invalid --version
declare -a longopts_invalid=("help" "version")
declare -a opts_invalid
declare -a nonopts_invalid
myapp.CheckOptions "" longopts_invalid opts_invalid nonopts_invalid
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with TStrings detects invalid long options"
else
    kt_test_fail "CheckOptions with TStrings failed to detect invalid long options"
fi
myapp.delete

# Test: CheckOptions with TStrings and AllErrors true
kt_test_start "CheckOptions with TStrings and AllErrors"
TCustomApplication.new myapp
myapp.SetArgs --invalid
declare -a longopts_all=("help" "version")
declare -a opts_all
declare -a nonopts_all
myapp.CheckOptions "" longopts_all opts_all nonopts_all
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with TStrings detects all errors"
else
    kt_test_fail "CheckOptions with TStrings failed to detect errors"
fi
myapp.delete

# Test: CheckOptions with array Longopts (another overload)
kt_test_start "CheckOptions with array Longopts"
TCustomApplication.new myapp
myapp.SetArgs --help --version
declare -a longopts_array=("help" "version" "verbose")
declare -a opts_array
declare -a nonopts_array
myapp.CheckOptions "" longopts_array opts_array nonopts_array
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions with array Longopts works"
else
    kt_test_fail "CheckOptions with array Longopts error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with string LongOpts (space separated)
kt_test_start "CheckOptions with string LongOpts"
TCustomApplication.new myapp
myapp.SetArgs --help
myapp.CheckOptions "" "help version verbose" "false"
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts works"
else
    kt_test_fail "CheckOptions with string LongOpts error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with string LongOpts invalid
kt_test_start "CheckOptions with string LongOpts detects invalid"
TCustomApplication.new myapp
myapp.SetArgs --invalid
myapp.CheckOptions "" "help version" "false"
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts detects invalid options"
else
    kt_test_fail "CheckOptions with string LongOpts failed to detect invalid"
fi
myapp.delete

# Test: CheckOptions with string LongOpts and AllErrors
kt_test_start "CheckOptions with string LongOpts and AllErrors"
TCustomApplication.new myapp
myapp.SetArgs --invalid
myapp.CheckOptions "" "help version" "true"
error_msg=$RESULT
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts and AllErrors detects errors"
else
    kt_test_fail "CheckOptions with string LongOpts and AllErrors failed"
fi
myapp.delete

# Test: CheckOptions with both long options allowed
kt_test_start "CheckOptions with both long options allowed"
TCustomApplication.new myapp
myapp.SetArgs --help --version
myapp.CheckOptions "" "help version" "false"
error1=$RESULT
if [[ -z "$error1" ]]; then
    kt_test_pass "CheckOptions with both long options works"
else
    kt_test_fail "CheckOptions with both long options failed: error=$error1"
fi
myapp.delete

# --- TCA-08: array-vs-string is decided by the LongOpts argument alone -------
kt_test_start "LongOpts array is recognised without any output arrays [TCA-08]"
TCustomApplication.new myapp
myapp.SetArgs --help
declare -a lo=(help version)
declare -a o=() n=()
myapp.CheckOptions "" lo o n
with_arrays=$RESULT
myapp.CheckOptions "" lo
without_arrays=$RESULT
myapp.CheckOptions "" lo "false"
with_allerrors=$RESULT
if [[ -z "$with_arrays" && -z "$without_arrays" && -z "$with_allerrors" ]]; then
    kt_test_pass "the same array name is an array in all three call shapes"
else
    kt_test_fail "array coupling: with_arrays='$with_arrays' without='$without_arrays' allerrors='$with_allerrors'"
fi
myapp.delete

kt_test_start "an EMPTY LongOpts array is empty, not one anonymous option [TCA-08]"
TCustomApplication.new myapp
myapp.SetArgs --
declare -a empty_lo=()
declare -a eo=() en=()
myapp.CheckOptions "" empty_lo eo en
err=$RESULT
if [[ "$err" == 'Invalid option at position 1: ""' && ${#en[@]} -eq 0 ]]; then
    kt_test_pass "'--' is an invalid option even with an empty long-option array"
else
    kt_test_fail "empty array handling: err='$err' non=(${en[*]:-})"
fi
myapp.delete

kt_test_start "a scalar variable whose name is passed is treated as a string"
TCustomApplication.new myapp
myapp.SetArgs --help
help="not an array"
myapp.CheckOptions "" help
err=$RESULT
unset help
if [[ -z "$err" ]]; then
    kt_test_pass "'help' is the long option name, not the scalar's value"
else
    kt_test_fail "scalar LongOpts mis-handled: '$err'"
fi
myapp.delete

kt_test_start "LongOpts string splits on space, tab, CR and LF (FPC SepChars)"
TCustomApplication.new myapp
myapp.SetArgs --help --version --verbose
myapp.CheckOptions "" "$(printf 'help\tversion\nverbose')"
err=$RESULT
if [[ -z "$err" ]]; then
    kt_test_pass "tab- and newline-separated long options are accepted"
else
    kt_test_fail "SepChars splitting failed: '$err'"
fi
myapp.delete

kt_test_log "013_CheckOptionsTStrings.sh completed"