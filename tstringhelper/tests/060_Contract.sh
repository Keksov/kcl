#!/bin/bash
# Contract — the kcl-wide contract for this unit (kcl/README.md section 1),
# written for phase P1 of the 2026-09-06 review. What it pins:
#
#   X-SETU (G8-01)   the unit loads, and RE-loads, under `set -eu` (decision D7).
#   X-INJ  (D1)      a caller-supplied index/count never reaches `(( ))` raw.
#   X-ECHO (G1-13)   values that look like echo options round-trip verbatim.
#   source integrity a sweeping mechanical edit must not silently mangle the
#                    file. In P1 an echo->printf sweep put a REAL newline inside
#                    the format string; the output was byte-identical, so every
#                    behavioural test stayed green while 534 statements were cut
#                    in half. `bash -n` plus "no single-quoted string left open"
#                    catches that whole class for the price of two greps.
#
# These files are deliberately near-identical across the suites: a change to the
# contract should be a mechanical sweep, not a re-reading of 17 dialects.

KTESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../ktests" && pwd)"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Contract" "$(dirname "$0")" "$@"

# A directory of our own: the ktests fixture temp dir is named after $0, which
# is "bash" for every file the runner starts, and the runner runs files in
# PARALLEL — a neighbour's teardown deletes it while we are using it, and a
# redirect into a vanished directory means the member never runs at all
# (kcl_ledger.json, found_in_P4/P4-F2).
PRIVTMP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.tmp/$(basename "${BASH_SOURCE[0]}" .sh)"
mkdir -p "$PRIVTMP"

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$UNIT_DIR/tstringhelper.sh"
source "$UNIT"

TMP="$PRIVTMP"

# --- 0. source integrity ---------------------------------------------------
kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then
    kt_test_pass "bash -n clean"
else
    kt_test_fail "bash -n: $err"
fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then
    kt_test_fail "unterminated format string(s): ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

# --- 1. set -eu ------------------------------------------------------------
# Each check runs in a child shell so a failure cannot abort this file, and
# asserts on stderr too: `set -u` exists to turn a silent typo into a message.
expect_clean() {   # TITLE SNIPPET
    local title="$1" snippet="$2" out rc err
    local errf="$TMP/setu.err"
    kt_test_start "$title"
    out="$(bash -c "set -eu
source '$UNIT'
$snippet
printf OK" 2>"$errf")"; rc=$?
    err="$(<"$errf")"
    if [[ $rc -eq 0 && "$out" == "OK" && -z "$err" ]]; then
        kt_test_pass "clean under set -eu"
    else
        kt_test_fail "rc=$rc out='$out' stderr='$err'"
    fi
}

expect_clean "the unit loads under set -eu [X-SETU, D7]" ":"
expect_clean "loading the unit TWICE under set -eu is a no-op [X-SETU]" "source '$UNIT'"
expect_clean "main path under set -eu [X-SETU, D7]" '
string.substring hello 1 3 >/dev/null
string.trim "  x  " >/dev/null
string.indexOf hello l >/dev/null
string.padLeft ab 5 >/dev/null
string.toUpper abc >/dev/null
string.create x 3 >/dev/null'

# --- 2. numeric arguments (D1) ---------------------------------------------
kt_test_start "every index/count parameter rejects an injection shape [TSH-01]"
canary="$TMP/pwn"; rm -f "$canary"
bad="x[\$(touch '$canary')]"
accepted=""
for call in "substring hello" "remove hello" "insert hello" "chars hello" \
            "isDelimiter hello" "padLeft x" "padRight x" "indexOf hello l" \
            "indexOfAny hello lo" "lastIndexOf hello l" "lastIndexOfAny hello lo" \
            "create x"; do
    string.$call "$bad" >/dev/null 2>&1 && accepted+="${call%% *} "
done
if [[ ! -e "$canary" && -z "$accepted" ]]; then
    kt_test_pass "12 entry points rejected, nothing executed"
else
    kt_test_fail "canary=$([[ -e "$canary" ]] && echo CREATED || echo absent) accepted: ${accepted:-none}"
fi

# --- 3. values are data (X-ECHO) -------------------------------------------
kt_test_start "values that look like echo options round-trip [TSH-02]"
broken=""
[[ "$(string.trim ' -n ')" == "-n" ]] || broken+="trim "
[[ "$(string.toUpper -e)" == "-E" ]] || broken+="toUpper "
[[ "$(string.substring '-name' 0 2)" == "-n" ]] || broken+="substring "
[[ -z "$broken" ]] && kt_test_pass "all round-tripped" || kt_test_fail "lost: $broken"

# --- 4. no global leakage (X-LOCALS) ---------------------------------------
kt_test_start "members do not clobber the caller's loop variables [TSH-10]"
i="CALLER_I"; arg="CALLER_ARG"
string.padLeft x 3 >/dev/null
string.create x 3 >/dev/null
string.join , a b c >/dev/null 2>&1 || true
leaked=""
[[ "$i" == "CALLER_I" ]] || leaked+="i=$i "
[[ "$arg" == "CALLER_ARG" ]] || leaked+="arg=$arg "
[[ -z "$leaked" ]] && kt_test_pass "no leak" || kt_test_fail "clobbered: $leaked"

# --- 5. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. This runs the documented failure path and checks the caller
# still gets control — verified on 5.2.37 and 5.3.9.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
string.substring hello abc >/dev/null || printf 'reached rc=%s' \0
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc="* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi

# --- 6. the return contract (P5: D3 / R8, kcl/README.md 1.1-1.3) -----------
# 061_TSH17_ReturnContract.sh works through this member by member; what
# belongs in the CONTRACT file is the rule itself, in the same shape every
# other kcl suite states it.
kt_test_start "a direct call prints nothing and answers in RESULT [D3, 1.1]"
RESULT="__unset__"
: > "$TMP/direct.out"
string.substring "hello world" 6 > "$TMP/direct.out" 2>&1 || :
printed="$(<"$TMP/direct.out")"
if [[ -z "$printed" && "$RESULT" == "world" ]]; then
    kt_test_pass "silent, RESULT=world"
else
    kt_test_fail "printed='$printed' RESULT='$RESULT'"
fi

kt_test_start "the same call inside \$( ) prints the value exactly once [D3, 1.1]"
got="$(string.substring "hello world" 6)"
if [[ "$got" == "world" ]]; then
    kt_test_pass "world"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "a boolean answers with its exit status [R8, 1.3]"
rc_true=0; rc_false=0
string.contains "abc" "b" >/dev/null || rc_true=$?
string.contains "abc" "z" >/dev/null || rc_false=$?
if (( rc_true == 0 && rc_false == 1 )) && [[ "$RESULT" == "false" ]]; then
    kt_test_pass "rc 0 / rc 1, RESULT=false"
else
    kt_test_fail "rc_true=$rc_true rc_false=$rc_false RESULT='$RESULT'"
fi

kt_test_start "an error is rc 1 with an empty RESULT and no output [1.2]"
RESULT="__unset__"
: > "$TMP/err.out"
rc=0
string.chars "abc" 99 > "$TMP/err.out" 2>&1 || rc=$?
printed="$(<"$TMP/err.out")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

# --- 7. output arrays (kcl/README.md 1.7) ----------------------------------
kt_test_start "an output-array member fills the caller array and counts in RESULT [1.7]"
declare -a ctr_parts=(sentinel)
RESULT="__unset__"
string.split "a,b,c" "," ctr_parts >/dev/null 2>&1 || :
if [[ "$RESULT" == "3" && "${ctr_parts[*]}" == "a b c" ]]; then
    kt_test_pass "3 parts"
else
    kt_test_fail "RESULT='$RESULT' parts=(${ctr_parts[*]})"
fi

kt_test_start "every reserved output-array name is refused with rc 2 [1.7]"
accepted=""
for name in RESULT REPLY IFS this __inst__ __class__ __kk_x __KK_X __tsh_x "" "1bad" "not valid"; do
    rc=0
    string.split "a,b" "," "$name" >/dev/null 2>&1 || rc=$?
    (( rc == 2 )) || accepted+="${name:-<empty>}(rc $rc) "
done
if [[ -z "$accepted" ]]; then
    kt_test_pass "12 names refused"
else
    kt_test_fail "not refused with rc 2: $accepted"
fi

# --- 8. the locale self-heal (D6, kcl/README.md 1.6) -----------------------
kt_test_start "character semantics survive a bare environment [D6, TSH-04]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
string.length 'мир'; printf '%s' \"\$RESULT\"" 2>&1)"
if [[ "$out" == "3" ]]; then
    kt_test_pass "3 characters"
else
    kt_test_fail "got '$out'"
fi

# --- 9. no forks in the hot paths (1.8) ------------------------------------
kt_test_start "no member body shells out [1.8]"
forking=""
for m in "${string_class_static_methods[@]}"; do
    body="$(declare -f "string.__static_$m" 2>/dev/null)"
    body="${body//\$((/ARITH}"
    if [[ "$body" == *'$('* || "$body" == *'`'* ]]; then
        forking+="$m "
    fi
done
if [[ -z "$forking" ]]; then
    kt_test_pass "${#string_class_static_methods[@]} members, none forks"
else
    kt_test_fail "command substitution in: $forking"
fi
