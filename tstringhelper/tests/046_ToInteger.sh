#!/bin/bash
# ToInteger
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToInteger" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to int
kt_test_start "To integer"
result=$(string.toInteger "123")
if [[ "$result" == "123" ]]; then
    kt_test_pass "To integer"
else
    kt_test_fail "To integer (expected: 123, got: '$result')"
fi

# --- P5: FPC StrToInt semantics (finding TSH-14) ---------------------------
# ToInteger is StrToInt, which is Val (rtl/inc/sstrings.inc, InitVal +
# fpc_Val_SInt_ShortStr). Val accepts, in this order:
#   leading spaces and TABs, an optional sign, an optional base prefix
#   ($ / x / X / 0x / 0X = hex, % = binary, & = octal), then digits of that
#   base — and NOTHING else, so a fractional part, trailing text or trailing
#   spaces make the conversion fail (StrToInt then raises EConvertError).
# In bash that failure is rc 1 + RESULT='' (kcl/README.md 1.2). Two bounded
# deviations, documented in the unit README: the decimal range is checked
# (int32 here, int64 for toInt64) instead of silently truncating, and a
# non-decimal literal wider than the destination is rejected instead of being
# truncated from 64 bits.
int_is() {   # EXPECTED INPUT [MEMBER]
    local member="${3:-string.toInteger}"
    kt_test_start "${member#string.} $(printf '%q' "$2") -> $1 [TSH-14]"
    RESULT="__unset__"
    local rc=0
    "$member" "$2" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ "$RESULT" == "$1" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected 0 / '$1'"
    fi
}

int_no() {   # INPUT [MEMBER]
    local member="${2:-string.toInteger}"
    kt_test_start "${member#string.} rejects $(printf '%q' "$1") [TSH-14]"
    RESULT="__unset__"
    local rc=0
    "$member" "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected rc 1 and an empty RESULT"
    fi
}

int_is 123   "123"
int_is 0     "0"
int_is -7    "-7"
int_is 7     "+7"
int_is 7     "007"
int_is 42    $'\t 42'
int_is 42    "  42"
int_is 16    '$10'
int_is 16    "0x10"
int_is 16    "0X10"
int_is 16    "x10"
int_is 16    "X10"
int_is 255   '$ff'
int_is 255   '$FF'
int_is -16   '-$10'
int_is 10    "%1010"
int_is 15    "&17"
int_is 2147483647  "2147483647"
int_is -2147483648 "-2147483648"

int_no "42.99"
int_no "3.9"
int_no "hello"
int_no ""
int_no "42 "
int_no "4 2"
int_no "12abc"
int_no '$'
int_no "0x"
int_no "%"
int_no "%12"
int_no "&9"
int_no '$g'
int_no "1e3"
int_no "2147483648"
int_no "-2147483649"
int_no 'a[$(id)]'

kt_test_start "\$( ) still prints the parsed integer exactly once [D3]"
got="$(string.toInteger '  -042')"
if [[ "$got" == "-42" ]]; then
    kt_test_pass "-42"
else
    kt_test_fail "got '$got'"
fi
