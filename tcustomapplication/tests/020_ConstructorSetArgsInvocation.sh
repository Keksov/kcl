#!/bin/bash
# 020_ConstructorSetArgsInvocation.sh - Test that SetArgs in constructor receives actual script arguments
# This test verifies that when TCustomApplication is created with script parameters,
# the constructor's SetArgs call receives the exact same arguments that were passed to the script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "020: TCustomApplication SetArgs Invocation in Constructor"

# Test 1: Constructor SetArgs with single argument
kt_test_start "Constructor receives single argument passed to script"
TCustomApplication.new app1 "myarg"
app1._GetArgs
arg_count="$RESULT"
if [[ "$arg_count" == "1" ]]; then
    kt_test_pass "Constructor SetArgs received 1 argument"
else
    kt_test_fail "Expected 1 argument, but got: $arg_count"
fi
app1.delete

# Test 2: Constructor SetArgs with multiple arguments
kt_test_start "Constructor receives multiple arguments passed to script"
TCustomApplication.new app2 "arg1" "arg2" "arg3"
app2._GetArgs
arg_count="$RESULT"
if [[ "$arg_count" == "3" ]]; then
    kt_test_pass "Constructor SetArgs received 3 arguments"
else
    kt_test_fail "Expected 3 arguments, but got: $arg_count"
fi
app2.delete

# Test 3: Constructor SetArgs with options
kt_test_start "Constructor receives options passed to script"
TCustomApplication.new app3 "--verbose" "-h" "--config" "file.conf"
app3._GetArgs
arg_count="$RESULT"
if [[ "$arg_count" == "4" ]]; then
    kt_test_pass "Constructor SetArgs received 4 option arguments"
else
    kt_test_fail "Expected 4 arguments, but got: $arg_count"
fi
app3.delete

# Test 4: Constructor SetArgs preserves argument order
kt_test_start "Constructor SetArgs preserves exact argument order"
TCustomApplication.new app4 "--verbose" "-h"
app4.FindOptionIndex "" "verbose" 0
verbose_idx="$RESULT"
app4.FindOptionIndex "h" "" 0
h_idx="$RESULT"
if [[ "$verbose_idx" == "0" && "$h_idx" == "1" ]]; then
    kt_test_pass "Constructor SetArgs preserves argument order"
else
    kt_test_fail "Expected order 0:1, but got: $verbose_idx:$h_idx"
fi
app4.delete

# Test 5: Constructor without arguments
kt_test_start "Constructor works correctly when called without arguments"
TCustomApplication.new app5
app5._GetArgs
arg_count="$RESULT"
if [[ "$arg_count" == "0" ]]; then
    kt_test_pass "Constructor SetArgs correctly handles no arguments"
else
    kt_test_fail "Expected 0 arguments, but got: $arg_count"
fi
app5.delete

# Test 6: Constructor SetArgs with mixed arguments
kt_test_start "Constructor receives mixed arguments and preserves them all"
TCustomApplication.new app6 "-v" "--output" "result.txt" "input.txt"
app6._GetArgs
arg_count="$RESULT"
app6.FindOptionIndex "v" "" 0
v_idx="$RESULT"
app6.FindOptionIndex "" "output" 0
output_idx="$RESULT"
if [[ "$arg_count" == "4" && "$v_idx" == "0" && "$output_idx" == "1" ]]; then
    kt_test_pass "Constructor SetArgs preserves all mixed arguments"
else
    kt_test_fail "Expected 4:0:1, but got: $arg_count:$v_idx:$output_idx"
fi
app6.delete

# Test 7: Verify SetArgs is called during construction with real parameters
kt_test_start "Constructor SetArgs called with real parameters from $@"
TCustomApplication.new app7 "--help" "file.txt"
# Access the stored arguments through FindOptionIndex
app7.FindOptionIndex "" "help" 0
help_idx="$RESULT"
if [[ "$help_idx" == "0" ]]; then
    kt_test_pass "Constructor correctly invoked SetArgs with script parameters"
else
    kt_test_fail "Constructor failed to invoke SetArgs: help option not found at index 0"
fi
app7.delete

kt_test_log "020_ConstructorSetArgsInvocation.sh completed"
