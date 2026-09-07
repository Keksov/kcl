#!/bin/bash
# 034_QuotedString.sh — rewritten in P5 for finding TSH-08.
#
# The old file accepted "either of two answers" on three of its ten
# assertions (`'it''s'` OR `"it's"`, `''''` OR `''''''`), which is exactly how
# the defect stayed green: with a CUSTOM quote character the member did not
# double anything at all (`quotedString 'say "hi"' '"'` produced the
# unparseable `"say "hi""`), and the default path shelled out to
# `printf | sed`, which forks and eats trailing newlines.
#
# FPC: QuotedString = AnsiQuotedStr(Self, ''''), QuotedString(Q) =
# AnsiQuotedStr(Self, Q) — "S quoted left and right by Quote, and every single
# occurrence of Quote replaced by two" (rtl/objpas/sysutils/sysstr.inc:672).
# The port is `$q${s//"$q"/$q$q}$q`: no fork, no data loss.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "QuotedString" "$SCRIPT_DIR" "$@"

source "$SCRIPT_DIR/../tstringhelper.sh"

q_is() {   # TITLE EXPECTED ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    string.quotedString "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title"
    else
        kt_test_fail "$title (expected '$want', got '$RESULT')"
    fi
}

q_is "the default quote character is the apostrophe (FPC) [TSH-08]" \
    "'hello'" "hello"
q_is "an internal apostrophe is DOUBLED [TSH-08]" \
    "'it''s'" "it's"
q_is "an empty string becomes two quotes [TSH-08]" \
    "''" ""
q_is "a string of two quotes becomes six [TSH-08]" \
    "''''''" "''"
q_is "spaces are not special [TSH-08]" \
    "'hello world'" "hello world"
q_is "shell metacharacters are data [TSH-08]" \
    "'test@#\$'" 'test@#$'
q_is "a digit string [TSH-08]" \
    "'12345'" "12345"
q_is "a custom quote character quotes [TSH-08]" \
    '"hello"' "hello" '"'
q_is "a custom quote character is DOUBLED too (the defect) [TSH-08]" \
    '"say ""hi"""' 'say "hi"' '"'
q_is "a custom quote leaves the DEFAULT quote alone [TSH-08]" \
    '"it'"'"'s"' "it's" '"'
q_is "an apostrophe input under a custom quote [TSH-08]" \
    '|it'"'"'s|' "it's" '|'
q_is "the quote character alone under a custom quote [TSH-08]" \
    '||||' '|' '|'
q_is "an empty quote argument falls back to the apostrophe (FPC) [TSH-08]" \
    "'x'" "x" ""
q_is "only the FIRST character of the quote argument is used (FPC Char) [TSH-08]" \
    "#x#" "x" "#!"
q_is "a glob metacharacter as the quote character is literal [TSH-08]" \
    '*a**b*' 'a*b' '*'

# --- no data loss: trailing newlines and echo-option shapes ----------------
kt_test_start "trailing newlines survive quoting [TSH-08]"
RESULT="__unset__"
string.quotedString $'a\n\n' >/dev/null 2>&1 || :
if [[ "$RESULT" == $'\'a\n\n\'' ]]; then
    kt_test_pass "both newlines kept"
else
    kt_test_fail "got $(printf '%q' "$RESULT")"
fi

kt_test_start "a value that looks like an echo option survives quoting [TSH-08, X-ECHO]"
RESULT="__unset__"
string.quotedString "-neE" >/dev/null 2>&1 || :
if [[ "$RESULT" == "'-neE'" ]]; then
    kt_test_pass "'-neE'"
else
    kt_test_fail "got '$RESULT'"
fi

kt_test_start "quotedString does not fork [TSH-08, 1.8]"
body="$(declare -f string.__static_quotedString)"
body="${body//\$((/ARITH}"
if [[ "$body" != *'$('* && "$body" != *'`'* && "$body" != *sed* ]]; then
    kt_test_pass "no command substitution, no sed"
else
    kt_test_fail "the body still shells out"
fi

# --- round trip with deQuotedString ----------------------------------------
kt_test_start "quotedString then deQuotedString is the identity [TSH-08]"
bad=""
for s in "hello" "it's" "" "''" "a'b'c" $'line1\nline2' "-n" 'say "hi"'; do
    string.quotedString "$s" >/dev/null 2>&1 || :
    q="$RESULT"
    string.deQuotedString "$q" >/dev/null 2>&1 || :
    [[ "$RESULT" == "$s" ]] || bad+="[$s -> $q -> $RESULT] "
done
if [[ -z "$bad" ]]; then
    kt_test_pass "8 round trips"
else
    kt_test_fail "broken: $bad"
fi
