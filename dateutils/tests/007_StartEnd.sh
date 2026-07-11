#!/bin/bash
# P3 — start/end of year/month/week/day (own-design). tw16040 StartOfTheYear/
# EndOfTheYear anchors live in 002_FpcParity.sh. Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "StartEnd" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

D=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)   # a Saturday
fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }

# --- year / month / day boundaries via ISO strings --------------------------
kt_test_start "startOf/endOf year|month|day produce the right instants"
ok=true
[[ "$(fmt "$(dateutils.startOfTheYear $D)")"  == "2011-01-01 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.endOfTheYear $D)")"    == "2011-12-31 23:59:59.999" ]] || ok=false
[[ "$(fmt "$(dateutils.startOfTheMonth $D)")" == "2011-03-01 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.endOfTheMonth $D)")"   == "2011-03-31 23:59:59.999" ]] || ok=false
[[ "$(fmt "$(dateutils.startOfTheDay $D)")"   == "2011-03-26 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.endOfTheDay $D)")"     == "2011-03-26 23:59:59.999" ]] || ok=false
# leap Feb end
[[ "$(fmt "$(dateutils.endOfAMonth 2000 2)")" == "2000-02-29 23:59:59.999" ]] || ok=false
[[ "$(fmt "$(dateutils.endOfAMonth 2011 2)")" == "2011-02-28 23:59:59.999" ]] || ok=false
$ok && kt_test_pass "startOf/endOf year|month|day produce the right instants" \
     || kt_test_fail "start/end year|month|day wrong"

# --- week boundaries are Monday..Sunday (ISO) -------------------------------
kt_test_start "startOfTheWeek is Monday 00:00, endOfTheWeek is Sunday 23:59:59.999"
ok=true
[[ "$(fmt "$(dateutils.startOfTheWeek $D)")" == "2011-03-21 00:00:00.000" ]] || ok=false   # Mon
[[ "$(fmt "$(dateutils.endOfTheWeek $D)")"   == "2011-03-27 23:59:59.999" ]] || ok=false   # Sun
# Monday input maps to itself; Sunday input maps to that Sunday
[[ "$(fmt "$(dateutils.startOfTheWeek "$(dateutils.encodeDate 2011 3 21)")")" == "2011-03-21 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.endOfTheWeek "$(dateutils.encodeDate 2011 3 27)")")"   == "2011-03-27 23:59:59.999" ]] || ok=false
$ok && kt_test_pass "startOfTheWeek is Monday 00:00, endOfTheWeek is Sunday 23:59:59.999" \
     || kt_test_fail "week boundaries wrong"

# --- The/A twins agree ------------------------------------------------------
kt_test_start "The/A twins agree on the same inputs"
ok=true
[[ "$(dateutils.startOfAYear 2011)"    == "$(dateutils.startOfTheYear $D)"  ]] || ok=false
[[ "$(dateutils.endOfAYear 2011)"      == "$(dateutils.endOfTheYear $D)"    ]] || ok=false
[[ "$(dateutils.startOfAMonth 2011 3)" == "$(dateutils.startOfTheMonth $D)" ]] || ok=false
[[ "$(dateutils.endOfAMonth 2011 3)"   == "$(dateutils.endOfTheMonth $D)"   ]] || ok=false
[[ "$(dateutils.startOfADay 2011 3 26)" == "$(dateutils.startOfTheDay $D)"  ]] || ok=false
[[ "$(dateutils.endOfADay 2011 3 26)"   == "$(dateutils.endOfTheDay $D)"    ]] || ok=false
$ok && kt_test_pass "The/A twins agree on the same inputs" \
     || kt_test_fail "The/A twin mismatch"

# --- startOfADay/endOfADay day-of-year overload -----------------------------
kt_test_start "startOfADay/endOfADay accept the (year, dayOfYear) overload"
ok=true
# 2011 day 85 == Mar 26
[[ "$(dateutils.startOfADay 2011 85)" == "$(dateutils.startOfADay 2011 3 26)" ]] || ok=false
[[ "$(dateutils.endOfADay 2011 85)"   == "$(dateutils.endOfADay 2011 3 26)"   ]] || ok=false
# 2000 leap day 60 == Feb 29
[[ "$(fmt "$(dateutils.startOfADay 2000 60)")" == "2000-02-29 00:00:00.000" ]] || ok=false
$ok && kt_test_pass "startOfADay/endOfADay accept the (year, dayOfYear) overload" \
     || kt_test_fail "day-of-year overload wrong"

# --- endOfTheX == startOfNext(X) - 1ms --------------------------------------
kt_test_start "endOfTheX is exactly 1ms before the start of the next period"
ok=true
(( $(dateutils.startOfADay 2011 3 27)  - $(dateutils.endOfTheDay $D)   == 1 )) || ok=false
(( $(dateutils.startOfAMonth 2011 4)   - $(dateutils.endOfTheMonth $D) == 1 )) || ok=false
(( $(dateutils.startOfAYear 2012)      - $(dateutils.endOfTheYear $D)  == 1 )) || ok=false
# next week start = Monday after this week's Sunday
(( $(dateutils.startOfTheWeek "$(dateutils.encodeDate 2011 3 28)") - $(dateutils.endOfTheWeek $D) == 1 )) || ok=false
$ok && kt_test_pass "endOfTheX is exactly 1ms before the start of the next period" \
     || kt_test_fail "end/start-next 1ms invariant broken"

# --- startOfAWeek / endOfAWeek (ISO week-date) ------------------------------
kt_test_start "startOfAWeek/endOfAWeek land on ISO week Monday/Sunday"
ok=true
# ISO week 1 of 2009 starts Monday 2008-12-29
[[ "$(fmt "$(dateutils.startOfAWeek 2009 1 1)")" == "2008-12-29 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.startOfAWeek 2009 1)")"   == "2008-12-29 00:00:00.000" ]] || ok=false   # default dow=1
[[ "$(fmt "$(dateutils.endOfAWeek 2009 1)")"     == "2009-01-04 23:59:59.999" ]] || ok=false   # default dow=7 (Sun)
# invalid week -> status 1
dateutils.startOfAWeek 2005 53 1 2>/dev/null && ok=false   # 2005 has 52 weeks
$ok && kt_test_pass "startOfAWeek/endOfAWeek land on ISO week Monday/Sunday" \
     || kt_test_fail "startOfAWeek/endOfAWeek wrong"
