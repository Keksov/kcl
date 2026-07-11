#!/bin/bash
# P4.3 — compare*/same*, withinPast*, *InRange (own-design).
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "CompareRange" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- compare* echo -1/0/1 ---------------------------------------------------
kt_test_start "compareDateTime/Date/Time echo -1/0/1 with correct semantics"
early=$(dateutils.encodeDateTime 2011 3 26 8 0 0 0)
late=$(dateutils.encodeDateTime 2011 3 26 20 0 0 0)
nextday=$(dateutils.encodeDateTime 2011 3 27 8 0 0 0)
ok=true
[[ "$(dateutils.compareDateTime $early $late)" == -1 ]] || ok=false
[[ "$(dateutils.compareDateTime $late $early)" == 1  ]] || ok=false
[[ "$(dateutils.compareDateTime $early $early)" == 0 ]] || ok=false
# compareDate ignores time (same day -> 0)
[[ "$(dateutils.compareDate $early $late)" == 0 ]] || ok=false
[[ "$(dateutils.compareDate $early $nextday)" == -1 ]] || ok=false
# compareTime ignores date (same time-of-day across days -> 0)
[[ "$(dateutils.compareTime $early $nextday)" == 0 ]] || ok=false
[[ "$(dateutils.compareTime $early $late)" == -1 ]] || ok=false
$ok && kt_test_pass "compareDateTime/Date/Time echo -1/0/1 with correct semantics" \
     || kt_test_fail "compare* wrong"

# --- same* ------------------------------------------------------------------
kt_test_start "sameDateTime/Date/Time"
ok=true
[[ "$(dateutils.sameDateTime $early $early)" == true  ]] || ok=false
[[ "$(dateutils.sameDateTime $early $late)"  == false ]] || ok=false
[[ "$(dateutils.sameDate $early $late)"      == true  ]] || ok=false   # same day
[[ "$(dateutils.sameDate $early $nextday)"   == false ]] || ok=false
[[ "$(dateutils.sameTime $early $nextday)"   == true  ]] || ok=false   # same time-of-day
[[ "$(dateutils.sameTime $early $late)"      == false ]] || ok=false
$ok && kt_test_pass "sameDateTime/Date/Time" \
     || kt_test_fail "same* wrong"

# --- withinPast* == (xBetween(now,then) <= range) ---------------------------
kt_test_start "withinPast* compare the corresponding *Between to the range"
now=$(dateutils.encodeDate 2011 3 26); then5=$(dateutils.encodeDate 2011 3 21)   # 5 days earlier
ok=true
[[ "$(dateutils.withinPastDays $now $then5 10)" == true  ]] || ok=false   # 5 <= 10
[[ "$(dateutils.withinPastDays $now $then5 3)"  == false ]] || ok=false   # 5 <= 3 ?
[[ "$(dateutils.withinPastHours $now $then5 200)" == true ]] || ok=false  # 120 <= 200
[[ "$(dateutils.withinPastWeeks $now $then5 1)"  == true  ]] || ok=false  # 0 weeks
# years (approx): 2000-01-01 .. 2011-01-01 -> 11 years
ny=$(dateutils.encodeDate 2011 1 1); ty=$(dateutils.encodeDate 2000 1 1)
[[ "$(dateutils.withinPastYears $ny $ty 12)" == true  ]] || ok=false
[[ "$(dateutils.withinPastYears $ny $ty 10)" == false ]] || ok=false
$ok && kt_test_pass "withinPast* compare the corresponding *Between to the range" \
     || kt_test_fail "withinPast* wrong"

# --- dateTimeInRange inclusive/exclusive ------------------------------------
kt_test_start "dateTimeInRange honors the inclusive flag (default true)"
s=$(dateutils.encodeDateTime 2011 3 26 8 0 0 0)
e=$(dateutils.encodeDateTime 2011 3 26 20 0 0 0)
mid=$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)
ok=true
[[ "$(dateutils.dateTimeInRange $mid $s $e)"        == true  ]] || ok=false
[[ "$(dateutils.dateTimeInRange $s $s $e)"          == true  ]] || ok=false   # boundary, inclusive default
[[ "$(dateutils.dateTimeInRange $s $s $e false)"    == false ]] || ok=false   # boundary, exclusive
[[ "$(dateutils.dateTimeInRange $mid $s $e false)"  == true  ]] || ok=false
outside=$(dateutils.encodeDateTime 2011 3 26 21 0 0 0)
[[ "$(dateutils.dateTimeInRange $outside $s $e)"    == false ]] || ok=false
$ok && kt_test_pass "dateTimeInRange honors the inclusive flag (default true)" \
     || kt_test_fail "dateTimeInRange wrong"

# --- dateInRange (day granularity) ------------------------------------------
kt_test_start "dateInRange compares whole days"
ok=true
d=$(dateutils.encodeDateTime 2011 3 26 15 0 0 0)
[[ "$(dateutils.dateInRange $d "$(dateutils.encodeDate 2011 3 1)" "$(dateutils.encodeDate 2011 3 31)")" == true  ]] || ok=false
[[ "$(dateutils.dateInRange $d "$(dateutils.encodeDate 2011 3 27)" "$(dateutils.encodeDate 2011 3 31)")" == false ]] || ok=false
# boundary day is inclusive by default even with a time component
[[ "$(dateutils.dateInRange $d "$(dateutils.encodeDate 2011 3 26)" "$(dateutils.encodeDate 2011 3 31)")" == true  ]] || ok=false
$ok && kt_test_pass "dateInRange compares whole days" \
     || kt_test_fail "dateInRange wrong"

# --- timeInRange incl. the overnight wrap -----------------------------------
kt_test_start "timeInRange handles same-day and overnight (end<start) ranges"
ok=true
# same-day range 09:00..17:00
ws=$(dateutils.encodeDateTime 2000 1 1 9 0 0 0); we=$(dateutils.encodeDateTime 2000 1 1 17 0 0 0)
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)" $ws $we)" == true  ]] || ok=false
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 8 0 0 0)"  $ws $we)" == false ]] || ok=false
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 9 0 0 0)"  $ws $we false)" == false ]] || ok=false  # boundary excl
# overnight range 22:00..06:00 (wrap)
ns=$(dateutils.encodeDateTime 2000 1 1 22 0 0 0); ne=$(dateutils.encodeDateTime 2000 1 1 6 0 0 0)
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 23 0 0 0)" $ns $ne)" == true  ]] || ok=false
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 5 0 0 0)"  $ns $ne)" == true  ]] || ok=false
[[ "$(dateutils.timeInRange "$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)" $ns $ne)" == false ]] || ok=false
$ok && kt_test_pass "timeInRange handles same-day and overnight (end<start) ranges" \
     || kt_test_fail "timeInRange wrong"
