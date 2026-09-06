#!/bin/bash
# Contract — the kcl-wide contract for this unit (kcl/README.md section 1),
# kcl review 2026-09-06 phase P1. Findings pinned here:
#
#   G1-02 / X-INJ   index arguments reach `(( ))` unvalidated, so
#                   `L.Get 'x[$(touch pwn)]'` EXECUTES the command substitution
#                   and `L.Get abc` silently returns element 0 with rc 0.
#   G1-08 / X-LOCALS loop counters i/j are globals and clobber the caller's.
#   G8-01 / X-SETU  the unit is not sourceable under `set -u` (D7).
#   G1-13 / X-ECHO  values that look like echo options must round-trip (fixed in
#                   kklass at P0; pinned here because this unit is a value store).
#
# Every kcl suite carries one of these; they are deliberately near-identical so
# a contract change is a mechanical sweep, not a re-reading of 17 dialects.

KTESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../ktests" && pwd)"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Contract" "$(dirname "$0")" "$@"

UNIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT="$UNIT_DIR/tlist.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# --- 0. source integrity ---------------------------------------------------
# A sweeping mechanical edit can produce a file that still BEHAVES correctly and
# so passes every behavioural test, while the source itself is mangled. That
# happened in P1: an `echo` -> `printf` transform put a real newline inside the
# format string, so `printf '%s\n' "$x"` became `printf '%s` + newline + `' "$x"`
# — identical output, every suite green, 534 statements split in half. These two
# cheap checks catch that whole class.
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
# Run SNIPPET in a child shell under `set -eu`; it must print exactly OK, write
# nothing to stderr and exit 0.
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

expect_clean "loading the unit TWICE under set -eu is a no-op [X-SETU]" \
    "source '$UNIT'"

expect_clean "main path under set -eu [X-SETU, D7]" '
TList.new L
L.Add alpha
L.Add beta
L.Insert 1 gamma
L.Get 2 >/dev/null
L.count >/dev/null
L.IndexOf beta >/dev/null
L.Delete 0
L.Clear
L.delete'

# --- 2. numeric arguments (D1) --------------------------------------------
TList.new L
L.Add zero; L.Add one; L.Add two

kt_test_start "an injection-shaped index is rejected and never evaluated [G1-02]"
canary="$TMP/pwn"
rm -f "$canary"
RESULT="sentinel"
L.Get "x[\$(touch '$canary')]" 2>/dev/null; rc=$?
if [[ $rc -ne 0 && ! -e "$canary" && "$RESULT" == "sentinel" ]]; then
    kt_test_pass "rc=$rc, no side effect, RESULT untouched"
else
    kt_test_fail "rc=$rc canary=$([[ -e "$canary" ]] && echo CREATED || echo absent) RESULT='$RESULT'"
fi

kt_test_start "every index-taking member rejects an injection shape [G1-02]"
bad="x[\$(touch '$TMP/pwn2')]"
rm -f "$TMP/pwn2"
leaked=""
for call in "Get $bad" "Put $bad v" "Delete $bad" "Insert $bad v" \
            "Exchange 0 $bad" "Move 0 $bad"; do
    # shellcheck disable=SC2086
    L.$call >/dev/null 2>&1 && leaked+="L.${call%% *} accepted; "
done
L.capacity = "$bad" 2>/dev/null || true
L.count = "$bad" 2>/dev/null || true
[[ -e "$TMP/pwn2" ]] && leaked+="COMMAND EXECUTED; "
[[ -z "$leaked" ]] && kt_test_pass "all rejected, nothing executed" \
    || kt_test_fail "$leaked"

kt_test_start "a non-numeric index is rejected, not read as element 0 [G1-02]"
RESULT="sentinel"
L.Get abc 2>/dev/null; rc=$?
[[ $rc -ne 0 && "$RESULT" == "sentinel" ]] && kt_test_pass "rc=$rc, RESULT untouched" \
    || kt_test_fail "rc=$rc RESULT='$RESULT' (expected rejection, not element 0)"

kt_test_start "a leading-zero index is read as decimal, not octal [D1, G3-01]"
L.Clear
for n in 0 1 2 3 4 5 6 7 8 9; do L.Add "item$n"; done
RESULT=""
L.Get 08; rc=$?
[[ $rc -eq 0 && "$RESULT" == "item8" ]] && kt_test_pass "08 -> item8" \
    || kt_test_fail "rc=$rc RESULT='$RESULT' (expected item8)"

kt_test_start "an out-of-range index is rejected and leaves RESULT alone"
RESULT="sentinel"
L.Get 999 2>/dev/null; rc=$?
[[ $rc -ne 0 && "$RESULT" == "sentinel" ]] && kt_test_pass "rc=$rc" \
    || kt_test_fail "rc=$rc RESULT='$RESULT'"

# --- 3. values are data (X-ECHO) ------------------------------------------
kt_test_start "values that look like echo options round-trip through \$() [G1-13]"
L.Clear
bad_values=('-e' '-n' '-E' '-neE' '-e -n' $'a\nb' '\\' '  spaced  ')
broken=""
for i in "${!bad_values[@]}"; do
    L.Add "${bad_values[$i]}"
    got="$(L.Get "$i")"
    [[ "$got" == "${bad_values[$i]}" ]] || broken+="[$i] "
done
[[ -z "$broken" ]] && kt_test_pass "${#bad_values[@]} values round-tripped" \
    || kt_test_fail "lost at indices: $broken"

kt_test_start "the same values round-trip through the direct-call RESULT idiom"
broken=""
for i in "${!bad_values[@]}"; do
    RESULT=""
    L.Get "$i"
    [[ "$RESULT" == "${bad_values[$i]}" ]] || broken+="[$i] "
done
[[ -z "$broken" ]] && kt_test_pass "all round-tripped" || kt_test_fail "lost at indices: $broken"

# --- 4. no global leakage (X-LOCALS) --------------------------------------
kt_test_start "members do not clobber the caller's loop variables [G1-08]"
L.Clear
L.Add a; L.Add b; L.Add c
i="CALLER_I"; j="CALLER_J"; index="CALLER_INDEX"
L.IndexOf c >/dev/null
L.Insert 0 z
L.Delete 0
L.Sort >/dev/null 2>&1 || true
L.count >/dev/null
leaked=""
[[ "$i" == "CALLER_I" ]] || leaked+="i=$i "
[[ "$j" == "CALLER_J" ]] || leaked+="j=$j "
[[ "$index" == "CALLER_INDEX" ]] || leaked+="index=$index "
[[ -z "$leaked" ]] && kt_test_pass "no leak" || kt_test_fail "clobbered: $leaked"

# --- 5. lifecycle (X-LEAK) -------------------------------------------------
# `.delete` frees every `${inst}_*` this unit creates (kcl/README.md 1.9). TList
# had no destructor at all until P2, so every deleted list leaked its storage
# (finding G1-01); the regression detail lives in 021_ReviewP2.sh.
kt_test_start "delete frees every per-instance array this unit creates [G1-01]"
L.Clear; L.Add one; L.Add two
L.delete
leaked=""
for suffix in items data class; do
    declare -p "L_$suffix" >/dev/null 2>&1 && leaked+="L_$suffix "
done
declare -F "L.Add" >/dev/null 2>&1 && leaked+="L.Add() "
[[ -z "$leaked" ]] && kt_test_pass "no L_* variable and no wrapper left" \
    || kt_test_fail "left behind: $leaked"

# --- 6. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. This runs the documented failure path and checks the caller
# still gets control — verified on 5.2.37 and 5.3.9.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
TList.new L; L.Get 5 || printf 'reached rc=%s' \0
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc="* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi
kt_test_log "020_Contract.sh completed"
