#!/bin/bash
# 041_ToBoolean.sh — rewritten in P5 for finding TSH-07 (default R9).
#
# The old file had exactly two assertions, `true` and `false`, and the member
# was `[[ $s == true || $s == 1 ]]`. FPC's ToBoolean is StrToBool, i.e.
# TryStrToBool (rtl/objpas/sysutils/sysstr.inc:2075):
#
#   * if the text parses as a NUMBER, the answer is (value <> 0) — so `-1`,
#     `2`, `0.5` and `1e3` are true and `0`, `0.0`, `-0` are false;
#   * otherwise it is compared, CASE-INSENSITIVELY, against TrueBoolStrs[0]
#     ('True') and FalseBoolStrs[0] ('False');
#   * anything else is a CONVERSION FAILURE — StrToBool raises EConvertError.
#
# In bash that failure is the kcl error contract (kcl/README.md 1.2): rc 1 and
# RESULT='' — distinguishable from the answer "false", which is rc 1 with
# RESULT='false' (R8: a boolean answers with its exit status).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToBoolean" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

is_true() {   # VALUE
    kt_test_start "toBoolean '$1' is TRUE (rc 0, RESULT true) [TSH-07]"
    RESULT="__unset__"
    local rc=0
    string.toBoolean "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ "$RESULT" == "true" ]]; then
        kt_test_pass "rc 0 / true"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
}

is_false() {   # VALUE
    kt_test_start "toBoolean '$1' is FALSE (rc 1, RESULT false) [TSH-07]"
    RESULT="__unset__"
    local rc=0
    string.toBoolean "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ "$RESULT" == "false" ]]; then
        kt_test_pass "rc 1 / false"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
}

is_invalid() {   # VALUE
    kt_test_start "toBoolean '$1' is NOT convertible (rc 1, RESULT empty) [TSH-07]"
    RESULT="__unset__"
    local rc=0
    string.toBoolean "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1 / empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT'"
    fi
}

is_true  "true"
is_true  "True"
is_true  "TRUE"
is_true  "tRuE"
is_true  "1"
is_true  "-1"
is_true  "2"
is_true  "0.5"
is_true  "1e3"
is_true  "+7"

is_false "false"
is_false "False"
is_false "FALSE"
is_false "fAlSe"
is_false "0"
is_false "-0"
is_false "0.0"
is_false "000"

is_invalid ""
is_invalid "yes"
is_invalid "no"
is_invalid "t"
is_invalid "abc"
is_invalid "1x"
is_invalid "true false"

kt_test_start "\$( ) still prints true/false [TSH-07, D3]"
a="$(string.toBoolean True)"
b="$(string.toBoolean False)"
if [[ "$a" == "true" && "$b" == "false" ]]; then
    kt_test_pass "true / false"
else
    kt_test_fail "got '$a' / '$b'"
fi

kt_test_start "toBoolean is usable as a predicate [TSH-07, R8]"
out=""
string.toBoolean "True"  >/dev/null 2>&1 && out+="T"
string.toBoolean "False" >/dev/null 2>&1 || out+="F"
string.toBoolean "-1"    >/dev/null 2>&1 && out+="N"
if [[ "$out" == "TFN" ]]; then
    kt_test_pass "if/&&/|| all agree with RESULT"
else
    kt_test_fail "got '$out'"
fi
