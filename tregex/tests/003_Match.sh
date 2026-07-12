#!/bin/bash
# 003_Match.sh - TRegEx.match: the RESULT / RESULT_INDEX / RESULT_LENGTH /
# RESULT_GROUPS contract, offset recovery (S5 exact unanchored, S6 anchored
# CAVEAT pinned as a divergence row), numbered groups incl. non-participating
# (S10), leftmost-LONGEST alternation (S8), empty match, dot-newline (S1),
# no-match/invalid reset. Basis: DocWiki TRegEx.Match + P0 probes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "003: TRegEx.match — RESULT* contract, offsets, groups"

# mres <name> <text> <re> <expText> <expIndex> <expLen> [flags]
mres() {
    kt_test_start "$1"
    TRegEx.match "$2" "$3" "${7:-}"
    if [[ "$RESULT" == "$4" && "$RESULT_INDEX" == "$5" && "$RESULT_LENGTH" == "$6" ]]; then
        kt_test_pass "text='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH"
    else
        kt_test_fail "got text='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH ; want text='$4' idx=$5 len=$6"
    fi
}

# --- basic match: text, offset, length ---
mres "leading match"        "hello"    "he"    "he"   0 2
mres "mid match + offset"   "xxabcyy"  "abc"   "abc"  2 3
mres "single char"          "abc"      "b"     "b"    1 1
mres "whole via anchors"    "abcdef"   "^.*$"  "abcdef" 0 6
mres "quantifier greedy"    "aaa"      "a+"    "aaa"  0 3

# unicode: text + offset are locale-robust (ASCII prefix 'caf' -> idx 3);
# RESULT_LENGTH is `${#matched}` in the AMBIENT locale (S9: byte-count under
# empty/C locale on MSYS2, char-count under a full UTF-8 locale) — so we assert
# it stays self-consistent with ${#RESULT} rather than hard-coding 1-vs-2.
kt_test_start "unicode match: text + offset (ambient-locale length)"
TRegEx.match "café" "é"
if [[ "$RESULT" == "é" && "$RESULT_INDEX" == "3" && "$RESULT_LENGTH" == "${#RESULT}" ]]; then
    kt_test_pass "text='é' idx=3 len=$RESULT_LENGTH (== \${#RESULT})"
else
    kt_test_fail "text='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH (want é/3/${#RESULT})"
fi

# --- offset recovery: EXACT for unanchored, repeated substrings (S5) ---
mres "repeated-substr first" "xxabcabc" "abc"  "abc"  2 3
mres "overlap 'aa' in 'aaa'"  "aaa"     "aa"    "aa"   0 2

# --- offset CAVEAT with $ anchor (S6): matched text recurs earlier ---
#     TRUE position is 4, prefix-strip reports the FIRST 'abc' at 0 (documented).
mres "S6 caveat: abc\$ index=0(caveat)" "abcXabc" 'abc$' "abc" 0 3

# --- empty match -> offset 0, length 0, rc 0 ---
mres "empty match a*"       "zzz"      "a*"    ""     0 0
kt_test_start "empty match rc is 0"
TRegEx.match "zzz" "a*"; [[ $? -eq 0 ]] && kt_test_pass "rc0" || kt_test_fail "empty match rc!=0"

# --- leftmost-LONGEST alternation (S8, ERE) vs PCRE leftmost-first ---
mres "longest (a|ab) on ab"  "ab"      "a|ab"  "ab"   0 2
mres "longest (ab|a) on ab"  "ab"      "ab|a"  "ab"   0 2

# --- dot matches newline (S1) ---
mres "dot spans newline"    $'a\nb'    "a.b"   $'a\nb' 0 3

# --- numbered groups: RESULT_GROUPS = BASH_REMATCH[1..] ---
kt_test_start "capture groups populate RESULT_GROUPS"
TRegEx.match "2026-07-12" "([0-9]+)-([0-9]+)-([0-9]+)"
if [[ "${#RESULT_GROUPS[@]}" == "3" && "${RESULT_GROUPS[0]}" == "2026" \
      && "${RESULT_GROUPS[1]}" == "07" && "${RESULT_GROUPS[2]}" == "12" ]]; then
    kt_test_pass "groups=(${RESULT_GROUPS[*]})"
else
    kt_test_fail "groups wrong: n=${#RESULT_GROUPS[@]} (${RESULT_GROUPS[*]})"
fi

kt_test_start "no groups -> empty RESULT_GROUPS"
TRegEx.match "abc" "b"
[[ "${#RESULT_GROUPS[@]}" == "0" ]] && kt_test_pass "0 groups" || kt_test_fail "expected 0 groups, got ${#RESULT_GROUPS[@]}"

# --- non-participating group in alternation = empty string (S10) ---
kt_test_start "non-participating group is empty string (S10)"
TRegEx.match "b" "(a)|(b)"
if [[ "${#RESULT_GROUPS[@]}" == "2" && "${RESULT_GROUPS[0]}" == "" && "${RESULT_GROUPS[1]}" == "b" ]]; then
    kt_test_pass "g1='' g2='b'"
else
    kt_test_fail "n=${#RESULT_GROUPS[@]} g1='${RESULT_GROUPS[0]}' g2='${RESULT_GROUPS[1]}'"
fi

# --- quantified group keeps LAST iteration (POSIX/ADJ3) ---
kt_test_start "(.)+ leaves last iteration in group 1"
TRegEx.match "abc" "(.)+"
[[ "${RESULT_GROUPS[0]}" == "c" ]] && kt_test_pass "g1='c'" || kt_test_fail "g1='${RESULT_GROUPS[0]}' (want 'c')"

# --- no-match resets the whole tuple ---
kt_test_start "no-match: RESULT='' INDEX=-1 LEN=0 GROUPS=() rc=1"
RESULT="x"; RESULT_INDEX="x"; RESULT_LENGTH="x"; RESULT_GROUPS=(a b)
TRegEx.match "zzz" "q"; rc=$?
if [[ $rc -eq 1 && "$RESULT" == "" && "$RESULT_INDEX" == "-1" && "$RESULT_LENGTH" == "0" && "${#RESULT_GROUPS[@]}" == "0" ]]; then
    kt_test_pass "reset clean, rc=1"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' idx=$RESULT_INDEX len=$RESULT_LENGTH n=${#RESULT_GROUPS[@]}"
fi

# --- invalid pattern: rc=2, tuple reset ---
kt_test_start "invalid pattern: rc=2, tuple reset"
RESULT="x"; RESULT_GROUPS=(a b)
TRegEx.match "abc" "["; rc=$?
if [[ $rc -eq 2 && "$RESULT" == "" && "$RESULT_INDEX" == "-1" && "${#RESULT_GROUPS[@]}" == "0" ]]; then
    kt_test_pass "rc=2 reset clean"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' idx=$RESULT_INDEX n=${#RESULT_GROUPS[@]}"
fi

# --- BASH_REMATCH-copy safety: a later match must not corrupt saved groups ---
kt_test_start "RESULT_GROUPS stable across a later isMatch"
TRegEx.match "a1b2" "([a-z])([0-9])"
g0="${RESULT_GROUPS[0]}"; g1="${RESULT_GROUPS[1]}"
TRegEx.isMatch "zzzz" "q"   # a failing match that CLEARS BASH_REMATCH
if [[ "$g0" == "a" && "$g1" == "1" && "${RESULT_GROUPS[0]}" == "a" && "${RESULT_GROUPS[1]}" == "1" ]]; then
    kt_test_pass "RESULT_GROUPS survived (a copy, not a BASH_REMATCH alias)"
else
    kt_test_fail "RESULT_GROUPS corrupted: (${RESULT_GROUPS[*]})"
fi

# --- i-flag on match sets RESULT to the ACTUAL (original-case) matched text ---
kt_test_start "i-flag match returns original-case text"
TRegEx.match "HELLO" "l+" "i"
[[ "$RESULT" == "LL" && "$RESULT_INDEX" == "2" ]] && kt_test_pass "RESULT='LL' idx=2" || kt_test_fail "RESULT='$RESULT' idx=$RESULT_INDEX"

kt_test_log "003_Match.sh completed"
