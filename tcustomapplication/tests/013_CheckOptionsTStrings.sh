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

# Test: CheckOptions with TStrings Longopts
kt_test_start "CheckOptions with TStrings Longopts"
TCustomApplication.new myapp
# Set command-line arguments with proper format
myapp.SetArgs -- --help --version
# Create mock TStrings for Longopts
declare -a longopts_list=("help" "version" "verbose")
declare -a opts_list
declare -a nonopts_list
error_msg=$(myapp.CheckOptions "" longopts_list opts_list nonopts_list "false")
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions with TStrings Longopts returns no error"
else
    kt_test_fail "CheckOptions with TStrings Longopts unexpected error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with TStrings Longopts and invalid options
kt_test_start "CheckOptions with TStrings Longopts invalid"
TCustomApplication.new myapp
myapp.SetArgs -- -h:v:
declare -a longopts_invalid=("help" "version")
declare -a opts_invalid
declare -a nonopts_invalid
error_msg=$(myapp.CheckOptions "h:v:" longopts_invalid opts_invalid nonopts_invalid "false")
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with TStrings detects invalid options"
else
    kt_test_fail "CheckOptions with TStrings failed to detect invalid options"
fi
myapp.delete

# Test: CheckOptions with TStrings and AllErrors true
kt_test_start "CheckOptions with TStrings and AllErrors"
TCustomApplication.new myapp
myapp.SetArgs -- -h:v:
declare -a longopts_all=("help" "version")
declare -a opts_all
declare -a nonopts_all
error_msg=$(myapp.CheckOptions "h:v:" longopts_all opts_all nonopts_all "true")
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with TStrings and AllErrors works"
else
    kt_test_fail "CheckOptions with TStrings and AllErrors failed"
fi
myapp.delete

# Test: CheckOptions with array Longopts (another overload)
kt_test_start "CheckOptions with array Longopts"
TCustomApplication.new myapp
myapp.SetArgs -- --help --version
declare -a longopts_array=("help" "version" "verbose")
declare -a opts_array
declare -a nonopts_array
error_msg=$(myapp.CheckOptions "" longopts_array opts_array nonopts_array "false")
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
error_msg=$(myapp.CheckOptions "" "help version verbose" "false")
if [[ -z "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts works"
else
    kt_test_fail "CheckOptions with string LongOpts error: $error_msg"
fi
myapp.delete

# Test: CheckOptions with string LongOpts invalid
kt_test_start "CheckOptions with string LongOpts invalid"
TCustomApplication.new myapp
myapp.SetArgs -- -h:v:
error_msg=$(myapp.CheckOptions "h:v:" "help version" "false")
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts detects invalid"
else
    kt_test_fail "CheckOptions with string LongOpts failed to detect invalid"
fi
myapp.delete

# Test: CheckOptions with string LongOpts and AllErrors
kt_test_start "CheckOptions with string LongOpts and AllErrors"
TCustomApplication.new myapp
myapp.SetArgs -- -h:v:
error_msg=$(myapp.CheckOptions "h:v:" "help version" "true")
if [[ -n "$error_msg" ]]; then
    kt_test_pass "CheckOptions with string LongOpts and AllErrors works"
else
    kt_test_fail "CheckOptions with string LongOpts and AllErrors failed"
fi
myapp.delete

# Test: CheckOptions multiple calls
kt_test_start "CheckOptions multiple calls"
TCustomApplication.new myapp
myapp.SetArgs -- --help --version
error1=$(myapp.CheckOptions "" "help" "false")
error2=$(myapp.CheckOptions "" "version" "false")
if [[ -z "$error1" && -z "$error2" ]]; then
    kt_test_pass "Multiple CheckOptions calls work"
else
    kt_test_fail "Multiple CheckOptions calls failed: error1=$error1, error2=$error2"
fi
myapp.delete

kt_test_log "013_CheckOptionsTStrings.sh completed"