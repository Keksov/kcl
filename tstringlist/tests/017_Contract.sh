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

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$UNIT_DIR/tstringlist.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

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
TStringList.new L
L.Add banana
L.Add apple
L.count >/dev/null
L.Get 0 >/dev/null
L.IndexOf apple >/dev/null || true
L.Sort
L.Delete 0
L.Clear
L.delete'

# --- 2. numeric arguments (D1) ---------------------------------------------
kt_test_start "index-taking members reject an injection shape [G1-02]"
canary="$TMP/pwn"; rm -f "$canary"
bad="x[\$(touch '$canary')]"
TStringList.new L; L.Add a; L.Add b
accepted=""
L.Get "$bad" 2>/dev/null && accepted+="Get "
L.Delete "$bad" 2>/dev/null && accepted+="Delete "
L.Insert "$bad" v 2>/dev/null && accepted+="Insert "
if [[ ! -e "$canary" && -z "$accepted" ]]; then
    kt_test_pass "rejected, nothing executed"
else
    kt_test_fail "canary=$([[ -e "$canary" ]] && echo CREATED || echo absent) accepted: ${accepted:-none}"
fi

# --- 3. values are data (X-ECHO) -------------------------------------------
kt_test_start "values that look like echo options round-trip [G1-13]"
L.Clear
broken=""
for v in '-e' '-n' '-neE'; do
    L.Add "$v"
    L.Get $(( $(L.count >/dev/null; printf '%s' "$RESULT") - 1 )) >/dev/null
    [[ "$RESULT" == "$v" ]] || broken+="[$v] "
done
[[ -z "$broken" ]] && kt_test_pass "all round-tripped" || kt_test_fail "lost: $broken"

# --- 4. no global leakage (X-LOCALS) ---------------------------------------
kt_test_start "members do not clobber the caller's loop variables [G1-08]"
i="CALLER_I"; j="CALLER_J"
L.IndexOf a >/dev/null || true
L.Remove a >/dev/null 2>&1 || true
leaked=""
[[ "$i" == "CALLER_I" ]] || leaked+="i=$i "
[[ "$j" == "CALLER_J" ]] || leaked+="j=$j "
[[ -z "$leaked" ]] && kt_test_pass "no leak" || kt_test_fail "clobbered: $leaked"
L.delete

# --- 5. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. This runs the documented failure path and checks the caller
# still gets control — verified on 5.2.37 and 5.3.9.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
TStringList.new L; L.Get 5 || printf 'reached rc=%s' \0
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc="* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi
