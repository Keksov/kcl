#!/bin/bash
# 021_G3_ScanDateTime.sh — finding G3-08 (scanDateTime token rules).
#
# FPC reference: packages/rtl-objpas/src/inc/dateutil.inc, the nested
# `intscandate` of ScanDateTime.
#
#   * `lasttoken` (declared at :2496, initialised at :2499, assigned at :2640)
#     carries the PREVIOUS uppercased pattern character. The rule at :2505 is
#         if (lch='M') and (lasttoken='H') then <minutes>
#     so `mm` means MONTH everywhere except directly after an hour token — which
#     is why `yyyy-mm-dd hh:mm:ss` is the canonical FPC pattern and the port
#     rejected it outright.
#   * the time separator at :2615-2618 does `matchchar` and then `lch:=lasttoken`,
#     i.e. a `:` is TRANSPARENT: it does not become the previous token, so the
#     `M` in `hh:mm` still sees `H`.
#   * a run of more than two `m` after an hour is an error (:2507-2509,
#     Shhmmerror).
#   * `nn` is minutes unconditionally (:2528).
#
# Divergence from FPC, on purpose (plan P6): an UNTERMINATED quote in the
# pattern is rc 1 here. FPC walks off the end of the pattern and returns a
# value; the plan asks for a refusal, and a pattern that cannot be written down
# correctly is a malformed call, not data.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_ScanDateTime" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/dateutils.sh"

scans() {   # EXPECTED PATTERN INPUT
    local want="$1" pat="$2" inp="$3" got rc=0
    kt_test_start "scanDateTime '$pat' '$inp' -> $want"
    got="$(dateutils.scanDateTime "$pat" "$inp" 2>&1)" || rc=$?
    if [[ "$got" == "$want" && $rc -eq 0 ]]; then
        kt_test_pass "'$pat' '$inp' = $got"
    else
        kt_test_fail "'$pat' '$inp' gave '$got' rc=$rc, expected '$want'"
    fi
}

fails() {   # WHY PATTERN INPUT
    local why="$1" pat="$2" inp="$3" got rc=0
    kt_test_start "scanDateTime refuses '$pat' / '$inp' ($why)"
    got="$(dateutils.scanDateTime "$pat" "$inp" 2>&1)" || rc=$?
    if [[ $rc -eq 1 && -z "$got" ]]; then
        kt_test_pass "rc 1, no output"
    else
        kt_test_fail "gave '$got' rc=$rc, expected rc 1 and no output ($why)"
    fi
}

# ---------------------------------------------------------------------------
# 1. `M` after `H` is MINUTES [G3-08, dateutil.inc:2505]
# ---------------------------------------------------------------------------
scans 1301166930000 'yyyy-mm-dd hh:mm:ss' '2011-03-26 19:15:30'
scans 1301166930555 'yyyy-mm-dd hh:mm:ss.zzz' '2011-03-26 19:15:30.555'
scans 69300000      'hh:mm'          '19:15'
scans 69330000      'hh:mm:ss'       '19:15:30'
scans 69300000      'hhmm'           '1915'
# `nn` keeps working and means the same thing.
scans 69330000      'hh:nn:ss'       '19:15:30'
scans 1301166930000 'yyyy-mm-dd hh:nn:ss' '2011-03-26 19:15:30'

# ---------------------------------------------------------------------------
# 2. `mm` NOT after an hour is still the month
# ---------------------------------------------------------------------------
scans 1301097600000 'mm/dd/yyyy'     '03/26/2011'
scans 1301097600000 'dd-mm-yyyy'     '26-03-2011'
scans 1301097600000 'yyyymmdd'       '20110326'
# An hour earlier in the pattern must not leak past the next literal token.
scans 1301166900000 'hh:mm dd-mm-yyyy' '19:15 26-03-2011'

# ---------------------------------------------------------------------------
# 3. Malformed patterns
# ---------------------------------------------------------------------------
fails "more than two 'm' after an hour (Shhmmerror)" 'hh:mmm' '19:155'
fails "unterminated single quote" "hh'x"   '19x'
fails "unterminated double quote" 'hh"x'   '19x'
fails "input ends inside a token"  'yyyy-mm-dd' '2011-03'
fails "a literal that does not match" 'yyyy/mm/dd' '2011-03-26'
fails "no digits where a token expects them" 'yyyy' 'abcd'
fails "an impossible date still fails validation" 'yyyy-mm-dd' '2011-02-31'

# A CLOSED quote is fine, and the quoted text is matched verbatim.
scans 1301097600000 "yyyy'-'mm'-'dd" '2011-03-26'
scans 1301097600000 'yyyy"-"mm"-"dd' '2011-03-26'
# A quoted token letter is a literal, not a token.
scans 0              "'mm'"           'mm'

# ---------------------------------------------------------------------------
# 4. Trailing input is allowed (FPC's loop stops at the end of the PATTERN)
# ---------------------------------------------------------------------------
scans 1301097600000 'yyyy-mm-dd' '2011-03-26T19:15:30Z'

# ---------------------------------------------------------------------------
# 5. G3-04 — neither argument is ever evaluated
# ---------------------------------------------------------------------------
kt_test_start "scanDateTime does not evaluate its pattern or its input [G3-04]"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
canary="$TMP/pwn_021"
rm -f "$canary"
bad="x[\$(printf x > '$canary')]"
dateutils.scanDateTime "$bad" "1970"  >/dev/null 2>&1 || :
dateutils.scanDateTime "yyyy" "$bad"  >/dev/null 2>&1 || :
dateutils.scanDateTime "$bad" "$bad"  >/dev/null 2>&1 || :
dateutils.scanDateTime "zzz" "$bad"   >/dev/null 2>&1 || :
if [[ ! -e "$canary" ]]; then
    kt_test_pass "nothing executed"
else
    kt_test_fail "COMMAND EXECUTED"
fi

# ---------------------------------------------------------------------------
# 6. Two-digit years still pivot at 50
# ---------------------------------------------------------------------------
scans 1293840000000  'yy-mm-dd' '11-01-01'
scans 946684800000   'yy-mm-dd' '00-01-01'
scans 2493072000000  'yy-mm-dd' '49-01-01'
scans -631152000000  'yy-mm-dd' '50-01-01'
