#!/bin/bash
# 002_IsMatch.sh - TRegEx.isMatch: rc 0 match / 1 no-match / 2 invalid, anchors,
# POSIX classes, alternation, word boundaries, i-flag, and kcl torture subjects
# (newlines, globs, quotes, $(...), unicode, empty, leading dash). Basis:
# DocWiki TRegEx.IsMatch + P0 probe results (S1/S2/S3/S7/S8/ADJ). Pinned
# ERE-vs-PCRE deltas are EXPLICIT rows (the delta is the spec).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "002: TRegEx.isMatch"

# helpers: assert rc for isMatch <text> <pattern> [flags]
_im() { TRegEx.isMatch "$1" "$2" "${3:-}"; echo $?; }
ok()  { kt_test_start "$1"; [[ "$(_im "$2" "$3" "${4:-}")" == "0" ]] && kt_test_pass "match" || kt_test_fail "expected match (rc0) for text='$2' re='$3' flags='${4:-}'"; }
no()  { kt_test_start "$1"; [[ "$(_im "$2" "$3" "${4:-}")" == "1" ]] && kt_test_pass "no-match" || kt_test_fail "expected no-match (rc1) for text='$2' re='$3'"; }
inv() { kt_test_start "$1"; [[ "$(_im "$2" "$3")" == "2" ]] && kt_test_pass "invalid(rc2)" || kt_test_fail "expected invalid (rc2) for re='$3'"; }

# --- basic hit / miss ---
ok  "substring hit"          "hello world" "o w"
no  "substring miss"         "hello world" "xyz"
ok  "full-string via anchors" "abc" "^abc$"

# --- rc=2 invalid patterns (S3) + empty pattern (S2 -> rc2, our decision) ---
inv "unbalanced ["            "abc" "["
inv "unbalanced ("            "abc" "("
inv "bad repetition a{2,1}"   "abc" "a{2,1}"
inv "leading quantifier *"    "abc" "*"
inv "trailing backslash"      "abc" "\\"
inv "empty pattern -> rc2"    "abc" ""

# --- anchors, no multiline (S1 dot / ADJ4 no-multiline) ---
ok  "^ start anchor"          "abcdef" "^abc"
ok  "\$ end anchor"           "abcdef" "def$"
no  "^ not mid-string"        "xabc"   "^abc"
ok  ". matches newline (S1)"  $'a\nb'  "a.b"
no  "^ is string-start only"  $'x\ny'  "^y"
no  "\$ is string-end only"   $'x\ny'  "x$"

# --- POSIX character classes & ranges ---
ok  "[[:digit:]] hit"         "id=42"  "[[:digit:]]+"
no  "[[:digit:]] miss"        "abcdef" "[[:digit:]]"
ok  "[a-z] range"             "Hello"  "[a-z]+"
ok  "[[:space:]]"             $'a\tb'  "[[:space:]]"
ok  "negated class [^0-9]"    "12a34"  "[^0-9]"

# --- alternation: leftmost-LONGEST (S8) — isMatch only sees hit/miss ---
ok  "alternation hit"         "cat"    "cat|dog"
no  "alternation miss"        "fish"   "cat|dog"

# --- word boundaries \b \< \> (S7, GNU/glibc, both bashes) ---
ok  "\\b whole word"          "the cat sat" "\\bcat\\b"
no  "\\b not partial"         "concatenate" "\\bcat\\b"
ok  "\\< \\> word ends"       "a foo b"     "\\<foo\\>"

# --- i-flag: case sensitivity is flag-controlled (deterministic) ---
no  "case-sensitive default"  "HELLO"  "hello"
ok  "i-flag insensitive"      "HELLO"  "hello" "i"
ok  "i-flag mixed"            "HeLLo"  "hello" "i"
no  "no-i stays sensitive"    "HELLO"  "hello" ""

# --- pattern-via-variable safety: metachars/spaces/globs in pattern ---
ok  "pattern with spaces"     "a b c"  "a b"
ok  "pattern is a glob-like"  "a*b"    "a\\*b"
ok  "alternation in var"      "xy"     "(xy|z)"

# --- kcl torture subjects ---
ok  "subject has glob chars"  "f*o?[x]" "\\*o\\?"
ok  "subject has quotes"      "say \"hi\"" "\"hi\""
ok  "subject has \$(...)"     'a$(whoami)b' "\\\$\\(whoami\\)"
ok  "subject has backticks"   'x`id`y'  "\`id\`"
ok  "unicode subject"         "café"    "caf."
ok  "leading-dash subject"    "-n hi"   "^-n"
ok  "dash inside pattern"     "a-b"     "a-b"
no  "dash-pattern literal miss" "abc"   "-x"
no  "empty subject vs 'a'"    ""        "a"
ok  "empty subject vs empty-match re" "" "x*"

kt_test_log "002_IsMatch.sh completed"
