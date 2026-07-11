#!/bin/bash
# P1.2 — validity predicates + calendar-size functions (own-design coverage).
# Every check has a row in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Validity" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- isValidDate ------------------------------------------------------------
kt_test_start "isValidDate: leap-century Feb boundaries + year/month/day bounds"
ok=true
exp() { local got; got=$(dateutils.isValidDate $1 $2 $3); [[ "$got" == "$4" ]] || { ok=false; echo "  isValidDate $1 $2 $3 = $got want $4" >&2; }; }
exp 1900 2 29 false      # century, not /400 -> not leap
exp 2000 2 29 true       # /400 -> leap
exp 2004 2 29 true       # /4 -> leap
exp 2100 2 29 false      # century, not /400
exp 2011 2 29 false
exp 2011 2 28 true
exp 2011 4 31 false      # April has 30
exp 2011 4 30 true
exp 2011 13 1 false      # month bound
exp 2011 0 1 false
exp 2011 1 0 false       # day bound
exp 0 1 1 false          # year 0 invalid
exp 10000 1 1 false      # year 10000 invalid
exp 9999 12 31 true      # year 9999 valid
exp 1 1 1 true
$ok && kt_test_pass "isValidDate: leap-century Feb boundaries + year/month/day bounds" \
     || kt_test_fail "isValidDate wrong"

# --- isValidTime (incl. the 24:00:00.000 whole-day marker) ------------------
kt_test_start "isValidTime: field ranges + the 24:00:00.000 FPC exception"
ok=true
expt() { local got; got=$(dateutils.isValidTime $1 $2 $3 $4); [[ "$got" == "$5" ]] || { ok=false; echo "  isValidTime $1 $2 $3 $4 = $got want $5" >&2; }; }
expt 0 0 0 0 true
expt 23 59 59 999 true
expt 24 0 0 0 true       # FPC: whole-day marker is valid
expt 24 0 0 1 false      # anything nonzero with h=24 -> invalid
expt 24 1 0 0 false
expt 23 60 0 0 false
expt 23 59 60 0 false
expt 23 59 59 1000 false
expt 25 0 0 0 false
$ok && kt_test_pass "isValidTime: field ranges + the 24:00:00.000 FPC exception" \
     || kt_test_fail "isValidTime wrong"

# --- isValidDateTime --------------------------------------------------------
kt_test_start "isValidDateTime = isValidDate AND isValidTime"
ok=true
[[ "$(dateutils.isValidDateTime 2011 3 26 19 15 30 555)" == true ]] || ok=false
[[ "$(dateutils.isValidDateTime 2011 2 29 12 0 0 0)" == false ]] || ok=false   # bad date
[[ "$(dateutils.isValidDateTime 2011 3 26 24 0 0 1)" == false ]] || ok=false   # bad time
[[ "$(dateutils.isValidDateTime 2011 3 26 24 0 0 0)" == true  ]] || ok=false   # 24:00 ok
$ok && kt_test_pass "isValidDateTime = isValidDate AND isValidTime" \
     || kt_test_fail "isValidDateTime wrong"

# --- isValidDateDay ---------------------------------------------------------
kt_test_start "isValidDateDay: day-of-year bounds honor leap length"
ok=true
[[ "$(dateutils.isValidDateDay 2011 365)" == true  ]] || ok=false
[[ "$(dateutils.isValidDateDay 2011 366)" == false ]] || ok=false   # non-leap
[[ "$(dateutils.isValidDateDay 2000 366)" == true  ]] || ok=false   # leap
[[ "$(dateutils.isValidDateDay 2000 367)" == false ]] || ok=false
[[ "$(dateutils.isValidDateDay 2011 0)"   == false ]] || ok=false
[[ "$(dateutils.isValidDateDay 0 100)"    == false ]] || ok=false
$ok && kt_test_pass "isValidDateDay: day-of-year bounds honor leap length" \
     || kt_test_fail "isValidDateDay wrong"

# --- isValidDateWeek (ISO week count) ---------------------------------------
kt_test_start "isValidDateWeek: week bound = WeeksInAYear, dow 1..7"
ok=true
[[ "$(dateutils.isValidDateWeek 2004 53 1)" == true  ]] || ok=false   # 2004 has 53
[[ "$(dateutils.isValidDateWeek 2005 53 1)" == false ]] || ok=false   # 2005 has 52
[[ "$(dateutils.isValidDateWeek 2005 52 7)" == true  ]] || ok=false
[[ "$(dateutils.isValidDateWeek 2004 0 1)"  == false ]] || ok=false   # week 0
[[ "$(dateutils.isValidDateWeek 2004 1 0)"  == false ]] || ok=false   # dow 0
[[ "$(dateutils.isValidDateWeek 2004 1 8)"  == false ]] || ok=false   # dow 8
$ok && kt_test_pass "isValidDateWeek: week bound = WeeksInAYear, dow 1..7" \
     || kt_test_fail "isValidDateWeek wrong"

# --- isValidDateMonthWeek ---------------------------------------------------
kt_test_start "isValidDateMonthWeek: month 1..12, weekOfMonth 1..5, dow 1..7"
ok=true
[[ "$(dateutils.isValidDateMonthWeek 2011 3 4 6)" == true  ]] || ok=false
[[ "$(dateutils.isValidDateMonthWeek 2011 3 6 1)" == false ]] || ok=false   # wom 6
[[ "$(dateutils.isValidDateMonthWeek 2011 13 1 1)" == false ]] || ok=false  # month 13
[[ "$(dateutils.isValidDateMonthWeek 2011 3 0 1)" == false ]] || ok=false   # wom 0
[[ "$(dateutils.isValidDateMonthWeek 2011 3 5 7)" == true  ]] || ok=false
$ok && kt_test_pass "isValidDateMonthWeek: month 1..12, weekOfMonth 1..5, dow 1..7" \
     || kt_test_fail "isValidDateMonthWeek wrong"

# --- isInLeapYear (date argument) -------------------------------------------
kt_test_start "isInLeapYear takes a DATE and checks its year"
ok=true
expl() { local got; got=$(dateutils.isInLeapYear "$(dateutils.encodeDate $1 6 15)"); [[ "$got" == "$2" ]] || { ok=false; echo "  isInLeapYear($1) = $got want $2" >&2; }; }
expl 1900 false; expl 2000 true; expl 2004 true; expl 2100 false; expl 2011 false; expl 2024 true
$ok && kt_test_pass "isInLeapYear takes a DATE and checks its year" \
     || kt_test_fail "isInLeapYear wrong"

# --- daysInAMonth (full 12-month table + leap Feb) --------------------------
kt_test_start "daysInAMonth: full non-leap table + Feb leap variants + invalid month"
ok=true
nonleap=(31 28 31 30 31 30 31 31 30 31 30 31)
for m in $(seq 1 12); do
    [[ "$(dateutils.daysInAMonth 2011 $m)" == "${nonleap[$((m-1))]}" ]] || { ok=false; break; }
done
[[ "$(dateutils.daysInAMonth 2000 2)" == 29 ]] || ok=false
[[ "$(dateutils.daysInAMonth 1900 2)" == 28 ]] || ok=false
[[ "$(dateutils.daysInAMonth 2004 2)" == 29 ]] || ok=false
dateutils.daysInAMonth 2011 13 2>/dev/null && ok=false   # invalid month -> status 1
$ok && kt_test_pass "daysInAMonth: full non-leap table + Feb leap variants + invalid month" \
     || kt_test_fail "daysInAMonth wrong"

# --- daysInMonth / daysInAYear / daysInYear ---------------------------------
kt_test_start "daysInMonth(date), daysInAYear, daysInYear"
ok=true
[[ "$(dateutils.daysInMonth "$(dateutils.encodeDate 2000 2 10)")" == 29 ]] || ok=false
[[ "$(dateutils.daysInMonth "$(dateutils.encodeDate 2011 4 10)")" == 30 ]] || ok=false
[[ "$(dateutils.daysInAYear 2000)" == 366 ]] || ok=false
[[ "$(dateutils.daysInAYear 2011)" == 365 ]] || ok=false
[[ "$(dateutils.daysInYear "$(dateutils.encodeDate 2000 7 1)")" == 366 ]] || ok=false
[[ "$(dateutils.daysInYear "$(dateutils.encodeDate 2011 7 1)")" == 365 ]] || ok=false
$ok && kt_test_pass "daysInMonth(date), daysInAYear, daysInYear" \
     || kt_test_fail "daysInMonth/daysInAYear/daysInYear wrong"

# --- weeksInAYear / weeksInYear (ISO fixtures) ------------------------------
kt_test_start "weeksInAYear / weeksInYear: ISO 52-vs-53 fixtures"
ok=true
declare -A wexp=( [2004]=53 [2005]=52 [2009]=53 [2015]=53 [2020]=53 [2021]=52 [2026]=53 )
for y in "${!wexp[@]}"; do
    [[ "$(dateutils.weeksInAYear $y)" == "${wexp[$y]}" ]] || { ok=false; echo "  weeksInAYear $y = $(dateutils.weeksInAYear $y) want ${wexp[$y]}" >&2; }
    [[ "$(dateutils.weeksInYear "$(dateutils.encodeDate $y 6 1)")" == "${wexp[$y]}" ]] || ok=false
done
$ok && kt_test_pass "weeksInAYear / weeksInYear: ISO 52-vs-53 fixtures" \
     || kt_test_fail "weeksInAYear/weeksInYear wrong"
