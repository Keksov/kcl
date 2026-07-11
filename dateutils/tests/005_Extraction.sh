#!/bin/bash
# P2.1 — simple field extractors, ISO week/day-of-week, isAM/isPM (own-design).
# FPC-traceable extraction anchors live in 002_FpcParity.sh; rows in
# ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Extraction" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- simple extractors == decodeDateTime fields -----------------------------
kt_test_start "yearOf..milliSecondOf match decodeDateTime fields"
ok=true
for spec in "2011 3 26 19 15 30 555" "1899 12 30 0 0 0 0" "1969 12 31 23 59 59 999" "2000 2 29 12 0 0 1"; do
    read -r y mo d h mi s ms <<< "$spec"
    k=$(dateutils.encodeDateTime $y $mo $d $h $mi $s $ms)
    got="$(dateutils.yearOf $k) $(dateutils.monthOf $k) $(dateutils.dayOf $k) $(dateutils.hourOf $k) $(dateutils.minuteOf $k) $(dateutils.secondOf $k) $(dateutils.milliSecondOf $k)"
    [[ "$got" == "$spec" ]] || { ok=false; echo "  $spec -> [$got]" >&2; break; }
done
$ok && kt_test_pass "yearOf..milliSecondOf match decodeDateTime fields" \
     || kt_test_fail "simple extractors wrong"

# --- aliases: monthOfTheYear/dayOfTheMonth/hourOfTheDay ----------------------
kt_test_start "monthOfTheYear/dayOfTheMonth aliases agree with monthOf/dayOf"
k=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
if [[ "$(dateutils.monthOfTheYear $k)" == "$(dateutils.monthOf $k)" \
   && "$(dateutils.dayOfTheMonth $k)" == "$(dateutils.dayOf $k)" \
   && "$(dateutils.hourOfTheDay $k)" == "$(dateutils.hourOf $k)" ]]; then
    kt_test_pass "monthOfTheYear/dayOfTheMonth aliases agree with monthOf/dayOf"
else
    kt_test_fail "alias mismatch"
fi

# --- dayOfTheWeek (ISO Mon=1..Sun=7) ----------------------------------------
kt_test_start "dayOfTheWeek is ISO (Mon=1..Sun=7) across a full week"
ok=true
# 2011-03-21 is a Monday -> 1 .. 2011-03-27 Sunday -> 7
for i in 0 1 2 3 4 5 6; do
    k=$(dateutils.encodeDate 2011 3 $((21+i)))
    [[ "$(dateutils.dayOfTheWeek $k)" == "$((i+1))" ]] || { ok=false; break; }
done
[[ "$(dateutils.dayOfTheWeek "$(dateutils.encodeDate 1970 1 1)")" == 4 ]] || ok=false   # Thursday
$ok && kt_test_pass "dayOfTheWeek is ISO (Mon=1..Sun=7) across a full week" \
     || kt_test_fail "dayOfTheWeek wrong"

# --- dayOfTheYear -----------------------------------------------------------
kt_test_start "dayOfTheYear: Jan 1 = 1, Mar 26 non-leap = 85, Dec 31 leap = 366"
ok=true
[[ "$(dateutils.dayOfTheYear "$(dateutils.encodeDate 2011 1 1)")"  == 1   ]] || ok=false
[[ "$(dateutils.dayOfTheYear "$(dateutils.encodeDate 2011 3 26)")" == 85  ]] || ok=false
[[ "$(dateutils.dayOfTheYear "$(dateutils.encodeDate 2011 12 31)")" == 365 ]] || ok=false
[[ "$(dateutils.dayOfTheYear "$(dateutils.encodeDate 2000 12 31)")" == 366 ]] || ok=false
$ok && kt_test_pass "dayOfTheYear: Jan 1 = 1, Mar 26 non-leap = 85, Dec 31 leap = 366" \
     || kt_test_fail "dayOfTheYear wrong"

# --- ISO week-of-year fixtures (weekOfTheYear + weekOf alias + ISO-year) -----
# NOTE: the plan listed "2004-01-01 -> W53(2003)", but 2004-01-01 is a Thursday,
# so ISO-8601 puts it in W01 of 2004. The FPC-ported algorithm agrees; the
# corrected fixture is used here (see TEST_COVERAGE_NOTES.md).
kt_test_start "weekOfTheYear: ISO boundary fixtures with correct ISO-year"
ok=true
check_week() {  # date -> expected week, expected ISO-year
    local k; k=$(dateutils.encodeDate $1 $2 $3)
    dateutils._decode_date_week "$k"
    [[ "$(dateutils.weekOfTheYear $k)" == "$4" && "$__kdt_wy_year" == "$5" ]] \
        || { ok=false; echo "  $1-$2-$3 -> W$(dateutils.weekOfTheYear $k)($__kdt_wy_year) want W$4($5)" >&2; }
    [[ "$(dateutils.weekOf $k)" == "$4" ]] || ok=false   # weekOf == weekOfTheYear
}
check_week 2004 1 1  1  2004    # Thursday -> W01 2004 (plan's W53/2003 was wrong)
check_week 2003 12 31 1 2004    # Wednesday -> spills forward into W01 2004
check_week 2005 1 1  53 2004    # Saturday -> W53 2004
check_week 2008 12 29 1 2009    # Monday -> W01 2009
check_week 2010 1 3  53 2009    # Sunday -> W53 2009
check_week 2009 12 31 53 2009   # Thursday -> W53 2009
check_week 2011 3 26 12 2011
$ok && kt_test_pass "weekOfTheYear: ISO boundary fixtures with correct ISO-year" \
     || kt_test_fail "weekOfTheYear wrong"

# --- weekOfTheMonth ---------------------------------------------------------
kt_test_start "weekOfTheMonth over a month"
ok=true
[[ "$(dateutils.weekOfTheMonth "$(dateutils.encodeDate 2011 3 1)")"  == 1 ]] || ok=false
[[ "$(dateutils.weekOfTheMonth "$(dateutils.encodeDate 2011 3 26)")" == 4 ]] || ok=false
$ok && kt_test_pass "weekOfTheMonth over a month" \
     || kt_test_fail "weekOfTheMonth wrong"

# --- isAM / isPM ------------------------------------------------------------
kt_test_start "isAM/isPM split at noon (hour >= 12 is PM)"
ok=true
[[ "$(dateutils.isAM "$(dateutils.encodeDateTime 2011 3 26 11 59 59 999)")" == true  ]] || ok=false
[[ "$(dateutils.isPM "$(dateutils.encodeDateTime 2011 3 26 11 59 59 999)")" == false ]] || ok=false
[[ "$(dateutils.isPM "$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)")"     == true  ]] || ok=false
[[ "$(dateutils.isAM "$(dateutils.encodeDateTime 2011 3 26 0 0 0 0)")"      == true  ]] || ok=false
$ok && kt_test_pass "isAM/isPM split at noon (hour >= 12 is PM)" \
     || kt_test_fail "isAM/isPM wrong"
