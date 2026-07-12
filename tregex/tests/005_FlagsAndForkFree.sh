#!/bin/bash
# 005_FlagsAndForkFree.sh - the i-flag semantics (case sensitivity is decided
# SOLELY by the flag, ambient `shopt nocasematch` RESTORED after every call),
# and the zero-fork discipline (PATH='' on every P1 entry point; no $() in the
# match path — proven by dynamic-scope RESULT propagation). Basis: PLAN §2.3 +
# P0 probe S4.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"
source "$SCRIPT_DIR/../tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "005: TRegEx i-flag + fork-free"

# --- i-flag basic control ---
kt_test_start "i present -> insensitive; absent -> sensitive"
TRegEx.isMatch "ABC" "abc" i; a=$?
TRegEx.isMatch "ABC" "abc";   b=$?
[[ "$a" == "0" && "$b" == "1" ]] && kt_test_pass "i=0 no-i=1" || kt_test_fail "i=$a no-i=$b"

# --- flag DETERMINISM: ambient nocasematch ON must NOT leak into a no-i call ---
kt_test_start "no-i call is case-sensitive even when ambient nocasematch is ON"
shopt -s nocasematch
TRegEx.isMatch "ABC" "abc"; r=$?      # no i-flag -> must force sensitive -> miss
shopt -u nocasematch
[[ "$r" == "1" ]] && kt_test_pass "forced sensitive (rc1) despite ambient ON" \
    || kt_test_fail "ambient leaked (rc=$r, expected 1)"

# --- ambient RESTORE: caller had nocasematch OFF -> still OFF after an i call ---
kt_test_start "ambient OFF restored after i-flag call"
shopt -u nocasematch
TRegEx.isMatch "ABC" "abc" i >/dev/null
if shopt -q nocasematch; then kt_test_fail "nocasematch left ON"; else kt_test_pass "still OFF"; fi

# --- ambient RESTORE: caller had nocasematch ON -> still ON after a no-i call ---
kt_test_start "ambient ON restored after no-i call"
shopt -s nocasematch
TRegEx.isMatch "abc" "abc" >/dev/null
if shopt -q nocasematch; then kt_test_pass "still ON"; else kt_test_fail "nocasematch left OFF"; fi
shopt -u nocasematch   # cleanup

# --- ambient RESTORE across match() and on the invalid-pattern path too ---
kt_test_start "ambient ON restored even when pattern is invalid"
shopt -s nocasematch
TRegEx.match "abc" "["   # rc2, must still restore
ok1=$(shopt -q nocasematch && echo on || echo off)
shopt -u nocasematch
[[ "$ok1" == "on" ]] && kt_test_pass "restored ON after rc2 path" || kt_test_fail "state=$ok1"

# --- i-flag on match preserves original-case text + correct groups ---
kt_test_start "i-flag match: original-case text and groups"
TRegEx.match "FOO=Bar" "([a-z]+)=([a-z]+)" i
if [[ "$RESULT" == "FOO=Bar" && "${RESULT_GROUPS[0]}" == "FOO" && "${RESULT_GROUPS[1]}" == "Bar" ]]; then
    kt_test_pass "text='FOO=Bar' g=(FOO Bar)"
else
    kt_test_fail "RESULT='$RESULT' g=(${RESULT_GROUPS[*]})"
fi

# --- no-subshell proof: _match1 writes caller locals via dynamic scope ---
# (if it ran in a $() subshell those writes would be lost; they are not).
kt_test_start "match path runs in-process (no subshell wrapping)"
RESULT="pre"
TRegEx.match "abc" "b"
[[ "$RESULT" == "b" ]] && kt_test_pass "global RESULT set in-process" \
    || kt_test_fail "RESULT='$RESULT' (a subshell would have lost it)"

# --- zero-fork: every P1 entry point completes with PATH='' ---
kt_test_start "PATH='' : isMatch / match / escape need no external commands"
out="$(
    PATH=''
    source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
    TRegEx.isMatch "ABC" "abc" i; r=$?
    TRegEx.match "xxABC" "abc" i; m="$RESULT"; idx="$RESULT_INDEX"
    TRegEx.escape 'a.b' >/dev/null; e="$RESULT"
    printf '%s|%s|%s|%s' "$r" "$m" "$idx" "$e"
)"
[[ "$out" == "0|ABC|2|a\\.b" ]] && kt_test_pass "all fork-free -> $out" \
    || kt_test_fail "PATH='' path failed (got '$out', want '0|ABC|2|a\\.b')"

# --- fork-free i-flag save/restore does not disturb an unrelated shopt ---
kt_test_start "i-flag toggling leaves other shopts intact"
before="$(shopt -p extglob nullglob)"
TRegEx.isMatch "ABC" "abc" i >/dev/null
after="$(shopt -p extglob nullglob)"
[[ "$before" == "$after" ]] && kt_test_pass "extglob/nullglob unchanged" \
    || kt_test_fail "shopt disturbed: [$before] -> [$after]"

kt_test_log "005_FlagsAndForkFree.sh completed"
