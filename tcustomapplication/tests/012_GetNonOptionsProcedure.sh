#!/bin/bash
# 012_GetNonOptionsProcedure.sh - Test TCustomApplication GetNonOptions procedure overload
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

expect_array() {
    local test_name="$1"
    local array_name="$2"
    shift 2
    local -n actual_array="$array_name"
    local expected_array=("$@")

    if (( ${#actual_array[@]} != ${#expected_array[@]} )); then
        kt_test_fail "$test_name (expected ${#expected_array[@]} items, got ${#actual_array[@]}: ${actual_array[*]})"
        return
    fi

    local i
    for ((i = 0; i < ${#expected_array[@]}; i++)); do
        if [[ "${actual_array[$i]}" != "${expected_array[$i]}" ]]; then
            kt_test_fail "$test_name (item $i expected '${expected_array[$i]}', got '${actual_array[$i]}')"
            return
        fi
    done

    kt_test_pass "$test_name"
}

kt_test_section "012: TCustomApplication GetNonOptions Procedure Overload"

# Test: GetNonOptions procedure with basic options
kt_test_start "GetNonOptions procedure with basic options"
TCustomApplication.new myapp
declare -a non_options_list
myapp.SetArgs -- -h file1.txt --help file2.txt --version
myapp.GetNonOptions "h" "help version" non_options_list
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with basic options" non_options_list "file1.txt" "file2.txt"
else
    kt_test_fail "GetNonOptions procedure with basic options count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with required value options
kt_test_start "GetNonOptions procedure with required value options"
TCustomApplication.new myapp
declare -a non_options_req
myapp.SetArgs -- -h help.txt -v version.txt tail.txt
myapp.GetNonOptions "h:v:" "help version" non_options_req
result=$RESULT
if [[ "$result" == "3" ]]; then
    expect_array "GetNonOptions procedure with required value options" non_options_req "help.txt" "version.txt" "tail.txt"
else
    kt_test_fail "GetNonOptions procedure with required value options count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with optional value options
kt_test_start "GetNonOptions procedure with optional value options"
TCustomApplication.new myapp
declare -a non_options_opt
myapp.SetArgs -- -h -v maybe.txt tail.txt
myapp.GetNonOptions "h::v::" "help version" non_options_opt
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with optional value options" non_options_opt "maybe.txt" "tail.txt"
else
    kt_test_fail "GetNonOptions procedure with optional value options count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with complex option string
kt_test_start "GetNonOptions procedure with complex option string"
TCustomApplication.new myapp
declare -a non_options_complex
myapp.SetArgs -- -a alpha.txt --alpha beta.txt -d delta.txt gamma.txt
myapp.GetNonOptions "abc:def::ghi" "alpha beta gamma" non_options_complex
result=$RESULT
if [[ "$result" == "4" ]]; then
    expect_array "GetNonOptions procedure with complex option string" non_options_complex "alpha.txt" "beta.txt" "delta.txt" "gamma.txt"
else
    kt_test_fail "GetNonOptions procedure with complex option string count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with empty short options
kt_test_start "GetNonOptions procedure with empty short options"
TCustomApplication.new myapp
declare -a non_options_empty_short
myapp.SetArgs -- --help file1.txt --version file2.txt
myapp.GetNonOptions "" "help version" non_options_empty_short
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with empty short options" non_options_empty_short "file1.txt" "file2.txt"
else
    kt_test_fail "GetNonOptions procedure with empty short options count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with empty long options
kt_test_start "GetNonOptions procedure with empty long options"
TCustomApplication.new myapp
declare -a non_options_empty_long
myapp.SetArgs -- -h file1.txt file2.txt
myapp.GetNonOptions "h" "" non_options_empty_long
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with empty long options" non_options_empty_long "file1.txt" "file2.txt"
else
    kt_test_fail "GetNonOptions procedure with empty long options count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure with both empty
kt_test_start "GetNonOptions procedure with both empty"
TCustomApplication.new myapp
declare -a non_options_both_empty
myapp.SetArgs -- file1.txt file2.txt
myapp.GetNonOptions "" "" non_options_both_empty
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with both empty" non_options_both_empty "file1.txt" "file2.txt"
else
    kt_test_fail "GetNonOptions procedure with both empty count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions procedure multiple calls
kt_test_start "GetNonOptions procedure multiple calls"
TCustomApplication.new myapp
declare -a non_options1
declare -a non_options2
myapp.SetArgs -- -h first.txt
myapp.GetNonOptions "h" "help" non_options1
first_result=$RESULT
myapp.SetArgs -- -v second.txt
myapp.GetNonOptions "v" "version" non_options2
second_result=$RESULT
if [[ "$first_result" == "1" && "$second_result" == "1" && "${non_options1[0]}" == "first.txt" && "${non_options2[0]}" == "second.txt" ]]; then
    kt_test_pass "GetNonOptions procedure multiple calls"
else
    kt_test_fail "GetNonOptions procedure multiple calls failed: first=$first_result:${non_options1[*]} second=$second_result:${non_options2[*]}"
fi
myapp.delete

# Test: GetNonOptions procedure with case sensitivity
kt_test_start "GetNonOptions procedure with case sensitivity"
TCustomApplication.new myapp
declare -a non_options_case
myapp.SetArgs -- -H upper.txt --HELP long.txt
myapp.GetNonOptions "H" "HELP" non_options_case
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions procedure with case sensitivity" non_options_case "upper.txt" "long.txt"
else
    kt_test_fail "GetNonOptions procedure with case sensitivity count mismatch: $result"
fi
myapp.delete

kt_test_log "012_GetNonOptionsProcedure.sh completed"