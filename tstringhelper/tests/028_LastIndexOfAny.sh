#!/bin/bash
# 028_LastIndexOfAny.sh — rewritten in P5 for finding TSH-06.
#
# Two of the old assertions accepted either of two answers ("4 or 7",
# "4 or -1"), which hid the same StartIndex/ACount arithmetic defect as in
# lastIndexOf.
#
# FPC (rtl/objpas/sysutils/syshelp.inc, LastIndexOfAny(AnyOf, AStartIndex,
# ACount)):
#
#     Result := AStartIndex+1;            // 1-based scan position
#     Min := Result-ACount+1; if Min<1 then Min:=1;
#     while (Result>=Min) and not HaveChar(Self[Result],AnyOf) do Dec(Result);
#     if Result<Min then Result:=-1 else Result:=Result-1;
#
# so AStartIndex is the INCLUSIVE upper end of the window and ACount its
# length. Defaults: AStartIndex = Length-1, ACount = Length. AnyOf is a SET of
# characters; an empty set never matches.
#
# One documented deviation: FPC does not clamp the scan position to the end of
# the string (Self[Result] past Length is undefined memory in Pascal); this
# port clamps to the last character, so a StartIndex past the end behaves like
# the last character rather than reading out of bounds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "LastIndexOfAny" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

source "$SCRIPT_DIR/../tstringhelper.sh"

la_is() {   # EXPECTED ARGS...
    local want="$1"; shift
    kt_test_start "lastIndexOfAny $* -> $want [TSH-06]"
    RESULT="__unset__"
    string.lastIndexOfAny "$@" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$want"
    else
        kt_test_fail "lastIndexOfAny $* gave '$RESULT', expected '$want'"
    fi
}

# --- defaults ---------------------------------------------------------------
la_is 7  "hello world" "aeiou"
la_is -1 "hello" "xyz"
la_is 4  "hello" "o"
la_is 5  "aabbcc" "bc"
la_is 0  "hello" "h"
la_is 7  "beautiful" "aeiou"
la_is 4  "Hello" "aeiou"
la_is 2  "aaa" "a"
la_is -1 "hello" ""
la_is -1 "" "a"

# --- StartIndex is the inclusive upper end ----------------------------------
la_is 4  "hello world" "aeiou" 5
la_is 4  "hello world" "aeiou" 4
la_is 1  "hello world" "aeiou" 3
la_is 7  "hello world" "aeiou" 7
la_is -1 "hello world" "aeiou" 0

# --- ACount is the window length --------------------------------------------
la_is 4  "hello world" "aeiou" 5 5
la_is 4  "hello world" "aeiou" 5 2
la_is -1 "hello world" "aeiou" 5 1
la_is 7  "hello world" "aeiou" 8 2
la_is -1 "hello world" "aeiou" 8 1
la_is -1 "hello" "o" 4 0

# --- a StartIndex past the end clamps to the last character (deviation) -----
la_is 4  "hello" "o" 99 99
la_is -1 "hello" "o" 99

kt_test_start "a non-numeric StartIndex is rc 1 [D1]"
rc=0; string.lastIndexOfAny "hello" "l" "abc" >/dev/null 2>&1 || rc=$?
if (( rc == 1 )); then kt_test_pass "rc 1"; else kt_test_fail "rc=$rc"; fi

kt_test_start "an injected ACount executes nothing [X-INJ]"
canary="$PRIVTMP/pwn028"
rm -f "$canary"
string.lastIndexOfAny "hello" "l" 4 'a[$(touch '"$canary"')]' >/dev/null 2>&1 || :
if [[ ! -e "$canary" ]]; then
    kt_test_pass "no canary"
else
    rm -f "$canary"; kt_test_fail "the injected command ran"
fi
