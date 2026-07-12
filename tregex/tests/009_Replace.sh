#!/bin/bash
# 009_Replace.sh - TRegEx.replace / replaceCb: the $-replacement grammar
# ($0/$&/$1-$9/${n}/$$, invalid-group and unknown-$x kept literal, sed
# metacharacters & \ LITERAL), replace-ALL default + maxCount, i-flag, empty-
# match insertion, no-match/invalid, the callback REPLY contract, $() body-echo
# + direct RESULT, and torture. FPC-traceable cross-checks live in 008.
# Basis: DocWiki TRegEx.Replace + .NET substitution grammar + PLAN §2.5 + P0.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "009: TRegEx.replace / replaceCb"

# rep <name> <text> <re> <repl> <expected> [maxCount] [flags]
rep() {
    kt_test_start "$1"
    TRegEx.replace "$2" "$3" "$4" "${6:--}" "${7:-}" >/dev/null
    [[ "$RESULT" == "$5" ]] && kt_test_pass "-> '$RESULT'" || kt_test_fail "got '$RESULT' ; want '$5'"
}

# --- replace-all default + literal replacement ---
rep "replace all default"   "a.b.c"    "\\."   "-"    "a-b-c"
rep "literal replacement"   "cat"      "a"     "X"    "cXt"
rep "no match unchanged"    "abc"      "z"     "X"    "abc"

# --- $-grammar ---
rep "\$0 whole match"       "abc"      "b"     "[\$0]"   "a[b]c"
rep "\$& whole match"       "abc"      "b"     "[\$&]"   "a[b]c"
rep "\$1 group"             "a1b"      "([0-9])" "<\$1>" "a<1>b"
rep "\${2}\${1} braces swap" "ab"      "(a)(b)" "\${2}\${1}" "ba"
rep "\$\$ literal dollar"   "abc"      "b"     "x\$\$y"  "ax\$yc"
rep "invalid group literal" "abc"      "b"     "\$9"     "a\$9c"
rep "unknown \$x literal"   "abc"      "b"     "\$z"     "a\$zc"
rep "sed & literal (not whole)" "abc"  "b"     "&"       "a&c"
rep "sed backslash literal" "abc"      "b"     "\\n"     "a\\nc"

# --- maxCount ---
rep "maxCount 1"            "aaa"      "a"     "X"    "Xaa"   1
rep "maxCount 2"            "aaaa"     "a"     "X"    "XXaa"  2
rep "maxCount 0 = all"      "aaa"      "a"     "X"    "XXX"   0

# --- i-flag ---
rep "i-flag replace"        "AaAa"     "a"     "X"    "XXXX"  -  i
rep "no-i sensitive"        "AaAa"     "a"     "X"    "AXAX"

# --- empty-match insertion ---
rep "empty-match insert"    "abc"      "x*"    "-"    "-a-b-c-"
# anchor caveat (delta): ^ re-anchors per remainder, so replace inserts before
# EVERY char (>a>b>c>), NOT once at string start (.NET would give '>abc').
rep "anchor caveat: ^ per-remainder" "abc" "^" ">"  ">a>b>c>"

# --- torture: newlines / unicode / quotes / empty ---
rep "newline subject"       $'a\nb'    $'\n'   " "    "a b"
rep "unicode replacement"   "abc"      "b"     "é"    "aéc"
rep "quotes in replacement" "abc"      "b"     '"x"'  'a"x"c'
rep "empty replacement"     "a-b-c"    "-"     ""     "abc"
rep "replace into empty subj" ""       "x*"    "Z"    "Z"

# --- rc: invalid -> rc2, text unchanged ---
kt_test_start "invalid pattern: rc2, text unchanged"
TRegEx.replace "abc" "[" "X" >/dev/null; rc=$?
[[ $rc -eq 2 && "$RESULT" == "abc" ]] && kt_test_pass "rc2, unchanged" || kt_test_fail "rc=$rc RESULT='$RESULT'"

# --- $() body-echo ergonomics + direct RESULT agree ---
kt_test_start "replace \$() body-echo == direct RESULT"
cap="$(TRegEx.replace "a1b2" "[0-9]" "#")"
TRegEx.replace "a1b2" "[0-9]" "#" >/dev/null
[[ "$cap" == "a#b#" && "$RESULT" == "a#b#" ]] && kt_test_pass "both 'a#b#'" || kt_test_fail "cap='$cap' RESULT='$RESULT'"

# --- replaceCb: callback contract (REPLY), groups, maxCount, empty REPLY ---
kt_test_start "replaceCb: uppercases each match via REPLY"
up() { REPLY="${1^^}"; }
TRegEx.replaceCb "a1 b2 c3" "[a-z][0-9]" up >/dev/null
[[ "$RESULT" == "A1 B2 C3" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "replaceCb: callback sees groups as \$2.."
swap() { REPLY="$3$2"; }
TRegEx.replaceCb "abcd" "(.)(.)" swap >/dev/null
[[ "$RESULT" == "badc" ]] && kt_test_pass "$RESULT" || kt_test_fail "got '$RESULT'"

kt_test_start "replaceCb: maxCount limits calls"
cnt=0; tick() { cnt=$((cnt+1)); REPLY="[$1]"; }
TRegEx.replaceCb "a a a a" "a" tick 2 >/dev/null
[[ "$RESULT" == "[a] [a] a a" && "$cnt" == "2" ]] && kt_test_pass "2 calls, $RESULT" || kt_test_fail "cnt=$cnt RESULT='$RESULT'"

kt_test_start "replaceCb: callback leaving REPLY empty deletes the match"
noop() { REPLY=""; }
TRegEx.replaceCb "a-b-c" "-" noop >/dev/null
[[ "$RESULT" == "abc" ]] && kt_test_pass "deleted delimiters" || kt_test_fail "got '$RESULT'"

# --- zero-fork ---
kt_test_start "PATH='' : replace + replaceCb need no external commands"
zf="$(
    PATH=''
    source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
    TRegEx.replace "a1b" "[0-9]" "#" >/dev/null; r="$RESULT"
    cb() { REPLY="<$1>"; }
    TRegEx.replaceCb "a1b" "[0-9]" cb >/dev/null; c="$RESULT"
    printf '%s|%s' "$r" "$c"
)"
[[ "$zf" == "a#b|a<1>b" ]] && kt_test_pass "$zf" || kt_test_fail "PATH='' failed ('$zf')"

kt_test_log "009_Replace.sh completed"
