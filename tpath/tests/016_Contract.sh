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

# --- 5. the error path under set -e (D7) -----------------------------------
# tpath has NO failing path today: every member answers rc 0, including empty
# and malformed input (review table X-CONTRACT). That is the unit's current
# contract, not an oversight of this test — decision D3 converts tpath to
# func + kk._return in P3 and gives it the rc-1 error contract, and the
# "a failing member returns to the caller" assertion every other suite carries
# lands here at the same time. Until then the `set -eu` main path above is the
# whole D7 story for this unit.
