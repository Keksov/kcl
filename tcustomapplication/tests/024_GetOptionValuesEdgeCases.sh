#!/bin/bash
# 024_GetOptionValuesEdgeCases.sh - Test GetOptionValues edge cases
#
# GetOptionValues writes a caller array and returns the COUNT in RESULT
# (default R10, kcl README 1.7); the old `"count:v1 v2"` string could not
# represent a value containing a space (finding TCA-07). FPC collects the
# matches by scanning DOWNWARD, so the values arrive last-first.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

# Source tcustomapplication module
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Extract test name from filename
TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

values_are() {   # LABEL COUNT EXPECTED_COUNT EXPECTED_JOINED ARRAYNAME
    local -n arr="$5"
    if [[ "$2" == "$3" && "${arr[*]}" == "$4" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "$1: count=$2 (expected $3), values=(${arr[*]:-}) (expected ($4))"
    fi
}

kt_test_section "024: TCustomApplication GetOptionValues Edge Cases"

kt_test_start "GetOptionValues with 10 repeated options"
TCustomApplication.new myapp
myapp.SetArgs -f f1 -f f2 -f f3 -f f4 -f f5 -f f6 -f f7 -f f8 -f f9 -f f10
declare -a vals=()
myapp.GetOptionValues "f" "" vals
values_are "ten values, last one first" "$RESULT" "10" "f10 f9 f8 f7 f6 f5 f4 f3 f2 f1" vals
myapp.delete

kt_test_start "GetOptionValues with consecutive repeated options"
TCustomApplication.new myapp
myapp.SetArgs -v val1 -v val2 -v val3
declare -a vals=()
myapp.GetOptionValues "v" "" vals
values_are "three consecutive occurrences" "$RESULT" "3" "val3 val2 val1" vals
myapp.delete

kt_test_start "GetOptionValues with separated occurrences"
TCustomApplication.new myapp
myapp.SetArgs -i input1 file.txt -i input2 -i input3
declare -a vals=()
myapp.GetOptionValues "i" "" vals
values_are "occurrences separated by a non-option" "$RESULT" "3" "input3 input2 input1" vals
myapp.delete

kt_test_start "GetOptionValues keeps an occurrence whose value is missing"
TCustomApplication.new myapp
myapp.SetArgs -f file1 -f -f file2 -h -f file3
declare -a vals=()
myapp.GetOptionValues "f" "" vals
# FPC adds one entry per OCCURRENCE, using '' when the next argument is an
# option: -f is at 1, 3, 4 and 7, and the one at 3 is followed by another -f.
values_are "four occurrences, one of them without a value" "$RESULT" "4" "file3 file2  file1" vals
myapp.delete

kt_test_start "GetOptionValues with -f ignores --files"
TCustomApplication.new myapp
myapp.SetArgs -f file1 --files file2 -f file3
declare -a vals=()
myapp.GetOptionValues "f" "" vals
values_are "only the short option matches" "$RESULT" "2" "file3 file1" vals
myapp.delete

kt_test_start "GetOptionValues for non-existent option"
TCustomApplication.new myapp
myapp.SetArgs -f file1 -i input1
declare -a vals=(stale)
myapp.GetOptionValues "x" "" vals
if [[ "$RESULT" == "0" && ${#vals[@]} -eq 0 ]]; then
    kt_test_pass "count 0 and the output array is emptied"
else
    kt_test_fail "GetOptionValues non-existent: count=$RESULT values=(${vals[*]:-})"
fi
myapp.delete

kt_test_start "GetOptionValues without an output array still returns the count"
TCustomApplication.new myapp
myapp.SetArgs -f f1 -f f2 -f f3
myapp.GetOptionValues "f" ""
if [[ "$RESULT" == "3" ]]; then
    kt_test_pass "the output array is optional"
else
    kt_test_fail "GetOptionValues without an array: $RESULT (expected 3)"
fi
myapp.delete

kt_test_start "GetOptionValues with special character values"
TCustomApplication.new myapp
myapp.SetArgs -f 'file:with:colons' -f 'file;with;semicolons' -f 'file|with|pipes'
declare -a vals=()
myapp.GetOptionValues "f" "" vals
values_are "separators inside values are data" "$RESULT" "3" \
    'file|with|pipes file;with;semicolons file:with:colons' vals
myapp.delete

kt_test_start "GetOptionValues with values containing spaces [TCA-07]"
TCustomApplication.new myapp
myapp.SetArgs -f 'a b' -f c -f 'd  e'
declare -a vals=()
myapp.GetOptionValues "f" "" vals
if [[ "$RESULT" == "3" && "${vals[0]}" == "d  e" && "${vals[1]}" == "c" && "${vals[2]}" == "a b" ]]; then
    kt_test_pass "three values, two of them containing spaces, stay three elements"
else
    kt_test_fail "GetOptionValues with spaces: count=$RESULT values=$(declare -p vals)"
fi
myapp.delete

kt_test_start "GetOptionValues with empty string values"
TCustomApplication.new myapp
myapp.SetArgs -v '' -v 'value2' -v ''
declare -a vals=()
myapp.GetOptionValues "v" "" vals
# An empty next argument IS a value in FPC (Copy('',1,1) is not OptionChar).
if [[ "$RESULT" == "3" && -z "${vals[0]}" && "${vals[1]}" == "value2" && -z "${vals[2]}" ]]; then
    kt_test_pass "empty values are kept as empty elements"
else
    kt_test_fail "GetOptionValues empty values: count=$RESULT $(declare -p vals)"
fi
myapp.delete

kt_test_start "GetOptionValues with single occurrence"
TCustomApplication.new myapp
myapp.SetArgs -o output.txt
declare -a vals=()
myapp.GetOptionValues "o" "" vals
values_are "one occurrence" "$RESULT" "1" "output.txt" vals
myapp.delete

kt_test_start "GetOptionValues with long options needs --name=value [TCA-01]"
TCustomApplication.new myapp
myapp.SetArgs --input=f1 --input=f2 --input=f3
declare -a vals=()
myapp.GetOptionValues "" "input" vals
values_are "three long options with values" "$RESULT" "3" "f3 f2 f1" vals
myapp.SetArgs --input f1 --input f2
declare -a bare=()
myapp.GetOptionValues "" "input" bare
if [[ "$RESULT" == "2" && -z "${bare[0]}" && -z "${bare[1]}" ]]; then
    kt_test_pass "space-separated long options are found but have no value"
else
    kt_test_fail "bare long options: count=$RESULT $(declare -p bare)"
fi
myapp.delete

kt_test_start "GetOptionValues with --option=value syntax"
TCustomApplication.new myapp
myapp.SetArgs --file=f1 regular_arg --file=f2
declare -a vals=()
myapp.GetOptionValues "" "file" vals
values_are "the option name stops at the '='" "$RESULT" "2" "f2 f1" vals
myapp.delete

kt_test_start "GetOptionValues among other options"
TCustomApplication.new myapp
myapp.SetArgs -a arg1 -b bval -a arg2 -c cval -a arg3
declare -a va=() vb=() vc=()
myapp.GetOptionValues "a" "" va
count_a=$RESULT
myapp.GetOptionValues "b" "" vb
count_b=$RESULT
myapp.GetOptionValues "c" "" vc
count_c=$RESULT
if [[ "$count_a" == "3" && "${va[*]}" == "arg3 arg2 arg1" && "$count_b" == "1" && "${vb[*]}" == "bval" && "$count_c" == "1" && "${vc[*]}" == "cval" ]]; then
    kt_test_pass "GetOptionValues correctly separates different options"
else
    kt_test_fail "separation failed: a=$count_a(${va[*]:-}) b=$count_b(${vb[*]:-}) c=$count_c(${vc[*]:-})"
fi
myapp.delete

kt_test_start "GetOptionValues collects short AND long occurrences"
TCustomApplication.new myapp
myapp.SetArgs -i one --input=two -i three
declare -a vals=()
myapp.GetOptionValues "i" "input" vals
# FPC collects every short match first, then every long match.
values_are "short matches first, then long ones" "$RESULT" "3" "three one two" vals
myapp.delete

kt_test_start "GetOptionValues rejects a reserved output-array name [README 1.7]"
TCustomApplication.new myapp
myapp.SetArgs -f x
myapp.GetOptionValues "f" "" RESULT
rc_reserved=$?
myapp.GetOptionValues "f" "" "not a name"
rc_bad=$?
myapp.GetOptionValues "f" "" "myapp_data"
rc_own=$?
if [[ "$rc_reserved" == "2" && "$rc_bad" == "2" && "$rc_own" == "2" ]]; then
    kt_test_pass "rc 2 for RESULT, for a non-identifier and for the instance storage"
else
    kt_test_fail "output-name validation: RESULT=$rc_reserved bad=$rc_bad own=$rc_own (all expected 2)"
fi
myapp.delete

kt_test_log "024_GetOptionValuesEdgeCases.sh completed"
