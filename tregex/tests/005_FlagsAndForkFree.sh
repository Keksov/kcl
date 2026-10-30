#!/usr/bin/env bash
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

# --- word edges (L5.4-12): the cheap check keeps a pattern without \< \> \b
#     away from the probe, the rewriter and the cache ---
kt_test_start "PATH='' : a pattern without \\< \\> \\b never reaches the word-edge probe, rewriter or cache"
out="$(
    PATH=''
    source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
    unset KCL_TREGEX_WB; TRegEx._wbReset
    __n=0
    eval "__orig_$(declare -f TRegEx._wbRewrite)"
    TRegEx._wbRewrite() { __n=$(( __n + 1 )); __orig_TRegEx._wbRewrite "$@"; }
    a=(); p=()
    TRegEx.isMatch "abc" "b"; TRegEx.match "a.c" 'a\.c'; TRegEx.matches "aXbX" "X" a
    TRegEx.split "a,b" "," p; TRegEx.replace "abc" 'b' 'x' >/dev/null; TRegEx.isMatch "aa" '(a)\1'
    s="mode=${__TRE_WB_MODE-unset} n=$__n"
    declare -p __TRE_WB_CACHE >/dev/null 2>&1 && s+=" cache=declared" || s+=" cache=none"
    TRegEx.isMatch "a foo b" '\<foo\>'; r=$?
    s+=" | rc=$r n=$__n mode=${__TRE_WB_MODE-unset}"
    KCL_TREGEX_WB=ltgt; TRegEx._wbReset; TRegEx.isMatch "abc" "b"
    s+=" | ltgt n=$__n mode=${__TRE_WB_MODE-unset}"
    printf '%s' "$s"
)"
[[ "$out" == "mode=unset n=0 cache=none | rc=0 n=1 mode="?* && "$out" == *" | ltgt n=1 mode=unset" ]] \
    && kt_test_pass "$out" || kt_test_fail "got '$out'"

# _wbcase MODE -> one PATH='' row: \<foo\> and \bfoo\b through that mode
_wbcase() {
    local m=$1 need=() __r
    kt_test_start "PATH='' : \\<foo\\> and \\bfoo\\b in word-edge mode $m are fork-free"
    case "$m" in   # the spellings this mode hands to the C library
        native)    need=('\<foo\>' '\bfoo\b') ;;
        ltgt)      need=('\<foo\>' '(\<|\>)foo(\<|\>)') ;;   # musl: only the 1st branch
        class)     need=('[[:<:]]foo[[:>:]]' '([[:<:]]|[[:>:]])foo([[:<:]]|[[:>:]])') ;;  # macOS: wrong
        ltgt-ctx)  need=('\<foo\>') ;;
        class-ctx) need=('[[:<:]]foo[[:>:]]') ;;
    esac
    for __r in "${need[@]}"; do
        if ! { [[ 'a foo b' =~ $__r ]] 2>/dev/null && ! [[ 'afoob' =~ $__r ]] 2>/dev/null; }; then
            kt_test_pass "N/A: this C library lacks '$__r', which mode $m needs"
            return
        fi
    done
    out="$(
        PATH=''
        source "$SCRIPT_DIR/../tregex.sh" 2>/dev/null
        if [[ $m == auto ]]; then unset KCL_TREGEX_WB; else KCL_TREGEX_WB=$m; fi
        TRegEx._wbReset
        TRegEx.isMatch "a foo b" '\<foo\>'; r1=$?
        TRegEx.isMatch "afoob" '\<foo\>'; r2=$?
        TRegEx.isMatch "a foo b" '\bfoo\b'; r3=$?
        TRegEx.isMatch "afoob" '\bfoo\b'; r4=$?
        TRegEx.match "a foo b" '\bf(o)o\b'; r5="$?:$RESULT:$RESULT_INDEX:${RESULT_GROUPS[*]}"
        printf '%s|%s|%s|%s|%s' "$r1" "$r2" "$r3" "$r4" "$r5"
    )"
    [[ "$out" == "0|1|0|1|0:foo:2:o" ]] && kt_test_pass "$out" \
        || kt_test_fail "mode $m: got '$out', want '0|1|0|1|0:foo:2:o'"
}
_wbcase auto
_wbcase native
_wbcase ltgt
_wbcase class
_wbcase ltgt-ctx
_wbcase class-ctx

# --- fork-free i-flag save/restore does not disturb an unrelated shopt ---
kt_test_start "i-flag toggling leaves other shopts intact"
before="$(shopt -p extglob nullglob)"
TRegEx.isMatch "ABC" "abc" i >/dev/null
after="$(shopt -p extglob nullglob)"
[[ "$before" == "$after" ]] && kt_test_pass "extglob/nullglob unchanged" \
    || kt_test_fail "shopt disturbed: [$before] -> [$after]"

kt_test_log "005_FlagsAndForkFree.sh completed"
