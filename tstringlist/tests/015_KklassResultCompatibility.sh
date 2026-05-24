#!/bin/bash
# 015_KklassResultCompatibility.sh - kklass RESULT/stdout compatibility regressions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TSTRINGLIST_DIR="$SCRIPT_DIR/.."
source "$TSTRINGLIST_DIR/tstringlist.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "015: kklass RESULT and stdout compatibility"

kt_test_start "IndexOf in command substitution returns only final result"
TStringList.new result_list
result_list.Add "apple" >/dev/null
result_list.Add "banana" >/dev/null
result_list.Add "cherry" >/dev/null
index_output="$(result_list.IndexOf "banana")"
if [[ "$index_output" == "1" ]]; then
    kt_test_pass "IndexOf command substitution output is clean"
else
    kt_test_fail "IndexOf output was '$index_output', expected '1'"
fi

kt_test_start "Find in command substitution suppresses nested Get and CompareStrings output"
result_list.Sort
find_output="$(result_list.Find "cherry")"
if [[ "$find_output" == "2" ]]; then
    kt_test_pass "Find command substitution output is clean"
else
    kt_test_fail "Find output was '$find_output', expected '2'"
fi

kt_test_start "Sorted Add in command substitution suppresses nested IndexOf and CompareStrings output"
add_output="$(result_list.Add "blueberry")"
if [[ "$add_output" == "2" ]]; then
    kt_test_pass "Sorted Add command substitution output is clean"
else
    kt_test_fail "Sorted Add output was '$add_output', expected '2'"
fi

result_list.delete

kt_test_start "Assign implementation avoids eval-based array copying"
assign_block=""
in_assign=0
while IFS= read -r line; do
    if [[ "$line" == *"method Assign '{"* ]]; then
        in_assign=1
    fi
    if (( in_assign )); then
        assign_block+="$line"$'\n'
        if [[ "$line" == *"}' \\"* ]]; then
            break
        fi
    fi
done < "$TSTRINGLIST_DIR/tstringlist.sh"

if [[ "$assign_block" == *"eval"* ]]; then
    kt_test_fail "Assign still contains eval-based array copying"
else
    kt_test_pass "Assign avoids eval-based array copying"
fi

kt_test_log "015_KklassResultCompatibility.sh completed"
