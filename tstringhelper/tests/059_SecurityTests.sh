#!/bin/bash
# 059_SecurityTests.sh — the arithmetic-injection guard (X-INJ / D1), extended
# in P5 with the FPC conversion contract (TSH-14).
#
# Two of the old assertions pinned a NON-FPC dialect and are rewritten here
# (kcl/PLAN.md section 4):
#   * "toInteger strips the fractional part" — `42.99` -> `42`. FPC's
#     ToInteger is StrToInt = Val, and Val stops at the '.' with a non-zero
#     error code, so StrToInt('42.99') RAISES. Silently truncating turns a
#     typo into a plausible wrong number.
#   * "toInteger returns 0 for non-numeric input" — the member printed `0`
#     with rc 1, which under `$( )` is indistinguishable from the perfectly
#     valid answer 0. The contract is rc 1 + RESULT='' (kcl/README.md 1.2).
#
# The temp files also moved out of /tmp into the suite's fixture directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "SecurityTests" "$SCRIPT_DIR" "$@"

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

# --- 1. no argument ever reaches an arithmetic evaluation -------------------
no_exec() {   # TITLE MEMBER ARGS...  (the literal @CANARY@ is replaced)
    local title="$1"; shift
    local canary="$TMP/pwn_$$_$RANDOM"
    rm -f "$canary"
    kt_test_start "$title"
    local -a args=()
    local a
    for a in "$@"; do
        args+=("${a//@CANARY@/$canary}")
    done
    "${args[@]}" >/dev/null 2>&1 || :
    if [[ ! -e "$canary" ]]; then
        kt_test_pass "$title"
    else
        rm -f "$canary"
        kt_test_fail "$title: the injected command RAN"
    fi
}

INJ='a[$(touch @CANARY@)]'

no_exec "toInteger does not execute an injected command [X-INJ]"   string.toInteger "$INJ"
no_exec "toInt64 does not execute an injected command [X-INJ]"     string.toInt64   "$INJ"
no_exec "toDouble does not execute an injected command [X-INJ]"    string.toDouble  "$INJ"
no_exec "toExtended does not execute an injected command [X-INJ]"  string.toExtended "$INJ"
no_exec "toSingle does not execute an injected command [X-INJ]"    string.toSingle  "$INJ"
no_exec "toBoolean does not execute an injected command [X-INJ]"   string.toBoolean "$INJ"
no_exec "substring startIndex [X-INJ]"        string.substring hello "$INJ"
no_exec "substring length [X-INJ]"            string.substring hello 0 "$INJ"
no_exec "remove startIndex [X-INJ]"           string.remove hello "$INJ"
no_exec "insert index [X-INJ]"                string.insert hello "$INJ" X
no_exec "chars index [X-INJ]"                 string.chars hello "$INJ"
no_exec "isDelimiter index [X-INJ]"           string.isDelimiter hello "$INJ" l
no_exec "padLeft width [X-INJ]"               string.padLeft x "$INJ"
no_exec "padRight width [X-INJ]"              string.padRight x "$INJ"
no_exec "indexOf startIndex [X-INJ]"          string.indexOf hello l "$INJ"
no_exec "indexOf count [X-INJ]"               string.indexOf hello l 0 "$INJ"
no_exec "indexOfAny startIndex [X-INJ]"       string.indexOfAny hello lo "$INJ"
no_exec "indexOfAnyUnquoted startIndex [X-INJ]" string.indexOfAnyUnquoted hello lo '"' '"' "$INJ"
no_exec "lastIndexOf startIndex [X-INJ]"      string.lastIndexOf hello l "$INJ"
no_exec "lastIndexOfAny startIndex [X-INJ]"   string.lastIndexOfAny hello lo "$INJ"
no_exec "create count [X-INJ]"                string.create x "$INJ"
no_exec "copyTo source index [X-INJ]"         string.copyTo abc "$INJ" dst059 0 1
no_exec "toCharArray start index [X-INJ]"     string.toCharArray abc "$INJ"
no_exec "split count [X-INJ]"                 string.split a,b , parts059 "$INJ"

# --- 2. the FPC conversion contract (TSH-14) --------------------------------
conv_is() {   # TITLE EXPECTED-RESULT MEMBER ARGS...
    local title="$1" want="$2"; shift 2
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == 0 )) && [[ "$RESULT" == "$want" ]]; then
        kt_test_pass "$title -> $want"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' (wanted 0 / '$want')"
    fi
}

conv_rejects() {   # TITLE MEMBER ARGS...
    local title="$1"; shift
    kt_test_start "$title"
    RESULT="__unset__"
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    if (( rc == 1 )) && [[ -z "$RESULT" ]]; then
        kt_test_pass "$title (rc 1, RESULT empty)"
    else
        kt_test_fail "$title: rc=$rc RESULT='$RESULT' (wanted rc 1 and an empty RESULT)"
    fi
}

conv_is "toInteger parses a decimal integer" "123" string.toInteger "123"
conv_is "toInteger keeps a negative sign"    "-7"  string.toInteger "-7"
conv_is "toInteger normalises a leading +"   "7"   string.toInteger "+7"
conv_is "toInteger normalises leading zeros" "7"   string.toInteger "007"
conv_is "toInteger accepts the value zero"   "0"   string.toInteger "0"

conv_rejects "toInteger REJECTS a fractional literal (FPC raises) [TSH-14]" \
    string.toInteger "42.99"
conv_rejects "toInteger REJECTS a word (0 was indistinguishable) [TSH-14]" \
    string.toInteger "hello"
conv_rejects "toInteger REJECTS an empty string [TSH-14]" \
    string.toInteger ""
conv_rejects "toInteger REJECTS the injection shape [TSH-14, X-INJ]" \
    string.toInteger 'a[$(id)]'
conv_rejects "toInt64 REJECTS a fractional literal [TSH-14]" \
    string.toInt64 "42.99"
