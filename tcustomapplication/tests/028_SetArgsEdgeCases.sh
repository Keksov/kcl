#!/bin/bash
# 028_SetArgsEdgeCases.sh - Test SetArgs method edge cases
# Tests various boundary conditions for SetArgs initialization

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "028: TCustomApplication SetArgs Edge Cases"

# Test: SetArgs with no arguments
kt_test_start "SetArgs with no arguments"
TCustomApplication.new myapp
myapp.SetArgs --
# Should result in empty args array
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "SetArgs with empty args creates empty array"
else
    kt_test_fail "Empty SetArgs failed: $result"
fi
myapp.delete

# Test: SetArgs with single argument
kt_test_start "SetArgs with single argument"
TCustomApplication.new myapp
myapp.SetArgs -- "single_arg"
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "false" ]]; then
    kt_test_pass "SetArgs single argument stored"
else
    kt_test_fail "Single argument test failed"
fi
myapp.delete

# Test: SetArgs called multiple times (should replace)
kt_test_start "SetArgs called multiple times replaces previous args"
TCustomApplication.new myapp
myapp.SetArgs -- -v old_value
myapp.SetArgs -- -h new_value
myapp.FindOptionIndex "v" "" 0
result_v=$RESULT
myapp.FindOptionIndex "h" "" 0
result_h=$RESULT
if [[ "$result_v" == "-1" && "$result_h" == "0" ]]; then
    kt_test_pass "Second SetArgs replaced first arguments"
else
    kt_test_fail "Multiple SetArgs failed: -v=$result_v (expected -1), -h=$result_h (expected 0)"
fi
myapp.delete

# Test: SetArgs with many arguments
kt_test_start "SetArgs with 50 arguments"
TCustomApplication.new myapp
args="--"
for i in {1..50}; do
    args="$args arg$i"
done
eval "myapp.SetArgs $args"
# Try to find a non-existent option - should be fast
myapp.FindOptionIndex "z" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "SetArgs handles 50 arguments"
else
    kt_test_fail "Large args test failed"
fi
myapp.delete

# Test: SetArgs with special characters
kt_test_start "SetArgs with special shell characters"
TCustomApplication.new myapp
myapp.SetArgs -- '$special' '$(injection)' '`backticks`' 'semicolon;test' 'pipe|test'
# Arguments should be stored as-is without evaluation
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "SetArgs stores special characters safely"
else
    kt_test_fail "Special chars test failed"
fi
myapp.delete

# Test: SetArgs with empty string arguments
kt_test_start "SetArgs with empty string arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "" "value" "" -v
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "3" ]]; then
    kt_test_pass "SetArgs preserves empty string arguments"
else
    kt_test_fail "Empty string args test failed: $result (expected 3)"
fi
myapp.delete

# Test: SetArgs with whitespace-only arguments
kt_test_start "SetArgs with whitespace-only arguments"
TCustomApplication.new myapp
myapp.SetArgs -- "   " "  " $'\t' -v
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "3" ]]; then
    kt_test_pass "SetArgs preserves whitespace arguments"
else
    kt_test_fail "Whitespace args test failed: $result"
fi
myapp.delete

# Test: SetArgs with newlines in arguments
kt_test_start "SetArgs with newline characters"
TCustomApplication.new myapp
myapp.SetArgs -- $'line1\nline2' -h $'multi\nline\nvalue'
myapp.HasOption "h" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "SetArgs preserves newline characters in arguments"
else
    kt_test_fail "Newline args test failed"
fi
myapp.delete

# Test: SetArgs with very long single argument
kt_test_start "SetArgs with very long argument (10KB)"
TCustomApplication.new myapp
long_arg=$(printf 'a%.0s' {1..10000})
myapp.SetArgs -- "-x" "$long_arg"
myapp.FindOptionIndex "x" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "SetArgs handles 10KB argument"
else
    kt_test_fail "Long argument test failed: $result"
fi
myapp.delete

# Test: SetArgs called without -- separator still captures all args
kt_test_start "SetArgs without -- separator still captures arguments"
TCustomApplication.new myapp
myapp.SetArgs -v file.txt
# Without --, all args are still captured (SetArgs starts from position 1 by default)
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "SetArgs captures args correctly even without -- separator"
else
    kt_test_fail "No separator test failed: $result (expected true)"
fi
myapp.delete

# Test: SetArgs with -- as both separator and argument
kt_test_start "SetArgs with -- separator followed by --"
TCustomApplication.new myapp
myapp.SetArgs -- -- file.txt
# First -- is separator, second -- is argument
myapp.FindOptionIndex "v" "" 0
result=$RESULT
if [[ "$result" == "-1" ]]; then
    kt_test_pass "Double -- handled correctly"
else
    kt_test_fail "Double -- test failed"
fi
myapp.delete

# Test: SetArgs after Initialize
kt_test_start "SetArgs called after Initialize"
TCustomApplication.new myapp
myapp.Initialize
myapp.SetArgs -- -v value.txt
myapp.HasOption "v" ""
result=$RESULT
if [[ "$result" == "true" ]]; then
    kt_test_pass "SetArgs works after Initialize"
else
    kt_test_fail "SetArgs after Initialize failed"
fi
myapp.delete

# Test: Args with Unicode characters
kt_test_start "SetArgs with Unicode characters"
TCustomApplication.new myapp
myapp.SetArgs -- -u 'café' '日本語' '🚀 rocket'
myapp.FindOptionIndex "u" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "SetArgs handles Unicode arguments"
else
    kt_test_fail "Unicode args test failed"
fi
myapp.delete

# Test: SetArgs with mixed quoted and unquoted
kt_test_start "SetArgs with mixed quoted/unquoted arguments"
TCustomApplication.new myapp
myapp.SetArgs -- -a "quoted arg" unquoted mixed'quoted'
myapp.FindOptionIndex "a" "" 0
result=$RESULT
if [[ "$result" == "0" ]]; then
    kt_test_pass "SetArgs handles mixed quoted arguments"
else
    kt_test_fail "Mixed quoted test failed"
fi
myapp.delete

# Test: SetArgs preserves argument order
kt_test_start "SetArgs preserves exact argument order"
TCustomApplication.new myapp
myapp.SetArgs -- b a d c e
myapp.FindOptionIndex "v" "" 0
result_v=$RESULT
# All should be treated as non-option arguments
if [[ "$result_v" == "-1" ]]; then
    kt_test_pass "SetArgs preserves order of non-option arguments"
else
    kt_test_fail "Order preservation failed"
fi
myapp.delete

# Test: SetArgs with equals signs in values
kt_test_start "SetArgs with equals signs in non-option arguments"
TCustomApplication.new myapp
myapp.SetArgs -- file1=content1 var=value -x opt=val
myapp.FindOptionIndex "x" "" 0
result=$RESULT
if [[ "$result" == "2" ]]; then
    kt_test_pass "SetArgs preserves equals signs in arguments"
else
    kt_test_fail "Equals signs test failed: $result"
fi
myapp.delete

# Test: Multiple calls to SetArgs and args persistence
kt_test_start "Args don't persist after SetArgs replacement"
TCustomApplication.new myapp
myapp.SetArgs -- -a val1
myapp.FindOptionIndex "a" "" 0
result1=$RESULT
myapp.SetArgs -- -b val2
myapp.FindOptionIndex "a" "" 0
result2=$RESULT
if [[ "$result1" == "0" && "$result2" == "-1" ]]; then
    kt_test_pass "SetArgs clears old arguments on new call"
else
    kt_test_fail "Args persistence test failed: before=$result1, after=$result2"
fi
myapp.delete

kt_test_log "028_SetArgsEdgeCases.sh completed"
