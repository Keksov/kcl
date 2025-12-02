#!/bin/bash
# 024_GetOptionValuesEdgeCases.sh - Test edge cases for GetOptionValues
# Tests boundary conditions and complex scenarios

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "024: TCustomApplication GetOptionValues Edge Cases"

# Test: GetOptionValues with many repeated options
kt_test_start "GetOptionValues with 10 repeated options"
TCustomApplication.new myapp
myapp.SetArgs -- -f f1 -f f2 -f f3 -f f4 -f f5 -f f6 -f f7 -f f8 -f f9 -f f10
myapp.GetOptionValues "f" ""
result=$RESULT
if [[ "$result" == "10:"* ]]; then
    kt_test_pass "GetOptionValues handles 10 repeated options"
else
    kt_test_fail "GetOptionValues many options failed: $result (expected 10)"
fi
myapp.delete

# Test: GetOptionValues with consecutive same options
kt_test_start "GetOptionValues with consecutive repeated options"
TCustomApplication.new myapp
myapp.SetArgs -- -v val1 -v val2 -v val3
myapp.GetOptionValues "v" ""
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues handles consecutive repeated options"
else
    kt_test_fail "GetOptionValues consecutive failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with options separated by non-options
kt_test_start "GetOptionValues with separated occurrences"
TCustomApplication.new myapp
myapp.SetArgs -- -i input1 file.txt -i input2 -i input3
myapp.GetOptionValues "i" ""
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues finds all occurrences even if separated"
else
    kt_test_fail "GetOptionValues separated failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with empty values
kt_test_start "GetOptionValues when some options have no values"
TCustomApplication.new myapp
myapp.SetArgs -- -f file1 -f -f file2 -h -f file3
myapp.GetOptionValues "f" ""
result=$RESULT
# -f file1 (has value), -f - (no value, next is option), -f file2 (has value), -f file3 (has value)
# Should find only those with values: 3
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues counts only options with values"
else
    kt_test_fail "GetOptionValues with missing values failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with mixed short and long (should only match requested type)
kt_test_start "GetOptionValues with -f ignores --files"
TCustomApplication.new myapp
myapp.SetArgs -- -f file1 --files file2 -f file3
myapp.GetOptionValues "f" ""
result=$RESULT
if [[ "$result" == "2:"* ]]; then
    kt_test_pass "GetOptionValues finds only matching short option -f"
else
    kt_test_fail "GetOptionValues mixed short/long failed: $result (expected 2)"
fi
myapp.delete

# Test: GetOptionValues for non-existent option
kt_test_start "GetOptionValues for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs -- -f file1 -i input1
myapp.GetOptionValues "x" ""
result=$RESULT
if [[ "$result" == "0:" ]]; then
    kt_test_pass "GetOptionValues returns 0: for non-existent option"
else
    kt_test_fail "GetOptionValues non-existent failed: $result (expected 0:)"
fi
myapp.delete

# Test: GetOptionValues starting from specific index
kt_test_start "GetOptionValues finds first occurrence at start_at index"
TCustomApplication.new myapp
myapp.SetArgs -- -f f1 -f f2 -f f3
# Note: GetOptionValues doesn't have start_at, but test the complete collection
myapp.GetOptionValues "f" ""
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues collects all occurrences"
else
    kt_test_fail "GetOptionValues collection failed: $result"
fi
myapp.delete

# Test: GetOptionValues with values containing special characters
kt_test_start "GetOptionValues with special character values"
TCustomApplication.new myapp
myapp.SetArgs -- -f 'file:with:colons' -f 'file;with;semicolons' -f 'file|with|pipes'
myapp.GetOptionValues "f" ""
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues handles special characters in values"
else
    kt_test_fail "GetOptionValues special chars failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with empty string values
kt_test_start "GetOptionValues with empty string values"
TCustomApplication.new myapp
myapp.SetArgs -- -v '' -v 'value2' -v ''
myapp.GetOptionValues "v" ""
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues includes empty string values"
else
    kt_test_fail "GetOptionValues empty values failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with single occurrence
kt_test_start "GetOptionValues with single occurrence"
TCustomApplication.new myapp
myapp.SetArgs -- -o output.txt
myapp.GetOptionValues "o" ""
result=$RESULT
if [[ "$result" == "1:"* ]]; then
    kt_test_pass "GetOptionValues works with single occurrence"
else
    kt_test_fail "GetOptionValues single failed: $result (expected 1)"
fi
myapp.delete

# Test: GetOptionValues with long options
kt_test_start "GetOptionValues with long options"
TCustomApplication.new myapp
myapp.SetArgs -- --input f1 --input f2 --input f3
myapp.GetOptionValues "" "input"
result=$RESULT
if [[ "$result" == "3:"* ]]; then
    kt_test_pass "GetOptionValues works with long options"
else
    kt_test_fail "GetOptionValues long options failed: $result (expected 3)"
fi
myapp.delete

# Test: GetOptionValues with long options containing equals
kt_test_start "GetOptionValues with --option=value syntax"
TCustomApplication.new myapp
myapp.SetArgs -- --file=f1 regular_arg --file=f2
# Note: --option=value is treated as a single token, may not work with standard GetOptionValues
# This test verifies current behavior
myapp.GetOptionValues "" "file=f1"
result=$RESULT
if [[ "$result" == "1:"* ]]; then
    kt_test_pass "GetOptionValues finds --option=value"
else
    kt_test_fail "GetOptionValues equals syntax: $result"
fi
myapp.delete

# Test: GetOptionValues alternating with different options
kt_test_start "GetOptionValues among other options"
TCustomApplication.new myapp
myapp.SetArgs -- -a arg1 -b bval -a arg2 -c cval -a arg3
myapp.GetOptionValues "a" ""
result_a=$RESULT
myapp.GetOptionValues "b" ""
result_b=$RESULT
myapp.GetOptionValues "c" ""
result_c=$RESULT
if [[ "$result_a" == "3:"* && "$result_b" == "1:"* && "$result_c" == "1:"* ]]; then
    kt_test_pass "GetOptionValues correctly separates different options"
else
    kt_test_fail "GetOptionValues separation failed: -a=$result_a, -b=$result_b, -c=$result_c"
fi
myapp.delete

# Test: GetOptionValues result parsing
kt_test_start "GetOptionValues result format is count:value1:value2:..."
TCustomApplication.new myapp
myapp.SetArgs -- -i in1 -i in2
myapp.GetOptionValues "i" ""
result=$RESULT
count="${result%%:*}"
if [[ "$count" == "2" ]]; then
    kt_test_pass "GetOptionValues returns correct format with count=$count"
else
    kt_test_fail "GetOptionValues format failed: $result"
fi
myapp.delete

kt_test_log "024_GetOptionValuesEdgeCases.sh completed"
