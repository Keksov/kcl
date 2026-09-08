#!/bin/bash
# 020_G3_JulianAndRanges.sh — findings G3-03, G3-06, G3-07, G3-10.
#
# G3-03 `_span_fixed` divided a NEGATIVE numerator and then printed whole and
#       fraction separately, so every date before the MJD epoch came out as
#       `0.-500000` / `-21503.-750000` — malformed, and un-parseable by the
#       inverse member.
# G3-07 `_jd_str_to_ms` rejects a malformed JD string (P1), but the four
#       `*JulianDateToDateTime` members ignored its exit status: REPLY was left
#       at 0 and `modifiedJulianDateToDateTime ''` answered the MJD epoch, rc 0.
# G3-06 `tryEncodeTimeInterval` is `TryEncodeTimeInterval(Hour, Min, Sec,
#       MSec: word)` in FPC (dateutil.inc:1899) — the fields are unsigned and
#       the test is `(Min<60) and (Sec<60) and (MSec<1000)`. The port accepted
#       negatives and, on the strength of a wrong comment, MSec = 1000.
# G3-10 IncYear/IncMonth end in EncodeDate(Y,M,D) (dateutil.inc:1561-1571 and
#       SysUtils.IncMonth), which raises when the year leaves 1..9999; and
#       EncodeDateTime goes through SysUtils.TryEncodeTime, whose rule is
#       `Hour < 24` — so hour 24 is valid for IsValidTime and invalid for
#       EncodeTime, an asymmetry that lives in FPC itself.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_JulianAndRanges" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/dateutils.sh"

value_is() {   # EXPECTED MEMBER ARGS...
    local want="$1"; shift
    kt_test_start "dateutils.$1 ${*:2} -> $want"
    local got rc=0
    got="$(dateutils."$@" 2>&1)" || rc=$?
    if [[ "$got" == "$want" && $rc -eq 0 ]]; then
        kt_test_pass "$1 -> $got"
    else
        kt_test_fail "$1 ${*:2} gave '$got' rc=$rc, expected '$want' rc=0"
    fi
}

bool_is() {   # true|false MEMBER ARGS...   (R8: the word AND the exit status)
    local want="$1"; shift
    kt_test_start "dateutils.$1 ${*:2} -> $want (word and rc, R8)"
    local got rc=0 wantrc=1
    [[ "$want" == true ]] && wantrc=0
    got="$(dateutils."$@" 2>&1)" || rc=$?
    if [[ "$got" == "$want" && $rc -eq $wantrc ]]; then
        kt_test_pass "$1 -> $got (rc $rc)"
    else
        kt_test_fail "$1 ${*:2} gave '$got' rc=$rc, expected '$want' rc=$wantrc"
    fi
}

refused() {   # WHY MEMBER ARGS...
    local why="$1"; shift
    kt_test_start "dateutils.$1 ${*:2} is refused ($why)"
    local got rc=0
    got="$(dateutils."$@" 2>&1)" || rc=$?
    if [[ $rc -eq 1 && -z "$got" ]]; then
        kt_test_pass "$1 -> rc 1, no output"
    else
        kt_test_fail "$1 ${*:2} gave '$got' rc=$rc, expected rc 1 and no output ($why)"
    fi
}

# ---------------------------------------------------------------------------
# 1. G3-03 — a negative Julian / Modified Julian date is well formed
# ---------------------------------------------------------------------------
MJD_MINUS_HALF=-3506760000000        # 1858-11-16 12:00, i.e. MJD -0.5
MJD_MINUS_21503_75=-5364640800000    # 1800-01-01 06:00, i.e. MJD -21503.75

value_is "-0.500000"      dateTimeToModifiedJulianDate "$MJD_MINUS_HALF"
value_is "-21503.750000"  dateTimeToModifiedJulianDate "$MJD_MINUS_21503_75"
value_is "-1.000000"      dateTimeToModifiedJulianDate -3506803200000
value_is "0.000000"       dateTimeToModifiedJulianDate -3506716800000
value_is "0.500000"       dateTimeToModifiedJulianDate -3506673600000

kt_test_start "a negative MJD round-trips through the inverse member [G3-03]"
ok=true
for kdt in "$MJD_MINUS_HALF" "$MJD_MINUS_21503_75" -3506803200000 -3506716800000; do
    s="$(dateutils.dateTimeToModifiedJulianDate "$kdt")"
    back="$(dateutils.modifiedJulianDateToDateTime "$s")" || { ok=false; break; }
    [[ "$back" == "$kdt" ]] || { ok=false; break; }
done
if $ok; then
    kt_test_pass "four pre-epoch MJD values survive the round trip"
else
    kt_test_fail "MJD round trip broke at kdt=$kdt (string '$s', back '$back')"
fi

# The Julian date of year 1 is positive, but the same formatting path is used —
# a plain regression pin so the sign fix cannot break the common case.
value_is "1721425.500000" dateTimeToJulianDate -62135596800000
value_is "2455647.302083" dateTimeToJulianDate 1301166900000

kt_test_start "a Julian date round-trips for both signs [G3-03]"
ok=true
for kdt in -62135596800000 1301166900000 "$MJD_MINUS_21503_75" 0; do
    s="$(dateutils.dateTimeToJulianDate "$kdt")"
    back="$(dateutils.julianDateToDateTime "$s")" || { ok=false; break; }
    # A 6-decimal Julian date resolves 10^-6 day = 86.4 ms, so the round trip is
    # exact only for values that land on a micro-day boundary; the bound is the
    # documented resolution, not a fudge factor.
    (( back >= kdt - 87 && back <= kdt + 87 )) || { ok=false; break; }
done
if $ok; then
    kt_test_pass "four JD values survive the round trip within one micro-day (86.4 ms)"
else
    kt_test_fail "JD round trip broke at kdt=$kdt (string '$s', back '$back')"
fi

# ---------------------------------------------------------------------------
# 2. G3-07 — a malformed JD string is rc 1, not the epoch
# ---------------------------------------------------------------------------
for member in julianDateToDateTime tryJulianDateToDateTime \
              modifiedJulianDateToDateTime tryModifiedJulianDateToDateTime; do
    refused "empty string"      "$member" ""
    refused "not a number"      "$member" "abc"
    refused "two decimal points" "$member" "1.2.3"
    refused "trailing garbage"  "$member" "2455647.5x"
    refused "arithmetic injection" "$member" 'x[$(printf x > /dev/null)]'
done

# ... and a well-formed one still works. 2455647.302083 is 2011-03-26 19:15:00
# rounded to the 6th decimal, i.e. 29 ms early — the string's own resolution.
value_is 1301166899971 tryJulianDateToDateTime "2455647.302083"
value_is 1301166899971 julianDateToDateTime "2455647.302083"
# A value that IS a whole micro-day round-trips exactly.
value_is 1301097600000 tryJulianDateToDateTime "2455646.500000"

# ---------------------------------------------------------------------------
# 3. G3-06 — interval fields are FPC `word`s
# ---------------------------------------------------------------------------
value_is 108900000 encodeTimeInterval 30 15 0 0        # hours may exceed 24
value_is 360000000 encodeTimeInterval 100 0 0 0
value_is 3599999   tryEncodeTimeInterval 0 59 59 999
refused "FPC: MSec < 1000"        tryEncodeTimeInterval 0 0 0 1000
refused "FPC: Min < 60"           tryEncodeTimeInterval 5 60 0 0
refused "FPC: Sec < 60"           tryEncodeTimeInterval 5 0 60 0
refused "negative hour is not a word"        tryEncodeTimeInterval -5 0 0 0
refused "negative minute is not a word"      tryEncodeTimeInterval 0 -5 0 0
refused "negative second is not a word"      tryEncodeTimeInterval 0 0 -5 0
refused "negative millisecond is not a word" tryEncodeTimeInterval 0 0 0 -5
refused "negative hour is not a word"        encodeTimeInterval -5 0 0 0

# ---------------------------------------------------------------------------
# 4. G3-10 — a result outside year 1..9999 is refused
# ---------------------------------------------------------------------------
Y9999_JUN=253383811200000     # 9999-06-01 00:00
Y0001_JAN31=-62133004800000   # 0001-01-31 00:00

kt_test_start "the two range fixtures really are 9999-06-01 and 0001-01-31"
a="$(dateutils.decodeDate $Y9999_JUN)"; b="$(dateutils.decodeDate $Y0001_JAN31)"
if [[ "$a" == "9999 6 1" && "$b" == "1 1 31" ]]; then
    kt_test_pass "$a / $b"
else
    kt_test_fail "fixtures wrong: '$a' '$b'"
fi

refused "year would become 10000" incYear "$Y9999_JUN" 1
refused "year would become 0"     incMonth "$Y0001_JAN31" -1
refused "year would become 0"     incYear "$Y0001_JAN31" -1
value_is 253383811200000 incYear "$Y9999_JUN" 0
value_is 253386403200000 incMonth "$Y9999_JUN" 1
refused "year would become 10000" incMonth "$Y9999_JUN" 7

# FPC's SysUtils.TryEncodeTime is `Hour < 24`, so hour 24 cannot be encoded...
refused "FPC TryEncodeTime requires Hour < 24" encodeTime 24 0 0 0
refused "FPC TryEncodeTime requires Hour < 24" tryEncodeTime 24 0 0 0
refused "FPC TryEncodeTime requires Hour < 24" encodeDateTime 2011 3 26 24 0 0 0
refused "FPC TryEncodeTime requires Hour < 24" tryEncodeDateTime 9999 12 31 24 0 0 0
# ... while DateUtils.IsValidTime (dateutil.inc:535) explicitly allows the
# whole-day marker. The asymmetry belongs to FPC; both halves are pinned.
bool_is true  isValidTime 24 0 0 0
bool_is true  isValidDateTime 2011 3 26 24 0 0 0
bool_is false isValidTime 24 0 0 1
bool_is false isValidTime 24 1 0 0
value_is 86399999 encodeTime 23 59 59 999
