#!/bin/bash
# 011_DeQuotedString.sh — rewritten in P5 for finding TSH-08.
#
# The old member was `printf '%s\n' "${self//\"/}"`: it deleted EVERY double
# quote anywhere in the string, ignored FPC's default quote character (the
# apostrophe) and took no quote argument at all. The single assertion in this
# file (`deQuotedString '"hello"'` -> `hello`) was green on that.
#
# FPC (rtl/objpas/sysutils/syshelp.inc, TStringHelper.DeQuotedString):
#   * the default quote character is the APOSTROPHE;
#   * if the string is shorter than 2 characters, or its first and last
#     characters are not both the quote character, it is returned UNCHANGED;
#   * otherwise the outer pair is dropped and, inside, a doubled quote
#     collapses to one while a lone quote disappears (the IsQuote toggle).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "DeQuotedString" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

dq_is() {   # TITLE EXPECTED ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    string.deQuotedString "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$RESULT')"
    fi
}

dq_is "the default quote character is the apostrophe (FPC) [TSH-08]" \
    "hello" "'hello'"
dq_is "a doubled apostrophe inside collapses to one [TSH-08]" \
    "it's" "'it''s'"
dq_is "double quotes are NOT the default quote: unchanged [TSH-08]" \
    '"hello"' '"hello"'
dq_is "... but they are with an explicit quote argument [TSH-08]" \
    "hello" '"hello"' '"'
dq_is "a doubled custom quote inside collapses to one [TSH-08]" \
    'say "hi"' '"say ""hi"""' '"'
dq_is "quotes in the MIDDLE are not stripped (not a quoted string) [TSH-08]" \
    'a"b"c' 'a"b"c' '"'
dq_is "only a leading quote: unchanged [TSH-08]" \
    "'hello" "'hello"
dq_is "only a trailing quote: unchanged [TSH-08]" \
    "hello'" "hello'"
dq_is "a single quote character is shorter than 2: unchanged [TSH-08]" \
    "'" "'"
dq_is "an empty string: unchanged [TSH-08]" \
    "" ""
dq_is "two quotes are an empty quoted string [TSH-08]" \
    "" "''"
dq_is "a lone inner quote disappears (FPC IsQuote toggle) [TSH-08]" \
    "ab" "'a'b'"
dq_is "an unquoted word: unchanged [TSH-08]" \
    "hello" "hello"
dq_is "an echo-option shape survives [TSH-08, X-ECHO]" \
    "-neE" "'-neE'"

kt_test_start "trailing newlines survive dequoting [TSH-08]"
RESULT="__unset__"
string.deQuotedString $'\'a\n\n\'' >/dev/null 2>&1 || :
if [[ "$RESULT" == $'a\n\n' ]]; then
    kt_test_pass "both newlines kept"
else
    kt_test_fail "got $(printf '%q' "$RESULT")"
fi

kt_test_start "deQuotedString does not fork [TSH-08, 1.8]"
body="$(declare -f string.__static_deQuotedString)"
body="${body//\$((/ARITH}"
if [[ "$body" != *'$('* && "$body" != *'`'* ]]; then
    kt_test_pass "no command substitution"
else
    kt_test_fail "the body shells out"
fi
