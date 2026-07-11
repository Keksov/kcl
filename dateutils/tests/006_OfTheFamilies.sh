#!/bin/bash
# P2.2 — OfThe* families + nthDayOfWeek/decodeDayOfWeekInMonth (own-design).
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "OfTheFamilies" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- cross-consistency: nested OfThe* reconstruct the same quantities --------
kt_test_start "OfThe* families are internally consistent across sample datetimes"
ok=true; why=""
for spec in "2011 3 26 19 15 30 555" "2020 1 1 0 0 0 0" "1999 12 31 23 59 59 999" "2011 3 21 8 5 1 7"; do
    read -r y mo d h mi s ms <<< "$spec"
    k=$(dateutils.encodeDateTime $y $mo $d $h $mi $s $ms)
    dow=$(dateutils.dayOfTheWeek $k); doy=$(dateutils.dayOfTheYear $k)
    # same-unit aliases
    [[ "$(dateutils.hourOfTheDay $k)" == "$h" && "$(dateutils.minuteOfTheHour $k)" == "$mi" \
       && "$(dateutils.secondOfTheMinute $k)" == "$s" && "$(dateutils.milliSecondOfTheSecond $k)" == "$ms" ]] \
       || { ok=false; why="alias $spec"; break; }
    # of-the-day
    (( $(dateutils.minuteOfTheDay $k) == h*60+mi )) || { ok=false; why="minOfDay $spec"; break; }
    (( $(dateutils.secondOfTheDay $k) == (h*60+mi)*60+s )) || { ok=false; why="secOfDay $spec"; break; }
    (( $(dateutils.milliSecondOfTheDay $k) == ((h*60+mi)*60+s)*1000+ms )) || { ok=false; why="msOfDay $spec"; break; }
    # of-the-hour / of-the-minute
    (( $(dateutils.secondOfTheHour $k) == mi*60+s )) || { ok=false; why="secOfHour $spec"; break; }
    (( $(dateutils.milliSecondOfTheHour $k) == (mi*60+s)*1000+ms )) || { ok=false; why="msOfHour $spec"; break; }
    (( $(dateutils.milliSecondOfTheMinute $k) == s*1000+ms )) || { ok=false; why="msOfMin $spec"; break; }
    # of-the-week (Monday-based)
    (( $(dateutils.hourOfTheWeek $k) == (dow-1)*24+h )) || { ok=false; why="hrOfWeek $spec"; break; }
    (( $(dateutils.minuteOfTheWeek $k) == ((dow-1)*24+h)*60+mi )) || { ok=false; why="minOfWeek $spec"; break; }
    (( $(dateutils.milliSecondOfTheWeek $k) == ((((dow-1)*24+h)*60+mi)*60+s)*1000+ms )) || { ok=false; why="msOfWeek $spec"; break; }
    # of-the-month
    (( $(dateutils.hourOfTheMonth $k) == (d-1)*24+h )) || { ok=false; why="hrOfMonth $spec"; break; }
    (( $(dateutils.milliSecondOfTheMonth $k) == ((((d-1)*24+h)*60+mi)*60+s)*1000+ms )) || { ok=false; why="msOfMonth $spec"; break; }
    # of-the-year
    (( $(dateutils.hourOfTheYear $k) == h+(doy-1)*24 )) || { ok=false; why="hrOfYear $spec"; break; }
    (( $(dateutils.milliSecondOfTheYear $k) == ((mi+(h+(doy-1)*24)*60)*60+s)*1000+ms )) || { ok=false; why="msOfYear $spec"; break; }
done
$ok && kt_test_pass "OfThe* families are internally consistent across sample datetimes" \
     || kt_test_fail "OfThe* inconsistency: $why"

# --- period starts are zero -------------------------------------------------
kt_test_start "at the start of day/month/year/week every OfThe* is 0"
ok=true
soy=$(dateutils.encodeDateTime 2011 1 1 0 0 0 0)     # start of year (also month, day)
(( $(dateutils.milliSecondOfTheYear $soy) == 0 && $(dateutils.hourOfTheYear $soy) == 0 )) || ok=false
(( $(dateutils.milliSecondOfTheMonth $soy) == 0 )) || ok=false
(( $(dateutils.milliSecondOfTheDay $soy) == 0 )) || ok=false
mon=$(dateutils.encodeDateTime 2011 3 21 0 0 0 0)    # a Monday, 00:00
(( $(dateutils.milliSecondOfTheWeek $mon) == 0 && $(dateutils.hourOfTheWeek $mon) == 0 )) || ok=false
$ok && kt_test_pass "at the start of day/month/year/week every OfThe* is 0" \
     || kt_test_fail "period-start zero contract failed"

# --- period ends saturate ---------------------------------------------------
kt_test_start "end-of-week Sunday 23:59:59.999 -> milliSecondOfTheWeek = 604799999"
sun=$(dateutils.encodeDateTime 2011 3 27 23 59 59 999)   # Sunday (dow 7)
if (( $(dateutils.milliSecondOfTheWeek $sun) == 604799999 && $(dateutils.hourOfTheWeek $sun) == 6*24+23 )); then
    kt_test_pass "end-of-week Sunday 23:59:59.999 -> milliSecondOfTheWeek = 604799999"
else
    kt_test_fail "milliSecondOfTheWeek(Sun 23:59:59.999) = $(dateutils.milliSecondOfTheWeek $sun)"
fi

# --- nthDayOfWeek / decodeDayOfWeekInMonth ----------------------------------
kt_test_start "nthDayOfWeek: (day-of-month-1) div 7 + 1"
ok=true
declare -A nth=( [1]=1 [7]=1 [8]=2 [14]=2 [15]=3 [21]=3 [22]=4 [28]=4 [29]=5 [31]=5 )
for d in "${!nth[@]}"; do
    [[ "$(dateutils.nthDayOfWeek "$(dateutils.encodeDate 2011 3 $d)")" == "${nth[$d]}" ]] \
        || { ok=false; echo "  day $d -> $(dateutils.nthDayOfWeek "$(dateutils.encodeDate 2011 3 $d)") want ${nth[$d]}" >&2; }
done
$ok && kt_test_pass "nthDayOfWeek: (day-of-month-1) div 7 + 1" \
     || kt_test_fail "nthDayOfWeek wrong"

kt_test_start "decodeDayOfWeekInMonth echoes 'year month nth dow'"
# 2011-03-26 is the 4th Saturday (dow 6) of March 2011.
if [[ "$(dateutils.decodeDayOfWeekInMonth "$(dateutils.encodeDate 2011 3 26)")" == "2011 3 4 6" ]]; then
    kt_test_pass "decodeDayOfWeekInMonth echoes 'year month nth dow'"
else
    kt_test_fail "decodeDayOfWeekInMonth = [$(dateutils.decodeDayOfWeekInMonth "$(dateutils.encodeDate 2011 3 26)")]"
fi
