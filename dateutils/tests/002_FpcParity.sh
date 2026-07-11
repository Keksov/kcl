#!/bin/bash
# FPC-parity fixture set — ported 1:1 from Free Pascal's own DateUtils tests.
# Primary seed: FPC tests/webtbs/tw16040.pp (17 assertions).
#
# This file is built up INCREMENTALLY: each implementation phase appends the
# tw16040 assertions whose functions land in that phase, with the FPC values
# kept VERBATIM (translated to KDT), never "improved". Mapping (see PLAN.md /
# dateutils_ledger.json test_basis):
#
#   P1  EncodeDateTime anchors 2010-03-22, 2010-03-23, 2011-03-26 19:15:30.555;
#       EncodeDate(2011,1,1); IsInLeapYear(2011)=false
#   P2  YearOf/MonthOf/DayOf/HourOf(+TheDay)/MinuteOf(+TheHour)/SecondOf
#       (+TheMinute)/MilliSecondOf(+TheSecond) on 2011-03-26 19:15:30.555; IsPM
#   P3  StartOfTheYear -> 2011-01-01; EndOfTheYear -> 2011-12-31 23:59:59.999
#   P6  JulianDateToDateTime(2455277.5)=2010-03-22; DateTimeToJulianDate
#       roundtrip; MJD roundtrip; tunitdt1 far-future Unix fixtures
#   P7  scanDateTime 'YYYY.MM.DD HH:NN:SS:ZZZ' '2011.03.29 16:46:56:777'
#
# The file is COMPLETE when P7 delivers scanDateTime.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "FpcParity" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- P0: scaffolding present (no tw16040 functions land in P0) ---------------
kt_test_start "parity scaffolding present (dateutils class loaded)"
if [[ "$(dateutils.msPerDay)" == "86400000" ]]; then
    kt_test_pass "parity scaffolding present (dateutils class loaded)"
else
    kt_test_fail "dateutils did not load"
fi

# --- P1: EncodeDateTime/EncodeDate anchors + IsInLeapYear (tw16040) ----------
# tw16040 setup: date1:=EncodeDateTime(2010,03,22,0,0,0,0);
#                date2:=EncodeDateTime(2010,03,23,0,0,0,0);
# their JD equalities are asserted in P6; here we pin anchor integrity so the
# P6 comparison rests on verified encodings.
kt_test_start "P1/tw16040: EncodeDateTime(2010-03-22) anchor decodes correctly"
d1=$(dateutils.encodeDateTime 2010 3 22 0 0 0 0)
if [[ "$(dateutils.decodeDateTime "$d1")" == "2010 3 22 0 0 0 0" ]]; then
    kt_test_pass "P1/tw16040: EncodeDateTime(2010-03-22) anchor decodes correctly"
else
    kt_test_fail "d1 decode = [$(dateutils.decodeDateTime "$d1")]"
fi

kt_test_start "P1/tw16040: 2010-03-23 is exactly one day after 2010-03-22 (JD 2455277.5 -> 2455278.5)"
d2=$(dateutils.encodeDateTime 2010 3 23 0 0 0 0)
if (( d2 - d1 == 86400000 )); then
    kt_test_pass "P1/tw16040: 2010-03-23 is exactly one day after 2010-03-22 (JD 2455277.5 -> 2455278.5)"
else
    kt_test_fail "d2 - d1 = $(( d2 - d1 )), want 86400000"
fi

kt_test_start "P1/tw16040: EncodeDateTime(2011,03,26,19,15,30,555) anchor decodes correctly"
d3=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
if [[ "$(dateutils.decodeDateTime "$d3")" == "2011 3 26 19 15 30 555" ]]; then
    kt_test_pass "P1/tw16040: EncodeDateTime(2011,03,26,19,15,30,555) anchor decodes correctly"
else
    kt_test_fail "d3 decode = [$(dateutils.decodeDateTime "$d3")]"
fi

kt_test_start "P1/tw16040: EncodeDate(2011,1,1) == EncodeDateTime(2011,1,1,0,0,0,0)"
if [[ "$(dateutils.encodeDate 2011 1 1)" == "$(dateutils.encodeDateTime 2011 1 1 0 0 0 0)" \
   && "$(dateutils.decodeDate "$(dateutils.encodeDate 2011 1 1)")" == "2011 1 1" ]]; then
    kt_test_pass "P1/tw16040: EncodeDate(2011,1,1) == EncodeDateTime(2011,1,1,0,0,0,0)"
else
    kt_test_fail "EncodeDate(2011,1,1) mismatch"
fi

kt_test_start "P1/tw16040: not IsInLeapYear(2011-03-26 19:15:30.555)"
if [[ "$(dateutils.isInLeapYear "$d3")" == false ]]; then
    kt_test_pass "P1/tw16040: not IsInLeapYear(2011-03-26 19:15:30.555)"
else
    kt_test_fail "IsInLeapYear(date1) = $(dateutils.isInLeapYear "$d3"), want false"
fi

# --- P2: full extraction set on 2011-03-26 19:15:30.555 (tw16040) ------------
# tw16040 lines 62-96: YearOf/MonthOf/DayOf, HourOf(+HourOfTheDay),
# MinuteOf(+MinuteOfTheHour), SecondOf(+SecondOfTheMinute),
# MilliSecondOf(+MilliSecondOfTheSecond); plus IsPM (line 57).
kt_test_start "P2/tw16040: extraction set on 2011-03-26 19:15:30.555"
D=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
fails=""
[[ "$(dateutils.yearOf $D)"  == 2011 ]] || fails+="YearOf "
[[ "$(dateutils.monthOf $D)" == 3    ]] || fails+="MonthOf "
[[ "$(dateutils.dayOf $D)"   == 26   ]] || fails+="DayOf "
[[ "$(dateutils.hourOf $D)"   == 19 && "$(dateutils.hourOfTheDay $D)"          == 19  ]] || fails+="HourOf "
[[ "$(dateutils.minuteOf $D)" == 15 && "$(dateutils.minuteOfTheHour $D)"       == 15  ]] || fails+="MinuteOf "
[[ "$(dateutils.secondOf $D)" == 30 && "$(dateutils.secondOfTheMinute $D)"     == 30  ]] || fails+="SecondOf "
[[ "$(dateutils.milliSecondOf $D)" == 555 && "$(dateutils.milliSecondOfTheSecond $D)" == 555 ]] || fails+="MilliSecondOf "
if [[ -z "$fails" ]]; then
    kt_test_pass "P2/tw16040: extraction set on 2011-03-26 19:15:30.555"
else
    kt_test_fail "P2 extraction fails: $fails"
fi

kt_test_start "P2/tw16040: IsPM(2011-03-26 19:15:30.555) is true"
if [[ "$(dateutils.isPM "$D")" == true ]]; then
    kt_test_pass "P2/tw16040: IsPM(2011-03-26 19:15:30.555) is true"
else
    kt_test_fail "IsPM = $(dateutils.isPM "$D"), want true"
fi

# --- P3: StartOfTheYear / EndOfTheYear (tw16040 lines 97-106) ----------------
# tw16040: StartOfTheYear(date1) = EncodeDate(2011,1,1);
#          EndOfTheYear(date1)   = EncodeDateTime(2011,12,31,23,59,59,999);
kt_test_start "P3/tw16040: StartOfTheYear(2011-03-26 ...) == EncodeDate(2011,1,1)"
D3=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
if [[ "$(dateutils.startOfTheYear "$D3")" == "$(dateutils.encodeDate 2011 1 1)" ]]; then
    kt_test_pass "P3/tw16040: StartOfTheYear(2011-03-26 ...) == EncodeDate(2011,1,1)"
else
    kt_test_fail "StartOfTheYear mismatch"
fi

kt_test_start "P3/tw16040: EndOfTheYear(2011-03-26 ...) == EncodeDateTime(2011,12,31,23,59,59,999)"
if [[ "$(dateutils.endOfTheYear "$D3")" == "$(dateutils.encodeDateTime 2011 12 31 23 59 59 999)" ]]; then
    kt_test_pass "P3/tw16040: EndOfTheYear(2011-03-26 ...) == EncodeDateTime(2011,12,31,23,59,59,999)"
else
    kt_test_fail "EndOfTheYear mismatch"
fi

# --- P6: Julian/MJD (tw16040) + far-future Unix (tunitdt1) -------------------
# tw16040: date1:=EncodeDateTime(2010,3,22,0,0,0,0); date2:=JulianDateToDateTime(2455277.5);
#          date1=date2; DateTimeToJulianDate(date2)=2455277.5; MJD roundtrip; same for 2010-03-23.
kt_test_start "P6/tw16040: JulianDateToDateTime(2455277.5) == EncodeDateTime(2010,3,22,...)"
if [[ "$(dateutils.julianDateToDateTime 2455277.5)" == "$(dateutils.encodeDateTime 2010 3 22 0 0 0 0)" ]] \
   && [[ "$(dateutils.julianDateToDateTime 2455278.5)" == "$(dateutils.encodeDateTime 2010 3 23 0 0 0 0)" ]]; then
    kt_test_pass "P6/tw16040: JulianDateToDateTime(2455277.5) == EncodeDateTime(2010,3,22,...)"
else
    kt_test_fail "JulianDateToDateTime anchors mismatch"
fi

kt_test_start "P6/tw16040: DateTimeToJulianDate round-trips 2455277.5 / 2455278.5"
if [[ "$(dateutils.dateTimeToJulianDate "$(dateutils.encodeDateTime 2010 3 22 0 0 0 0)")" == "2455277.500000" ]] \
   && [[ "$(dateutils.dateTimeToJulianDate "$(dateutils.encodeDateTime 2010 3 23 0 0 0 0)")" == "2455278.500000" ]]; then
    kt_test_pass "P6/tw16040: DateTimeToJulianDate round-trips 2455277.5 / 2455278.5"
else
    kt_test_fail "DateTimeToJulianDate mismatch"
fi

kt_test_start "P6/tw16040: ModifiedJulianDate round-trips 2010-03-22 and 2010-03-23"
ok=1
for D in "$(dateutils.encodeDateTime 2010 3 22 0 0 0 0)" "$(dateutils.encodeDateTime 2010 3 23 0 0 0 0)"; do
    j=$(dateutils.dateTimeToModifiedJulianDate "$D")
    [[ "$(dateutils.modifiedJulianDateToDateTime "$j")" == "$D" ]] || ok=0
done
(( ok )) && kt_test_pass "P6/tw16040: ModifiedJulianDate round-trips 2010-03-22 and 2010-03-23" \
         || kt_test_fail "MJD roundtrip mismatch"

# tunitdt1: UnixToDateTime(15796372693) -> 2470-07-26 09:18:13; and a far-future
# encode -> unix -> decode roundtrip for 2345-12-12 04:45:49.
kt_test_start "P6/tunitdt1: UnixToDateTime(15796372693) == 2470-07-26 09:18:13"
if [[ "$(dateutils.unixToDateTime 15796372693)" == "$(dateutils.encodeDateTime 2470 7 26 9 18 13 0)" ]]; then
    kt_test_pass "P6/tunitdt1: UnixToDateTime(15796372693) == 2470-07-26 09:18:13"
else
    kt_test_fail "far-future UnixToDateTime mismatch"
fi

kt_test_start "P6/tunitdt1: encode(2345-12-12 04:45:49) -> unix -> decode round-trips"
e=$(dateutils.encodeDateTime 2345 12 12 4 45 49 0)
if [[ "$(dateutils.unixToDateTime "$(dateutils.dateTimeToUnix "$e")")" == "$e" ]]; then
    kt_test_pass "P6/tunitdt1: encode(2345-12-12 04:45:49) -> unix -> decode round-trips"
else
    kt_test_fail "far-future Unix roundtrip mismatch"
fi

# --- P7: scanDateTime (tw16040, final assertion) -----------------------------
# tw16040 line 107: scandatetime('YYYY.MM.DD HH:NN:SS:ZZZ','2011.03.29 16:46:56:777')
#                   = EncodeDateTime(2011,03,29,16,46,56,777).  Completes the file.
kt_test_start "P7/tw16040: scanDateTime('YYYY.MM.DD HH:NN:SS:ZZZ', '2011.03.29 16:46:56:777')"
if [[ "$(dateutils.scanDateTime 'YYYY.MM.DD HH:NN:SS:ZZZ' '2011.03.29 16:46:56:777')" \
   == "$(dateutils.encodeDateTime 2011 3 29 16 46 56 777)" ]]; then
    kt_test_pass "P7/tw16040: scanDateTime('YYYY.MM.DD HH:NN:SS:ZZZ', '2011.03.29 16:46:56:777')"
else
    kt_test_fail "scanDateTime tw16040 mismatch"
fi

# ============================================================================
# tw16040 parity COMPLETE: all 17 source assertions are now represented above
# (Julian/MJD x4, IsInLeapYear, IsPM, YearOf..MilliSecondOf + OfThe twins,
# StartOfTheYear/EndOfTheYear, and this scanDateTime). See PLAN.md test_basis.
# ============================================================================
