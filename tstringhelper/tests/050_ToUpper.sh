#!/bin/bash
# 050_ToUpper.sh — extended in P5 for finding TSH-04.
#
# The old file was ASCII only, so the byte-vs-character defect could not show:
# with LANG/LC_ALL unset `${s^^}` leaves 'café' as 'CAFé' and corrupts 'äö' on
# bash 5.2. D6 makes a UTF-8 locale part of the unit's contract.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToUpper" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

upper_is() {   # TITLE EXPECTED INPUT [MEMBER]
    local title="$1" want="$2" in="$3" member="${4:-string.toUpper}"
    kt_test_start "$title"
    RESULT="__unset__"
    "$member" "$in" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$RESULT')"
    fi
}

upper_is "an ASCII sentence"            "HELLO WORLD" "hello world"
upper_is "an already uppercase string"  "HELLO"       "HELLO"
upper_is "mixed case"                   "HELLO WORLD" "HeLLo WoRlD"
upper_is "an empty string"              ""            ""
upper_is "digits and punctuation pass through" "A1B-2C" "a1b-2c"
upper_is "Latin-1 letters are raised, not mangled [TSH-04]" "ÄÖ" "äö"
upper_is "an accented letter after ASCII [TSH-04]"          "CAFÉ" "café"
upper_is "Cyrillic is raised [TSH-04]"                      "МИР"  "мир"
upper_is "Greek is raised [TSH-04]"                         "ΑΒΓ"  "αβγ"
upper_is "a script without case is untouched [TSH-04]"      "日本" "日本"
upper_is "a value that looks like an echo option [X-ECHO]"  "-NE"  "-ne"

upper_is "upperCase is the same member (FPC alias)" "ABC" "abc" string.upperCase
upper_is "toUpperInvariant is the same member"      "ABC" "abc" string.toUpperInvariant
upper_is "toUpperInvariant on non-ASCII [TSH-04]"   "ÄÖ"  "äö"  string.toUpperInvariant

kt_test_start "the length in characters survives raising [TSH-04]"
string.toUpper "äöü" >/dev/null 2>&1 || :
up="$RESULT"
string.length "$up" >/dev/null 2>&1 || :
if [[ "$up" == "ÄÖÜ" && "$RESULT" == "3" ]]; then
    kt_test_pass "ÄÖÜ, 3 characters"
else
    kt_test_fail "raised='$up' length='$RESULT'"
fi

kt_test_start "\$( ) still prints the raised string exactly once [D3]"
got="$(string.toUpper 'мир')"
if [[ "$got" == "МИР" ]]; then
    kt_test_pass "МИР"
else
    kt_test_fail "got '$got'"
fi
