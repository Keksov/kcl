#!/bin/bash
# 027_LastIndexOf.sh — rewritten in P5 for finding TSH-06.
#
# Three of the old assertions accepted EITHER of two answers ("12 or 0",
# "3 or 9", "5 or -1"), which is how the wrong StartIndex/ACount arithmetic
# stayed green: the member treated StartIndex as EXCLUSIVE and computed its
# lower bound as the scan START, so `lastIndexOf hello lo 4` answered -1 where
# FPC answers 3.
#
# FPC (rtl/objpas/sysutils/syshelp.inc, LastIndexOf(const AValue: string;
# AStartIndex, ACount)):
#
#     if (L=0) or (L>LS) then Exit(-1);      // empty or oversized needle
#     I := AStartIndex+1; if I>LS then I:=LS; I := I-L+1;
#     M := AStartIndex-ACount+2; if M<1 then M:=1;
#     while (Result=-1) and (I>=M) do  ... Dec(I);
#
# i.e. StartIndex is the INCLUSIVE index of the last character the match may
# END on — `I:=I-L+1` moves the scan start back by the needle length, which is
# why `lastIndexOf hello lo 4` finds the match at 3 — and ACount is a lower
# bound counted back from StartIndex. Defaults: StartIndex = Length-1,
# ACount = Length.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "LastIndexOf" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

source "$SCRIPT_DIR/../tstringhelper.sh"

li_is() {   # EXPECTED ARGS...
    local want="$1"; shift
    kt_test_start "lastIndexOf $* -> $want [TSH-06]"
    RESULT="__unset__"
    string.lastIndexOf "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$want"
    else
        kt_test_fail "lastIndexOf $* gave '$RESULT', expected '$want'"
    fi
}

# --- defaults ---------------------------------------------------------------
li_is 7  "hello world" "o"
li_is 12 "hello world hello" "hello"
li_is -1 "hello" "z"
li_is 0  "hello" "h"
li_is 5  "aabbaa" "a"
li_is 4  "hello" "o"
li_is 6  "hello world" "world"
li_is -1 "Hello World" "h"
li_is 0  "hello" "hello"
li_is -1 "hi" "hello"

# --- the three cases the review measured against FPC ------------------------
li_is 3  "hello" "lo" 4
li_is 3  "hello" "l" 3
li_is 3  "hello" "l" 4 5

# --- StartIndex is INCLUSIVE ------------------------------------------------
li_is 2  "hello" "l" 2
li_is -1 "hello" "l" 1
li_is 0  "hello world hello" "hello" 10
li_is 0  "hello world hello" "hello" 11
li_is 0  "hello world hello" "hello" 15
li_is 12 "hello world hello" "hello" 16

# --- ACount is a lower bound counted back from StartIndex -------------------
li_is -1 "hello world hello" "l" 8 5
li_is 3  "hello world hello" "l" 8 6
li_is 9  "hello world hello" "l" 9 1
li_is -1 "hello world hello" "l" 8 1
li_is -1 "hello" "l" 3 0

# --- FPC edge cases ---------------------------------------------------------
# An empty needle is -1 (Pos('') = 0), not the string length.
li_is -1 "hello" ""
# A StartIndex past the end clamps the scan start to the last character, but
# the lower bound M is computed from the RAW StartIndex, so with the default
# ACount the window is empty. This is FPC's arithmetic, verbatim.
li_is -1 "hello" "l" 99
li_is 3  "hello" "l" 99 99

kt_test_start "a non-numeric StartIndex is rc 1 [D1]"
rc=0; string.lastIndexOf "hello" "l" "abc" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then kt_test_pass "rc 1"; else kt_test_fail "rc=$rc"; fi

kt_test_start "an injected StartIndex executes nothing [X-INJ]"
canary="$PRIVTMP/pwn027"
rm -f "$canary"
string.lastIndexOf "hello" "l" 'a[$(touch '"$canary"')]' >/dev/null 2>&1 || :
if [[ ! -e "$canary" ]]; then
    kt_test_pass "no canary"
else
    rm -f "$canary"; kt_test_fail "the injected command ran"
fi

# --- P5 review remark 1: a negative index or count is a rejected VALUE -----
# FPC's window arithmetic with a negative StartIndex is undefined by accident
# (it indexes Self at or below 0), so the search family answers rc 1 with an
# empty RESULT instead of reproducing it. The Copy/Delete clamping that FPC
# genuinely DEFINES stays where it belongs — substring and remove.
neg_rejected() {   # TITLE MEMBER ARGS...
    local title="$1"; shift
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT'"
    fi
}

neg_rejected "lastIndexOf with a negative StartIndex is rc 1"  string.lastIndexOf hello l -1
neg_rejected "lastIndexOf with a negative Count is rc 1"       string.lastIndexOf hello l 4 -2
neg_rejected "indexOf with a negative StartIndex is rc 1"      string.indexOf hello l -1
neg_rejected "indexOf with a negative Count is rc 1"           string.indexOf hello l 0 -1
neg_rejected "indexOfAny with a negative StartIndex is rc 1"   string.indexOfAny hello lo -1
neg_rejected "indexOfAny with a negative Count is rc 1"        string.indexOfAny hello lo 0 -1
neg_rejected "lastIndexOfAny with a negative StartIndex is rc 1" string.lastIndexOfAny hello lo -1
neg_rejected "lastIndexOfAny with a negative Count is rc 1"    string.lastIndexOfAny hello lo 4 -1
neg_rejected "indexOfAnyUnquoted with a negative StartIndex is rc 1" \
    string.indexOfAnyUnquoted hello lo '"' '"' -1
neg_rejected "indexOfAnyUnquoted with a negative Count is rc 1" \
    string.indexOfAnyUnquoted hello lo '"' '"' 0 -1

# The FPC-defined clamping is untouched: substring and remove still take a
# negative index the way fpc_ansistr_copy / fpc_ansistr_delete define it.
kt_test_start "substring keeps FPC Copy clamping for a negative index [TSH-11]"
RESULT="__unset__"
string.substring hello -3 >/dev/null 2>&1 || :
if [[ "$RESULT" == "hello" ]]; then
    kt_test_pass "hello"
else
    kt_test_fail "RESULT='$RESULT'"
fi

kt_test_start "remove keeps FPC Delete clamping for a negative index [TSH-11]"
RESULT="__unset__"
string.remove hello -1 >/dev/null 2>&1 || :
if [[ "$RESULT" == "hello" ]]; then
    kt_test_pass "hello"
else
    kt_test_fail "RESULT='$RESULT'"
fi
