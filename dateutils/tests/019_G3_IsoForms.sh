#!/bin/bash
# 019_G3_IsoForms.sh — findings G3-02 and G3-09 (ISO 8601 parsing).
#
# G3-02: `_parse_iso` only checked `d <= 31`, so `2011-02-31` was *accepted* and
#        `_join_kdt` rolled it over to 2011-03-03 with rc 0. Year 0000 too. FPC
#        routes every ISO parse through TryEncodeDate (dateutil.inc:2740-2761,
#        TryISOStrToDate), which rejects an impossible date and year < 1. The
#        port's date-only `tryISOStrToDate` was already correct, so the unit
#        answered two different ways for the same calendar question.
# G3-09: the compact FPC forms were rejected. Checked against
#        dateutil.inc:2763-2845 (TryISOStrToTime) and 2849-2874
#        (TryISOStrToDateTime) rather than against the review report — the
#        report lists `2011`, `20110326` and `T19:15` as FPC-valid *datetimes*
#        and they are not: TryISOStrToDateTime requires a date part of exactly
#        8 or 10 characters FOLLOWED by ' ' or 'T' at position 9 or 11.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_IsoForms" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/dateutils.sh"

# value(MEMBER ARGS...) -> "rc|output"
call() { local out rc=0; out="$(dateutils."$@" 2>&1)" || rc=$?; printf '%s|%s' "$rc" "$out"; }

accepts() {   # MEMBER ARG EXPECTED-VALUE
    local m="$1" arg="$2" want="$3" got
    kt_test_start "$m '$arg' -> $want"
    got="$(call "$m" "$arg")"
    if [[ "$got" == "0|$want" ]]; then
        kt_test_pass "$m '$arg' = $want"
    else
        kt_test_fail "$m '$arg' gave rc|out='$got', expected '0|$want'"
    fi
}

rejects() {   # MEMBER ARG WHY
    local m="$1" arg="$2" why="$3" got
    kt_test_start "$m rejects '$arg' ($why)"
    got="$(call "$m" "$arg")"
    if [[ "$got" == "1|" ]]; then
        kt_test_pass "$m '$arg' -> rc 1, no output"
    else
        kt_test_fail "$m '$arg' gave rc|out='$got', expected '1|' ($why)"
    fi
}

# ---------------------------------------------------------------------------
# 1. G3-02 — an impossible date is not a date, in EVERY entry point
# ---------------------------------------------------------------------------
for member in tryISO8601ToDate iso8601ToDate tryISOStrToDateTime; do
    rejects "$member" "2011-02-31T00:00:00" "Feb 31 does not exist"
    rejects "$member" "2011-02-30T12:00:00Z" "Feb 30 does not exist"
    rejects "$member" "2011-02-29T00:00:00" "2011 is not a leap year"
    rejects "$member" "2011-04-31T00:00:00" "April has 30 days"
    rejects "$member" "0000-01-01T00:00:00" "FPC TryEncodeDate requires year >= 1"
    rejects "$member" "2011-13-01T00:00:00" "month 13"
    rejects "$member" "2011-00-10T00:00:00" "month 0"
    rejects "$member" "2011-01-00T00:00:00" "day 0"
done

# The date-only forms go through the same validator.
rejects tryISO8601ToDate "2011-02-31" "date-only Feb 31"
rejects tryISO8601ToDate "0000-01-01" "date-only year 0"
rejects tryISOStrToDate  "20110231"   "date-only compact Feb 31"
rejects tryISOStrToDate  "0000-01-01" "date-only year 0"

# 2000 IS a leap year, 1900 is not — the validator must be the calendar, not a
# `d <= 31` shortcut.
accepts tryISO8601ToDate "2000-02-29T00:00:00Z" 951782400000
rejects tryISO8601ToDate "1900-02-29T00:00:00Z" "1900 is not a leap year"

# iso8601ToDateDef falls back to its default instead of failing (FPC).
kt_test_start "iso8601ToDateDef returns the default for an impossible date [G3-02]"
got="$(dateutils.iso8601ToDateDef "2011-02-31" 42)"
if [[ "$got" == "42" ]]; then
    kt_test_pass "default 42 returned"
else
    kt_test_fail "got '$got', expected the default 42"
fi

# ---------------------------------------------------------------------------
# 2. G3-09 — the compact FPC time forms (dateutil.inc:2763-2845)
# ---------------------------------------------------------------------------
# Lengths accepted by TryISOStrToTime after the zone is stripped: 2, 4, 5, 6,
# 8, 10, 12.
accepts tryISOStrToTime "19"           68400000
accepts tryISOStrToTime "1915"         69300000
accepts tryISOStrToTime "19:15"        69300000
accepts tryISOStrToTime "191530"       69330000
accepts tryISOStrToTime "19:15:30"     69330000
accepts tryISOStrToTime "191530.555"   69330555
accepts tryISOStrToTime "19:15:30.555" 69330555
# The zone is validated and then IGNORED (FPC discards xHour/xMinute of the
# offset before re-parsing the time part).
accepts tryISOStrToTime "19:15:30Z"      69330000
accepts tryISOStrToTime "19:15:30+03:00" 69330000
accepts tryISOStrToTime "19:15:30-0500"  69330000
accepts tryISOStrToTime "1915+03"        69300000
# Lengths FPC does not have.
rejects tryISOStrToTime "1"          "length 1 is not an FPC form"
rejects tryISOStrToTime "191"        "length 3 is not an FPC form"
rejects tryISOStrToTime "19:15:3"    "length 7 is not an FPC form"
rejects tryISOStrToTime "19-15"      "'-' is not a time separator"
rejects tryISOStrToTime "25"         "hour 25"
rejects tryISOStrToTime "1975"       "minute 75"
rejects tryISOStrToTime "19:15:61"   "second 61"

# ---------------------------------------------------------------------------
# 3. G3-09 — the compact datetime form (dateutil.inc:2849-2874)
# ---------------------------------------------------------------------------
# FPC splits at a fixed POSITION: aString[11] then aString[9] must be ' ' or
# 'T'. So YYYYMMDD + separator + time is valid, and a bare date or a bare time
# is NOT a datetime.
accepts tryISOStrToDateTime "20110326T19:15"    1301166900000
accepts tryISOStrToDateTime "20110326 19:15"    1301166900000
accepts tryISOStrToDateTime "20110326T191530"   1301166930000
accepts tryISOStrToDateTime "20110326T19"       1301166000000
accepts tryISOStrToDateTime "2011-03-26T19:15"  1301166900000
accepts tryISOStrToDateTime "2011-03-26 19:15:30.555" 1301166930555
rejects tryISOStrToDateTime "2011"       "FPC: a bare year is not a datetime"
rejects tryISOStrToDateTime "20110326"   "FPC: a bare date is not a datetime"
rejects tryISOStrToDateTime "T19:15"     "FPC: a bare time is not a datetime"
rejects tryISOStrToDateTime "20110326X19:15" "the separator must be ' ' or 'T'"

# tryISO8601ToDate reaches the same forms (it strips the zone and delegates).
accepts tryISO8601ToDate "20110326T19:15:30Z"      1301166930000
accepts tryISO8601ToDate "20110326T19:15:30+03:00" 1301156130000
accepts tryISO8601ToDate "2011-03-26T19:15:30Z"    1301166930000

# ---------------------------------------------------------------------------
# 4. The port's documented EXTENSION over FPC: a date-only ISO 8601 string
# ---------------------------------------------------------------------------
# FPC's TryISO8601ToDate mis-splits `2011-03-26` (it reads the trailing `-26`
# as a timezone) and returns False. The port accepts date-only input, because
# the zone is only stripped from a string that actually has a time part. This
# is a deliberate superset, pinned here so it cannot be lost by accident.
accepts tryISO8601ToDate "2011-03-26" 1301097600000
accepts tryISOStrToDate  "2011-03-26" 1301097600000
accepts tryISOStrToDate  "20110326"   1301097600000
accepts tryISOStrToDate  "2011"       1293840000000
accepts tryISOStrToDate  "201103"     1298937600000
accepts tryISOStrToDate  "2011-03"    1298937600000
