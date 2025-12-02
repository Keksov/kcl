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
myapp.SetArgs -- --help --version
# Create mock TStrings for Longopts
declare -a longopts_list=("help" "version" "verbose")
declare -a opts_list
declare -a nonopts_list
myapp.CheckOptions "" longopts_list opts_list nonopts_list
error_msg=$RESULT
if [[ -z "$error_msg" ]]; then
    # Also verify arrays were filled correctly
    if [[ ${#opts_list[@]} -eq 2 && "${opts_list[0]}" == "--help" && "${opts_list[1]}" == "--version" ]]; then
        kt_test_pass "CheckOptions with TStrings arrays returns no error and fills arrays"
    else
        kt_test_fail "CheckOptions arrays not filled correctly: opts_list=(${opts_list[@]})"
    fi
else
    kt_test_fail "CheckOptions with TStrings arrays unexpected error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with TStrings Longopts and invalid options
kt_test_start "CheckOptions with TStrings detects invalid long option"
TCustomApplication.new myapp
myapp.SetArgs -- --invalid --version
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
myapp.SetArgs -- --invalid
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
myapp.SetArgs -- --help --version
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
myapp.SetArgs -- --help
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
myapp.SetArgs -- --invalid
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
myapp.SetArgs -- --invalid
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
myapp.SetArgs -- --help --version
myapp.CheckOptions "" "help version" "false"
error1=$RESULT
if [[ -z "$error1" ]]; then
    kt_test_pass "CheckOptions with both long options works"
else
    kt_test_fail "CheckOptions with both long options failed: error=$error1"
fi
myapp.delete

kt_test_log "013_CheckOptionsTStrings.sh completed"