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
UNIT="$UNIT_DIR/tqueuestack.sh"
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
TQueue.new q
q.Enqueue alpha
q.Count >/dev/null
q.Peek >/dev/null
q.Dequeue >/dev/null
q.Clear
q.delete
TStack.new s
s.Push x
s.Pop >/dev/null
s.delete'

# P9-F3: `declare -a out=()` is the normal way to prepare a receiving array, and
# an array that has been declared but never given a value is UNBOUND for the
# `${ref@a}` expansion — so the assoc-target probe in _toArray aborted the whole
# caller under `set -u`. tinifile hit this in P8 and fixed it with `local -;
# set +u` around the one expansion; this unit had the bare form.
expect_clean "ToArray into a declared-but-empty array under set -eu [P9-F3]" '
TQueue.new q
q.Enqueue alpha
declare -a qout=()
q.ToArray qout
q.delete
TStack.new s
s.Push x
declare -a sout=()
s.ToArray sout
s.delete'
expect_clean "ToArray into a declared-but-unset array under set -eu [P9-F3]" '
TQueue.new q
q.Enqueue alpha
declare -a qout
q.ToArray qout
q.delete'

# --- 3. values are data (X-ECHO) -------------------------------------------
kt_test_start "values that look like echo options round-trip [G2-03]"
TQueue.new Q
broken=""
for v in '-e' '-n' '-neE' '-e -n'; do
    Q.Enqueue "$v"
    got="$(Q.Peek)"
    [[ "$got" == "$v" ]] || broken+="[$v] "
    Q.Dequeue >/dev/null
done
[[ -z "$broken" ]] && kt_test_pass "all round-tripped" || kt_test_fail "lost: $broken"
Q.delete

# --- 5. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. This runs the documented failure path and checks the caller
# still gets control — verified on 5.2.37 and 5.3.9.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
TQueue.new q; q.Dequeue >/dev/null || printf 'reached rc=%s' \0
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc="* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi
