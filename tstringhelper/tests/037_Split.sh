#!/bin/bash
# 037_Split.sh — rewritten in P5 for finding TSH-03 (and default R9).
#
# What the old file tested: `result=$(string.split "a,b,c" ",")` and then
# `[[ "$result" == *"a"* ]]`. The member joined the parts BACK TOGETHER with
# the separator (`${parts[*]}` under `IFS=$sep`), so its answer for that input
# was the input — the assertion passed on a member that returned nothing
# usable. It also lost everything after the first newline (`read` stops there)
# and treated a multi-character separator as a character SET.
#
# The contract now (kcl/README.md 1.7, R9):
#
#     string.split STR SEP ARRAY [COUNT] [OPTIONS]
#
# fills the caller's ARRAY by nameref and returns the part COUNT in RESULT; a
# malformed or reserved ARRAY name is rc 2 and nothing is written. The
# separator is one literal STRING (FPC's `array of string` overload with a
# single element), COUNT is FPC's ACount (0 = unlimited; the parts beyond it
# are DISCARDED, they do not become a last element), and OPTIONS is FPC's
# TStringSplitOptions: None / ExcludeEmpty / ExcludeLastEmpty.
# Reference: rtl/objpas/sysutils/syshelp.inc, TStringHelper.Split.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Split" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

# split_is TITLE EXPECTED-COUNT EXPECTED-PART... -- ARGS...
split_is() {
    local title="$1" want_count="$2"; shift 2
    local -a want=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do want+=("$1"); shift; done
    shift    # the --
    kt_test_start "$title"
    declare -ga _sp=(sentinel)
    RESULT="__unset__"
    local rc=0
    string.split "$@" >/dev/null 2>&1 || rc=$?
    if (( rc != 0 )); then
        kt_test_fail "$title: rc=$rc"
        return
    fi
    if [[ "$RESULT" != "$want_count" ]]; then
        kt_test_fail "$title: RESULT=$RESULT parts=[${_sp[*]}], expected count $want_count"
        return
    fi
    if (( ${#_sp[@]} != want_count )); then
        kt_test_fail "$title: array holds ${#_sp[@]} elements, RESULT says $RESULT"
        return
    fi
    local i
    for ((i = 0; i < want_count; i++)); do
        if [[ "${_sp[i]}" != "${want[i]}" ]]; then
            kt_test_fail "$title: part $i = '${_sp[i]}', expected '${want[i]}'"
            return
        fi
    done
    kt_test_pass "$title ($want_count parts)"
}

split_is "comma separator: three exact parts [TSH-03]" 3 a b c -- "a,b,c" "," _sp
split_is "a part may contain the character the old code re-joined on [TSH-03]" \
    2 "a b" "c" -- "a b,c" "," _sp
split_is "no separator in the input: one part, the whole string [TSH-03]" \
    1 "hello" -- "hello" "," _sp
split_is "an empty input is ONE empty part (FPC), not zero [TSH-03]" \
    1 "" -- "" "," _sp
split_is "a newline inside a part survives [TSH-03]" \
    3 "a" $'b\nc' "d" -- $'a,b\nc,d' "," _sp
split_is "consecutive separators keep the empty part [TSH-03]" \
    3 "a" "" "c" -- "a,,c" "," _sp
split_is "a trailing separator gives a trailing empty part [TSH-03]" \
    3 "a" "b" "" -- "a,b," "," _sp
split_is "a leading separator gives a leading empty part [TSH-03]" \
    3 "" "a" "b" -- ",a,b" "," _sp
split_is "a MULTI-character separator is one string, not a char set [TSH-03]" \
    2 "a" "b" -- "a, b" ", " _sp
split_is "... and the same input split on ',' alone keeps the space [TSH-03]" \
    2 "a" " b" -- "a, b" "," _sp
split_is "an empty separator: one part, the whole string [TSH-03]" \
    1 "hello,world" -- "hello,world" "" _sp
split_is "pipe separator [TSH-03]" 3 one two three -- "one|two|three" "|" _sp
split_is "space separator keeps empty runs [TSH-03]" \
    3 "hello" "world" "test" -- "hello world test" " " _sp
split_is "values that look like echo options round-trip [TSH-03, X-ECHO]" \
    2 "-n" "-e" -- "-n,-e" "," _sp
split_is "a separator that is a glob metacharacter is literal [TSH-03]" \
    3 a b c -- "a*b*c" "*" _sp

# --- ACount (FPC): the parts beyond the limit are DISCARDED -----------------
split_is "count 2 keeps the first two parts and drops the rest (FPC) [TSH-03]" \
    2 a b -- "a,b,c,d" "," _sp 2
split_is "count 1 keeps only the first part [TSH-03]" \
    1 a -- "a,b,c" "," _sp 1
split_is "count 0 means unlimited (FPC) [TSH-03]" \
    4 a b c d -- "a,b,c,d" "," _sp 0
split_is "a count larger than the number of parts is harmless [TSH-03]" \
    3 a b c -- "a,b,c" "," _sp 99

# --- TStringSplitOptions ----------------------------------------------------
split_is "ExcludeEmpty drops the empty parts [TSH-03]" \
    2 a c -- "a,,c" "," _sp 0 ExcludeEmpty
split_is "ExcludeEmpty drops a leading and a trailing empty part [TSH-03]" \
    2 a b -- ",a,b," "," _sp 0 ExcludeEmpty
split_is "ExcludeLastEmpty drops ONLY the trailing empty part [TSH-03]" \
    3 "" a b -- ",a,b," "," _sp 0 ExcludeLastEmpty
split_is "ExcludeLastEmpty on an input without one changes nothing [TSH-03]" \
    2 a b -- "a,b" "," _sp 0 ExcludeLastEmpty

# --- the output-array name is validated (kcl/README.md 1.7) -----------------
bad_name() {   # TITLE NAME EXPECTED-RC
    local title="$1" name="$2" want="${3:-2}"
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    string.split "a,b" "," "$name" >/dev/null 2>&1 || rc=$?
    if (( rc == want )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "$title (rc $rc)"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' (wanted rc $want)"
    fi
}

bad_name "a missing array name is rc 2 [1.7]"            ""
bad_name "RESULT as the array name is rc 2 [1.7]"        "RESULT"
bad_name "IFS as the array name is rc 2 [1.7]"           "IFS"
bad_name "a __kk_ name is rc 2 [1.7]"                    "__kk_x"
bad_name "the unit's own __tsh_ prefix is rc 2 [1.7]"    "__tsh_x"
bad_name "a name that is not an identifier is rc 2 [1.7]" "1bad"
bad_name "an injection shape as the array name is rc 2 [1.7, X-INJ]" 'a[$(touch pwn037)]'

kt_test_start "a rejected array name executes nothing [X-INJ]"
if [[ ! -e "$SCRIPT_DIR/pwn037" && ! -e "pwn037" ]]; then
    kt_test_pass "no canary file created"
else
    rm -f "$SCRIPT_DIR/pwn037" "pwn037"
    kt_test_fail "the injected command ran"
fi

kt_test_start "an unknown options token is rc 2 and writes nothing [1.2]"
declare -a _sp2=(sentinel)
RESULT="__unset__"
rc=0
string.split "a,b" "," _sp2 0 Bogus >/dev/null 2>&1 || rc=$?
if (( rc == 2 )) && [[ "${_sp2[0]}" == "sentinel" && -z "$RESULT" ]]; then
    kt_test_pass "rc 2, array untouched"
else
    kt_test_fail "rc=$rc array=[${_sp2[*]}] RESULT='$RESULT'"
fi

kt_test_start "a non-numeric count is rc 1 [D1]"
rc=0
string.split "a,b" "," _sp2 abc >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then
    kt_test_pass "rc 1"
else
    kt_test_fail "rc=$rc"
fi

kt_test_start "\$( ) prints the part count exactly once [D3]"
got="$(string.split "a,b,c" "," _sp)"
if [[ "$got" == "3" ]]; then
    kt_test_pass "3"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "the array is REPLACED, not appended to [TSH-03]"
declare -a _sp3=(old1 old2 old3 old4 old5)
string.split "x,y" "," _sp3 >/dev/null 2>&1 || :
if (( ${#_sp3[@]} == 2 )) && [[ "${_sp3[0]}" == "x" && "${_sp3[1]}" == "y" ]]; then
    kt_test_pass "2 elements, no leftovers"
else
    kt_test_fail "array=[${_sp3[*]}] (${#_sp3[@]} elements)"
fi
