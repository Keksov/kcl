#!/bin/bash
# ToInt64
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToInt64" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Convert to int
kt_test_start "To int64"
result=$(string.toInt64 "42")
if [[ "$result" == "42" ]]; then
    kt_test_pass "To int64"
else
    kt_test_fail "To int64 (expected: 42, got: '$result')"
fi

# --- P5: FPC StrToInt64 semantics (finding TSH-14) -------------------------
# Same Val grammar as toInteger (see 046_ToInteger.sh) with the Int64 range.
i64_is() {   # EXPECTED INPUT
    kt_test_start "toInt64 $(printf '%q' "$2") -> $1 [TSH-14]"
    RESULT="__unset__"
    local rc=0
    string.toInt64 "$2" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ "$RESULT" == "$1" ]]; then
        kt_test_pass "$1"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected 0 / '$1'"
    fi
}

i64_no() {   # INPUT
    kt_test_start "toInt64 rejects $(printf '%q' "$1") [TSH-14]"
    RESULT="__unset__"
    local rc=0
    string.toInt64 "$1" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty"
    else
        kt_test_fail "rc=$rc RESULT='$RESULT', expected rc 1 and an empty RESULT"
    fi
}

i64_is 42 "42"
i64_is 0  "0"
i64_is 9223372036854775807  "9223372036854775807"
i64_is -9223372036854775808 "-9223372036854775808"
i64_is 4294967296 "4294967296"
i64_is 4294967296 '$100000000'
i64_is 255 '$ff'

i64_no "9223372036854775808"
i64_no "42.5"
i64_no "abc"
i64_no ""
i64_no "0x"

kt_test_start "toInteger REJECTS what only fits in an Int64 [TSH-14]"
RESULT="__unset__"
rc=0
string.toInteger "4294967296" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
    kt_test_pass "rc 1 (StrToInt is a Longint conversion)"
else
    kt_test_fail "rc=$rc RESULT='$RESULT'"
fi
