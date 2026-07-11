#!/bin/bash
# P5.2 — week-date and day-of-week-in-month encodings (own-design).
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "WeekDayEncodings" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }

# --- decodeDateWeek ISO fixtures (year, week, dow) --------------------------
kt_test_start "decodeDateWeek matches ISO week-date fixtures"
ok=true
[[ "$(dateutils.decodeDateWeek "$(dateutils.encodeDate 2011 3 26)")" == "2011 12 6" ]] || ok=false
[[ "$(dateutils.decodeDateWeek "$(dateutils.encodeDate 2004 1 1)")"  == "2004 1 4"  ]] || ok=false   # Thu W01/2004
[[ "$(dateutils.decodeDateWeek "$(dateutils.encodeDate 2005 1 1)")"  == "2004 53 6" ]] || ok=false   # Sat W53/2004
[[ "$(dateutils.decodeDateWeek "$(dateutils.encodeDate 2008 12 29)")" == "2009 1 1" ]] || ok=false   # Mon W01/2009
[[ "$(dateutils.decodeDateWeek "$(dateutils.encodeDate 2010 1 3)")"  == "2009 53 7" ]] || ok=false   # Sun W53/2009
$ok && kt_test_pass "decodeDateWeek matches ISO week-date fixtures" \
     || kt_test_fail "decodeDateWeek wrong"

# --- encodeDateWeek: fixtures, default dow, roundtrip, invalid ---------------
kt_test_start "encodeDateWeek: ISO fixtures + default dow=1 + reject invalid week"
ok=true
[[ "$(fmt "$(dateutils.encodeDateWeek 2009 1 1)")" == "2008-12-29 00:00:00.000" ]] || ok=false
[[ "$(dateutils.encodeDateWeek 2009 1)" == "$(dateutils.encodeDateWeek 2009 1 1)" ]] || ok=false   # default dow=1
dateutils.encodeDateWeek 2005 53 1 2>/dev/null && ok=false     # 2005 has 52 weeks
dateutils.tryEncodeDateWeek 2011 0 1 2>/dev/null && ok=false   # week 0
$ok && kt_test_pass "encodeDateWeek: ISO fixtures + default dow=1 + reject invalid week" \
     || kt_test_fail "encodeDateWeek wrong"

kt_test_start "encodeDateWeek(decodeDateWeek(dt)) == dateOf(dt) across the ISO boundaries"
ok=true
for spec in "2011 3 26" "2004 1 1" "2005 1 1" "2008 12 29" "2010 1 3" "2009 12 31" "2016 2 29"; do
    read -r y m d <<< "$spec"
    dt=$(dateutils.encodeDateTime $y $m $d 13 30 0 0)
    read -r wy ww wd <<< "$(dateutils.decodeDateWeek $dt)"
    back=$(dateutils.encodeDateWeek $wy $ww $wd)
    [[ "$back" == "$(dateutils.dateOf $dt)" ]] || { ok=false; echo "  $spec -> W$wy/$ww/$wd -> $(fmt "$back")" >&2; break; }
done
$ok && kt_test_pass "encodeDateWeek(decodeDateWeek(dt)) == dateOf(dt) across the ISO boundaries" \
     || kt_test_fail "encodeDateWeek/decodeDateWeek roundtrip broke"

# --- month-week encodings ---------------------------------------------------
kt_test_start "decodeDateMonthWeek + encodeDateMonthWeek anchors"
ok=true
[[ "$(dateutils.decodeDateMonthWeek "$(dateutils.encodeDate 2011 3 26)")" == "2011 3 4 6" ]] || ok=false
[[ "$(dateutils.decodeDateMonthWeek "$(dateutils.encodeDate 2011 3 1)")"  == "2011 3 1 2" ]] || ok=false
[[ "$(fmt "$(dateutils.encodeDateMonthWeek 2011 3 4 6)")" == "2011-03-26 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.encodeDateMonthWeek 2011 3 1 2)")" == "2011-03-01 00:00:00.000" ]] || ok=false
dateutils.tryEncodeDateMonthWeek 2011 13 1 1 2>/dev/null && ok=false   # month 13 invalid
$ok && kt_test_pass "decodeDateMonthWeek + encodeDateMonthWeek anchors" \
     || kt_test_fail "month-week encodings wrong"

# --- day-of-week-in-month ---------------------------------------------------
# FPC ANthDayOfWeek is Word (>=1) -> there is NO negative/"last" form; the 5th
# occurrence simply fails when the month has only 4 (see TEST_COVERAGE_NOTES.md).
kt_test_start "encodeDayOfWeekInMonth: nth weekday anchors + 5th-when-only-4 fails"
ok=true
[[ "$(fmt "$(dateutils.encodeDayOfWeekInMonth 2011 3 4 6)")" == "2011-03-26 00:00:00.000" ]] || ok=false  # 4th Sat
[[ "$(fmt "$(dateutils.encodeDayOfWeekInMonth 2011 3 1 6)")" == "2011-03-05 00:00:00.000" ]] || ok=false  # 1st Sat
[[ "$(fmt "$(dateutils.encodeDayOfWeekInMonth 2011 3 1 2)")" == "2011-03-01 00:00:00.000" ]] || ok=false  # 1st Tue (the 1st)
[[ "$(fmt "$(dateutils.encodeDayOfWeekInMonth 2011 3 5 4)")" == "2011-03-31 00:00:00.000" ]] || ok=false  # 5th Thu exists
dateutils.encodeDayOfWeekInMonth 2011 3 5 6 2>/dev/null && ok=false   # no 5th Saturday in Mar 2011
dateutils.tryEncodeDayOfWeekInMonth 2011 2 5 1 2>/dev/null && ok=false # no 5th Monday in Feb 2011
$ok && kt_test_pass "encodeDayOfWeekInMonth: nth weekday anchors + 5th-when-only-4 fails" \
     || kt_test_fail "encodeDayOfWeekInMonth wrong"
