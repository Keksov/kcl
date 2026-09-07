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
UNIT="$UNIT_DIR/tpath.sh"
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
tpath.getFileName /a/b.txt >/dev/null
tpath.getExtension /a/b.txt >/dev/null
tpath.getDirectoryName /a/b.txt >/dev/null
tpath.combine /a b >/dev/null
tpath.changeExtension /a/b.txt .md >/dev/null'

expect_clean "a predicate under set -eu, called the documented way [1.3, D7]" '
if tpath.isPathRooted /a; then :; else :; fi
tpath.isPathRooted rel || :
! tpath.isPathRooted rel
tpath.hasExtension a.txt >/dev/null'

# --- 2. the return contract (D3) -------------------------------------------
kt_test_start "a direct call is silent and answers through RESULT [D3, 1.1]"
out_file="$TMP/direct.out"
: > "$out_file"
RESULT="__unset__"
tpath.getFileName /a/b.txt > "$out_file"
printed="$(<"$out_file")"
if [[ -z "$printed" && "$RESULT" == "b.txt" ]]; then
    kt_test_pass "RESULT=b.txt, nothing printed"
else
    kt_test_fail "printed='$printed' RESULT='$RESULT'"
fi

kt_test_start "\$( ) prints the value exactly once [D3, 1.1]"
got="$(tpath.getFileName /a/b.txt)"
if [[ "$got" == "b.txt" ]]; then
    kt_test_pass "b.txt"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "a value that looks like an echo option round-trips [X-ECHO]"
got="$(tpath.getFileName /a/-neE)"
RESULT="__unset__"
tpath.getFileName /a/-neE >/dev/null
if [[ "$got" == "-neE" && "$RESULT" == "-neE" ]]; then
    kt_test_pass "-neE both ways"
else
    kt_test_fail "captured='$got' RESULT='$RESULT'"
fi

# --- 3. the locale self-heal (D6) ------------------------------------------
kt_test_start "a bare environment gets a UTF-8 LC_CTYPE at load [D6, 1.6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
tpath.getFileName '/a/дом.txt' >/dev/null
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\${#RESULT}\"" 2>&1)"
if [[ "$out" == "C.UTF-8|7" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|7'"
fi

# --- 5. the error path reaches the caller under set -e (D7) ----------------
# Direct proof, instead of auditing the code for `&&` lists: bash exits only
# for the command following the FINAL && or ||, so a list in mid-body is safe;
# only a TRAILING list (the last statement of a function) turns a member into a
# script-killer. Since P3 tpath HAS a failing path (kcl/README.md 1.2), so the
# assertion every other suite carries lands here too.
kt_test_start "a failing member returns to the caller under set -e [D7, M7/T1]"
out="$(bash -c "set -e
source '$UNIT'
tpath.getAttributes /no/such/path >/dev/null 2>&1 || printf 'reached rc=%s' \$?
printf ' end'" 2>&1)"
if [[ "$out" == *"reached rc=1"* && "$out" == *"end"* ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "caller never regained control: '$out'"
fi
