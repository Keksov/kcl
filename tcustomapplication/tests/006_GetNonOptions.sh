#!/bin/bash
# 006_GetNonOptions.sh - Test TCustomApplication GetNonOptions method
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

expect_result() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"

    if [[ "$actual" == "$expected" ]]; then
        kt_test_pass "$test_name"
    else
        kt_test_fail "$test_name (expected: $expected, got: $actual)"
    fi
}

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

kt_test_section "006: TCustomApplication GetNonOptions"

# Test: GetNonOptions with basic options
kt_test_start "GetNonOptions with basic options"
TCustomApplication.new myapp
myapp.SetArgs -h file1.txt --help file2.txt --version
myapp.GetNonOptions "h" "help version"
result=$RESULT
expect_result "GetNonOptions with basic options" "$result" "2"
myapp.delete

# Test: GetNonOptions with required value options — the values are CONSUMED
# by their options (finding TCA-02); before P4 they were counted as non-options.
kt_test_start "GetNonOptions consumes the values of h: and v: [TCA-02]"
TCustomApplication.new myapp
declare -a req_non=()
myapp.SetArgs -h help.txt -v version.txt tail.txt
myapp.GetNonOptions "h:v:" "help version" req_non
result=$RESULT
if [[ "$result" == "1" ]]; then
    expect_array "only tail.txt is left" req_non "tail.txt"
else
    kt_test_fail "GetNonOptions with required value options: got $result, expected 1"
fi
myapp.delete

# Test: GetNonOptions with optional value options
kt_test_start "GetNonOptions with optional value options [TCA-02]"
TCustomApplication.new myapp
declare -a opt_non=()
myapp.SetArgs -h -v maybe.txt tail.txt
myapp.GetNonOptions "h::v::" "help version" opt_non
result=$RESULT
# -h has no value (the next argument is an option); -v takes maybe.txt.
if [[ "$result" == "1" ]]; then
    expect_array "only tail.txt is left" opt_non "tail.txt"
else
    kt_test_fail "GetNonOptions with optional value options: got $result, expected 1"
fi
myapp.delete

# Test: an invalid option makes GetNonOptions fail (FPC raises EListError)
kt_test_start "GetNonOptions reports an invalid option as rc 1 [TCA-13, D2]"
TCustomApplication.new myapp
declare -a bad_non=(untouched)
myapp.SetArgs - file.txt
RESULT="untouched"
if myapp.GetNonOptions "v" "" bad_non; then
    kt_test_fail "a lone '-' was accepted as a non-option (RESULT=$RESULT)"
elif [[ -n "$RESULT" ]]; then
    kt_test_fail "RESULT should be empty on the error path, got '$RESULT'"
elif [[ "${bad_non[*]}" != "untouched" ]]; then
    kt_test_fail "the output array was written on the error path: ${bad_non[*]}"
else
    kt_test_pass "rc 1, RESULT empty, output array untouched"
fi
myapp.delete

# Test: GetNonOptions with TStrings parameter
kt_test_start "GetNonOptions with TStrings parameter"
TCustomApplication.new myapp
declare -a non_options_list
myapp.SetArgs -h file1.txt file2.txt
myapp.GetNonOptions "h" "help" non_options_list
result=$RESULT
if [[ "$result" == "2" ]]; then
    expect_array "GetNonOptions with TStrings parameter" non_options_list "file1.txt" "file2.txt"
else
    kt_test_fail "GetNonOptions with TStrings parameter count mismatch: $result"
fi
myapp.delete

# Test: GetNonOptions with complex option string
kt_test_start "GetNonOptions with complex option string"
TCustomApplication.new myapp
myapp.SetArgs -a alpha.txt --alpha beta.txt -d delta.txt gamma.txt
myapp.GetNonOptions "abc:def::ghi" "alpha beta gamma"
result=$RESULT
expect_result "GetNonOptions with complex option string" "$result" "4"
myapp.delete

# Test: GetNonOptions with empty short options
kt_test_start "GetNonOptions with empty short options"
TCustomApplication.new myapp
myapp.SetArgs --help file1.txt --version file2.txt
myapp.GetNonOptions "" "help version"
result=$RESULT
expect_result "GetNonOptions with empty short options" "$result" "2"
myapp.delete

# Test: GetNonOptions with empty long options
kt_test_start "GetNonOptions with empty long options"
TCustomApplication.new myapp
myapp.SetArgs -h file1.txt file2.txt
myapp.GetNonOptions "h" ""
result=$RESULT
expect_result "GetNonOptions with empty long options" "$result" "2"
myapp.delete

# Test: GetNonOptions with both empty
kt_test_start "GetNonOptions with both empty"
TCustomApplication.new myapp
myapp.SetArgs file1.txt file2.txt
myapp.GetNonOptions "" ""
result=$RESULT
expect_result "GetNonOptions with both empty" "$result" "2"
myapp.delete

# Test: GetNonOptions multiple calls
kt_test_start "GetNonOptions multiple calls"
TCustomApplication.new myapp
myapp.SetArgs -h first.txt
myapp.GetNonOptions "h" "help"
result1=$RESULT
myapp.SetArgs -v second.txt
myapp.GetNonOptions "v" "version"
result2=$RESULT
if [[ "$result1" == "1" && "$result2" == "1" ]]; then
    kt_test_pass "GetNonOptions multiple calls"
else
    kt_test_fail "GetNonOptions multiple calls failed: result1=$result1, result2=$result2"
fi
myapp.delete

# Test: GetNonOptions with case sensitivity
kt_test_start "GetNonOptions with case sensitivity"
TCustomApplication.new myapp
myapp.SetArgs -H upper.txt --HELP long.txt
myapp.GetNonOptions "H" "HELP"
result=$RESULT
expect_result "GetNonOptions with case sensitivity" "$result" "2"
myapp.delete

kt_test_log "006_GetNonOptions.sh completed"