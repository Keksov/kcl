#!/bin/bash
# 001_Skeleton.sh - tregex class WIRING + return-contract mechanics (phase-
# stable). Proves: (1) source is green, (2) `build TRegEx` is green, (3) every
# declared member is defined, (4) the silent-RESULT / no-$()-leak contract for
# the multi-value members, (5) the body-echo contract for the scalar members
# (escape), (6) still-pending members dispatch as stubs, (7) source+dispatch
# are fork-free (PATH=''). Behavior per member lives in 002-005. Every case has
# a TEST_COVERAGE_NOTES.md row (basis: contract / P0 probe — no FPC seed).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

TREGEX_DIR="$SCRIPT_DIR/.."
source "$TREGEX_DIR/tregex.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

kt_test_section "001: TRegEx wiring + return-contract mechanics"

# --- source + build succeeded; every declared member is defined
kt_test_start "source + build: all 7 members defined"
missing=""
for m in isMatch match escape matches split replace replaceCb; do
    declare -F "TRegEx.$m" >/dev/null || missing="$missing $m"
done
if [[ -z "$missing" ]]; then
    kt_test_pass "isMatch match escape matches split replace replaceCb defined"
else
    kt_test_fail "members missing after build:$missing"
fi

# --- real predicate: isMatch hit rc0 / miss rc1 (dispatch sanity)
kt_test_start "isMatch dispatches as a predicate (hit=0, miss=1)"
TRegEx.isMatch "hello" "ell"; a=$?
TRegEx.isMatch "hello" "zzz"; b=$?
if [[ "$a" == "0" && "$b" == "1" ]]; then
    kt_test_pass "hit rc=0, miss rc=1"
else
    kt_test_fail "hit rc=$a miss rc=$b (want 0/1)"
fi

# --- multi-value contract: DIRECT match sets RESULT globally
kt_test_start "direct match sets RESULT global"
RESULT="preset"
TRegEx.match "abcd" "bc"
if [[ "$RESULT" == "bc" ]]; then
    kt_test_pass "RESULT=$RESULT after direct call"
else
    kt_test_fail "RESULT not set (got '$RESULT')"
fi

# --- multi-value contract: DIRECT match prints nothing (silent)
kt_test_start "direct match prints nothing to stdout"
tmpout="$(mktemp)"
TRegEx.match "abcd" "bc" >"$tmpout" 2>/dev/null
if [[ ! -s "$tmpout" ]]; then
    kt_test_pass "no stdout from direct call"
else
    kt_test_fail "direct call leaked stdout: [$(cat "$tmpout")]"
fi
rm -f "$tmpout"

# --- multi-value contract: $() runs in a subshell -> globals do NOT leak back
kt_test_start "match under \$(): globals do not leak to parent"
RESULT="__sentinel__"; RESULT_INDEX="__sentinel__"
cap="$(TRegEx.match "abcd" "bc")"
if [[ -z "$cap" && "$RESULT" == "__sentinel__" && "$RESULT_INDEX" == "__sentinel__" ]]; then
    kt_test_pass "\$() captured '' and parent RESULT/RESULT_INDEX unchanged"
else
    kt_test_fail "leak (cap='$cap' RESULT='$RESULT' INDEX='$RESULT_INDEX')"
fi

# --- scalar contract: escape BODY-ECHOES its value, so $() is ergonomic
kt_test_start "escape echoes scalar under \$() (owner-approved)"
e="$(TRegEx.escape 'a.c')"
if [[ "$e" == 'a\.c' ]]; then
    kt_test_pass "\$(TRegEx.escape 'a.c') = '$e'"
else
    kt_test_fail "escape \$() capture wrong (got '$e', want 'a\\.c')"
fi

# --- all members are REAL now (no stub sentinel remains after P3)
kt_test_start "no stub sentinels remain (all 7 members implemented)"
RESULT=""; TRegEx.replace "ab" "b" "X" >/dev/null
sawstub=0
[[ "$RESULT" == __tregex_stub__* ]] && sawstub=1
RESULT=""; TRegEx.replaceCb "ab" "b" : >/dev/null 2>&1
[[ "$RESULT" == __tregex_stub__* ]] && sawstub=1
if [[ $sawstub -eq 0 ]]; then
    kt_test_pass "replace/replaceCb are real (no __tregex_stub__)"
else
    kt_test_fail "a stub sentinel still leaks"
fi

# --- zero-fork: source + dispatch complete with PATH='' (no external procs)
kt_test_start "PATH='' : source + isMatch/match/escape need no external commands"
zf="$(
    PATH=''
    source "$TREGEX_DIR/tregex.sh" 2>/dev/null
    TRegEx.isMatch "abc" "b"; r1=$?
    TRegEx.match "abc" "b";   m=$RESULT
    TRegEx.escape "a.b" >/dev/null; e=$RESULT
    printf '%s|%s|%s' "$r1" "$m" "$e"
)"
if [[ "$zf" == "0|b|a\\.b" ]]; then
    kt_test_pass "dispatch under PATH='' -> $zf"
else
    kt_test_fail "PATH='' failed (got '$zf', want '0|b|a\\.b')"
fi

kt_test_log "001_Skeleton.sh completed"
