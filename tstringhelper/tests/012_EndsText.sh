#!/bin/bash
# EndsText
# Auto-migrated to ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "EndsText" "$SCRIPT_DIR" "$@"

# Source tstringhelper if needed
TSTRINGHELPER_DIR="$SCRIPT_DIR/.."
[[ -f "$TSTRINGHELPER_DIR/tstringhelper.sh" ]] && source "$TSTRINGHELPER_DIR/tstringhelper.sh"


# Test 1: Ends with
kt_test_start "Ends with"
result=$(string.endsText "world" "hello world")
if [[ "$result" == "true" ]]; then
    kt_test_pass "Ends with"
else
    kt_test_fail "Ends with (expected: true, got: '$result')"
fi

# Test 2: Does not end with
kt_test_start "Does not end with"
result=$(string.endsText "hello" "hello world")
if [[ "$result" == "false" ]]; then
    kt_test_pass "Does not end with"
else
    kt_test_fail "Does not end with (expected: false, got: '$result')"
fi

# --- P5 review remark 2: TStringHelper.EndsText, not StrUtils.AnsiEndsText --
# FPC has TWO rules for an EMPTY subtext and they disagree:
#   rtl/objpas/sysutils/syshelp.inc, TStringHelper.EndsText:
#       Result := (ASubText<>'') and (CompareText(Copy(...),ASubText)=0);
#   packages/rtl-objpas/src/inc/strutils.pp, AnsiEndsText:
#       Result := (ASubText='') or AnsiSameText(RightStr(...),ASubText);
# This unit ports TStringHelper, so the class-function rule wins: an empty
# subtext is FALSE. Note the asymmetry with EndsWith, which is TStringHelper's
# own `Result := L=0` — empty VALUE there is TRUE (test 013).
bool_is() {   # TITLE EXPECTED-RC EXPECTED-RESULT MEMBER ARGS...
    local title="$1" wantrc="$2" wantres="$3"; shift 3
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == wantrc )) && [[ "$RESULT" == "$wantres" ]]; then
        kt_test_pass "rc $rc / $RESULT"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' (wanted rc $wantrc / '$wantres')"
    fi
}

bool_is "an EMPTY subtext is false (TStringHelper.EndsText) [P5-F2]" \
    1 false string.endsText "" "hello world"
bool_is "an empty subtext against an empty text is false too [P5-F2]" \
    1 false string.endsText "" ""
bool_is "a non-empty subtext still matches case-insensitively [P5-F2]" \
    0 true string.endsText "WORLD" "hello world"
bool_is "an empty TEXT with a non-empty subtext is false [P5-F2]" \
    1 false string.endsText "x" ""
