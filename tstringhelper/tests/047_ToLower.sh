#!/bin/bash
# 047_ToLower.sh — extended in P5 for finding TSH-04.
#
# The old file was ASCII only ("HELLO WORLD", "hello", "HeLLo WoRlD", ""), so
# the byte-vs-character defect could not show: with LANG/LC_ALL unset bash 5.2
# turns `${s,,}` on 'ÄÖ' into two replacement characters and leaves 'CAFÉ' as
# 'CAFé'. D6 makes a UTF-8 locale part of the unit's contract (the runners pin
# LC_ALL=C.UTF-8 and the unit self-heals a bare environment), so the non-ASCII
# cases belong here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ToLower" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

lower_is() {   # TITLE EXPECTED INPUT [MEMBER]
    local title="$1" want="$2" in="$3" member="${4:-string.toLower}"
    kt_test_start "$title"
    RESULT="__unset__"
    "$member" "$in" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$RESULT')"
    fi
}

lower_is "an ASCII sentence"            "hello world" "HELLO WORLD"
lower_is "an already lowercase string"  "hello"       "hello"
lower_is "mixed case"                   "hello world" "HeLLo WoRlD"
lower_is "an empty string"              ""            ""
lower_is "digits and punctuation pass through" "a1b-2c" "A1B-2C"
lower_is "Latin-1 letters are lowered, not mangled [TSH-04]" "äö" "ÄÖ"
lower_is "an accented letter after ASCII [TSH-04]"           "café" "CAFÉ"
lower_is "Cyrillic is lowered [TSH-04]"                      "мир"  "МИР"
lower_is "Greek is lowered [TSH-04]"                         "αβγ"  "ΑΒΓ"
lower_is "a script without case is untouched [TSH-04]"       "日本" "日本"
lower_is "a value that looks like an echo option [X-ECHO]"   "-ne"  "-NE"

lower_is "lowerCase is the same member (FPC alias)" "abc" "ABC" string.lowerCase
lower_is "toLowerInvariant is the same member"      "abc" "ABC" string.toLowerInvariant
lower_is "toLowerInvariant on non-ASCII [TSH-04]"   "äö"  "ÄÖ"  string.toLowerInvariant

kt_test_start "the length in characters survives lowering [TSH-04]"
string.toLower "ÄÖÜ" >/dev/null 2>&1 || :
low="$RESULT"
string.length "$low" >/dev/null 2>&1 || :
if [[ "$low" == "äöü" && "$RESULT" == "3" ]]; then
    kt_test_pass "äöü, 3 characters"
else
    kt_test_fail "lowered='$low' length='$RESULT'"
fi

kt_test_start "\$( ) still prints the lowered string exactly once [D3]"
got="$(string.toLower 'МИР')"
if [[ "$got" == "мир" ]]; then
    kt_test_pass "мир"
else
    kt_test_fail "got '$got'"
fi
