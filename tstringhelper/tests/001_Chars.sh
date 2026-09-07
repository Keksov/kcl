#!/bin/bash
# 001_Chars.sh — TStringHelper.Chars[] (0-based character indexing).
#
# P5: the out-of-range answer changed. The member used to PRINT the word
# "undefined" with rc 0 — neither an FPC answer (FPC's Chars[] property has no
# bounds check at all) nor a kcl one, and indistinguishable from real data
# under `$( )`. The contract is kcl/README.md 1.2: rc 1, RESULT empty, nothing
# printed. The index also goes through kk.isInt first (D1).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Chars" "$SCRIPT_DIR" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$SCRIPT_DIR/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

source "$SCRIPT_DIR/../tstringhelper.sh"

TMP="$PRIVTMP"
mkdir -p "$TMP"
OUT="$TMP/stdout.txt"

char_is() {   # EXPECTED STR INDEX
    kt_test_start "chars '$2' $3 -> '$1'"
    RESULT="__unset__"
    string.chars "$2" "$3" >/dev/null 2>&1 || :
    if [[ "$RESULT" == "$1" ]]; then
        kt_test_pass "'$1'"
    else
        kt_test_fail "chars '$2' $3 gave '$RESULT', expected '$1'"
    fi
}

char_is "h" "hello" 0
char_is "e" "hello" 1
char_is "o" "hello" 4
char_is "и" "мир" 1

char_fails() {   # TITLE STR INDEX
    kt_test_start "$1"
    RESULT="__unset__"
    local rc=0 printed
    # A DIRECT call, redirected into a file: `$( )` would run the member in a
    # subshell, where the RESULT it sets could never reach this shell.
    : > "$OUT"
    string.chars "$2" "$3" > "$OUT" 2>&1 || rc=$?
    printed="$(<"$OUT")"
    if (( rc == 1 )) && [[ -z "$printed" && -z "$RESULT" ]]; then
        kt_test_pass "rc 1, RESULT empty, silent"
    else
        kt_test_fail "rc=$rc printed='$printed' RESULT='$RESULT'"
    fi
}

char_fails "an index past the end is rc 1, not the word 'undefined'" "hello" 10
char_fails "the index equal to the length is rc 1"                   "hello" 5
char_fails "a negative index is rc 1"                                "hello" -1
char_fails "an index into an empty string is rc 1"                   ""      0
char_fails "a non-numeric index is rc 1 [D1]"                        "hello" "abc"
char_fails "an empty index is rc 1 [D1]"                             "hello" ""

kt_test_start "an injected index executes nothing [X-INJ]"
canary="$PRIVTMP/pwn001"
rm -f "$canary"
string.chars "hello" 'a[$(touch '"$canary"')]' >/dev/null 2>&1 || :
if [[ ! -e "$canary" ]]; then
    kt_test_pass "no canary"
else
    rm -f "$canary"; kt_test_fail "the injected command ran"
fi

kt_test_start "\$( ) prints the character exactly once [D3]"
got="$(string.chars "hello" 1)"
if [[ "$got" == "e" ]]; then
    kt_test_pass "e"
else
    kt_test_fail "got '$got'"
fi
