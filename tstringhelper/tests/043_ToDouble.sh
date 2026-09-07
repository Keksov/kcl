#!/bin/bash
# ToDouble
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToDouble" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to double
kt_test_start "To double"
result=$(string.toDouble "3.14")
if [[ "$result" == "3.14" ]]; then
    kt_test_pass "To double"
else
    kt_test_fail "To double (expected: 3.14, got: '$result')"
fi

# --- P5: the float conversions validate (finding TSH-18) -------------------
# toDouble/toExtended/toSingle used to be `${self%% *}` — the first word of the
# argument, whatever it was: `toDouble abc` answered `abc`, `toDouble "1 2"`
# answered `1`. FPC's ToDouble is StrToFloat, i.e. TextToFloat, which runs
# Val(trim(S)) and raises when the code is non-zero
# (rtl/objpas/sysutils/sysstr.inc:1247). The port validates with the shared
# kk.isNum guard (D1) after stripping FPC's whitespace set, and answers rc 1 +
# RESULT='' on anything else (kcl/README.md 1.2).
#
# The decimal separator is '.' — DefaultFormatSettings under the C locale that
# kcl pins (D6); FPC's TextToFloat also refuses a thousands separator.
flt_is() {   # EXPECTED INPUT MEMBER
    kt_test_start "${3#string.} $(printf '%q' "$2") -> $1 [TSH-18]"
    RESULT="__unset__"
    local rc=0
    "$3" "$2" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ "$RESULT" == "$1" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected 0 / '$1'"
    fi
}

flt_no() {   # INPUT MEMBER
    kt_test_start "${2#string.} rejects $(printf '%q' "$1") [TSH-18]"
    RESULT="__unset__"
    local rc=0
    "$2" "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected rc 1 and an empty RESULT"
    fi
}

for m in string.toDouble string.toExtended string.toSingle; do
    flt_is "3.14"     "3.14"     "$m"
    flt_is "-2.5"     "-2.5"     "$m"
    flt_is "42"       "42"       "$m"
    flt_is ".5"       ".5"       "$m"
    flt_is "2.5E-10"  "2.5E-10"  "$m"
    flt_is "1e3"      "1e3"      "$m"
    flt_is "0"        "0"        "$m"
    flt_is "7"        "+7"       "$m"
    flt_is "3.14"     "  3.14  " "$m"

    flt_no "abc"      "$m"
    flt_no ""         "$m"
    flt_no "1 2"      "$m"
    flt_no "3.1.4"    "$m"
    flt_no "1,5"      "$m"
    flt_no "inf"      "$m"
    flt_no "nan"      "$m"
    flt_no '$10'      "$m"
    flt_no '12abc'    "$m"
    flt_no 'a[$(id)]' "$m"
done

kt_test_start "\$( ) still prints the number exactly once [D3]"
got="$(string.toDouble ' -0.25 ')"
if [[ "$got" == "-0.25" ]]; then
    kt_test_pass "-0.25"
else
    kt_test_fail "got '$got'"
fi
