#!/bin/bash
# 004_Escape.sh - TRegEx.escape: every ERE metacharacter backslash-quoted so
# the output matches the input LITERALLY; round-trip via isMatch/match; the
# body-echo ($()) + RESULT dual contract; empty / no-meta / all-meta / torture
# subjects. Basis: DocWiki TRegEx.Escape (ERE metaset, not PCRE's).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "004: TRegEx.escape"

# esc <name> <in> <expected>   (checks RESULT == expected)
esc() {
    kt_test_start "$1"
    TRegEx.escape "$2" >/dev/null
    [[ "$RESULT" == "$3" ]] && kt_test_pass "'$2' -> '$RESULT'" \
        || kt_test_fail "escape('$2') = '$RESULT' ; want '$3'"
}

# --- each metacharacter gets a single leading backslash ---
esc "dot"          "a.b"   'a\.b'
esc "caret"        "a^b"   'a\^b'
esc "dollar"       "a\$b"  'a\$b'
esc "star"         "a*b"   'a\*b'
esc "plus"         "a+b"   'a\+b'
esc "question"     "a?b"   'a\?b'
esc "open paren"   "a(b"   'a\(b'
esc "close paren"  "a)b"   'a\)b'
esc "open bracket" "a[b"   'a\[b'
esc "close bracket" "a]b"  'a\]b'
esc "open brace"   "a{b"   'a\{b'
esc "close brace"  "a}b"   'a\}b'
esc "pipe"         "a|b"   'a\|b'
esc "backslash"    "a\\b"  'a\\b'

# --- non-metacharacters are untouched ---
esc "plain word"   "hello" "hello"
esc "space kept"   "a b c" "a b c"
esc "digits/dash"  "a-b_9" "a-b_9"
esc "unicode kept" "café"  "café"
esc "empty string" ""      ""

# --- all metacharacters at once ---
esc "all metas" '.^$*+?()[]{}|\' '\.\^\$\*\+\?\(\)\[\]\{\}\|\\'

# --- round-trip: escaped output matches the input literally (isMatch) ---
roundtrip() {
    kt_test_start "round-trip: $1"
    TRegEx.escape "$2" >/dev/null; local e="$RESULT"
    if TRegEx.isMatch "$2" "$e"; then kt_test_pass "literal '$2' matches its escape"
    else kt_test_fail "escape of '$2' ('$e') did not match literally"; fi
}
roundtrip "metachar salad" 'a.b*c[d]e(f)|g^h$i+j?k{l}m'
roundtrip "regex-looking"  'v1.2.3+build(x)'
roundtrip "brackets/braces" '{[()]}'
roundtrip "just a dot"     '.'
roundtrip "dollar-anchored-looking" 'end$'

# --- round-trip precision: escaped pattern matches WHOLE string at index 0 ---
kt_test_start "escape+match: whole literal, index 0, full length"
lit='a.b*(c)'
TRegEx.escape "$lit" >/dev/null; e="$RESULT"
TRegEx.match "$lit" "$e"
if [[ "$RESULT" == "$lit" && "$RESULT_INDEX" == "0" && "$RESULT_LENGTH" == "${#lit}" ]]; then
    kt_test_pass "matched whole '$lit' at 0 len ${#lit}"
else
    kt_test_fail "RESULT='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH"
fi

# --- escaped pattern must NOT over-match (metachars truly neutralized) ---
kt_test_start "escaped '.' does not match an arbitrary char"
TRegEx.escape "a.c" >/dev/null; e="$RESULT"
if TRegEx.isMatch "aXc" "$e"; then kt_test_fail "escaped 'a.c' wrongly matched 'aXc'"
else kt_test_pass "escaped 'a.c' rejects 'aXc'"; fi

# --- dual contract: $() capture (body-echo) AND direct RESULT agree ---
kt_test_start "body-echo \$() == RESULT"
cap="$(TRegEx.escape 'x+y')"
TRegEx.escape 'x+y' >/dev/null
[[ "$cap" == 'x\+y' && "$RESULT" == 'x\+y' ]] && kt_test_pass "both 'x\\+y'" \
    || kt_test_fail "cap='$cap' RESULT='$RESULT'"

# --- torture: newline in subject is not a metachar (kept verbatim) ---
kt_test_start "newline subject kept, still round-trips"
nl=$'a\n.b'
TRegEx.escape "$nl" >/dev/null; e="$RESULT"
TRegEx.isMatch "$nl" "$e" && kt_test_pass "newline literal round-trips" || kt_test_fail "newline round-trip failed"

kt_test_log "004_Escape.sh completed"
