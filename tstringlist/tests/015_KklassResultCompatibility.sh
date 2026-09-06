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

# REWRITTEN for the 2026-09-06 review (finding G1-17): this used to scan for
# `method Assign '{`, the pre-Pascal-DSL syntax that no longer exists anywhere
# in the file — the collected block was always empty, so the assertion could
# not fail. It now reads the REAL body of the two bulk-copy members and pins
# what the finding is about: no `eval`, and no `$( )` (finding G1-11 — the
# source count came from `$($source.count)`, one fork per call).
body_of() {   # FUNCTION_NAME -> the body text of that function in the unit
    local fn="$1" src="$TSTRINGLIST_DIR/tstringlist.sh" line out="" in_fn=0
    while IFS= read -r line; do
        if (( in_fn == 0 )); then
            [[ "$line" == "$fn() {" ]] && in_fn=1
            continue
        fi
        [[ "$line" == "}" ]] && break
        out+="$line"$'\n'
    done < "$src"
    printf '%s' "$out"
}

for member in Assign AddStrings; do
    kt_test_start "TStringList.$member copies without eval and without a fork [G1-17, G1-11]"
    block="$(body_of "TStringList.$member")"
    problems=""
    [[ -z "$block" ]] && problems+="body not found; "
    [[ "$block" == *"eval"* ]] && problems+="uses eval; "
    # strip the comment lines, then arithmetic expansion (which is NOT a fork),
    # before looking for a command substitution
    payload="$(printf '%s\n' "$block" | grep -v '^[[:space:]]*#')"
    payload="${payload//\$((/ARITH}"
    [[ "$payload" == *'$('* ]] && problems+="uses \$( ) (fork); "
    [[ "$payload" == *'`'* ]] && problems+="uses backticks (fork); "
    if [[ -z "$problems" ]]; then
        kt_test_pass "$(printf '%s' "$block" | grep -c '') lines, no eval, no subshell"
    else
        kt_test_fail "$problems"
    fi
done

kt_test_log "015_KklassResultCompatibility.sh completed"
