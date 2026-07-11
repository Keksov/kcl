#!/bin/bash
# P4.2 — *Between, periodBetween, *Span, dateTimeDiff (own-design).
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "BetweenSpan" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- fine-grained *Between (|now-then|/unit) --------------------------------
kt_test_start "milliSeconds/seconds/minutes/hours/days/weeksBetween on a known offset"
h=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
h0=$(dateutils.encodeDate 2011 3 26)
ok=true
[[ "$(dateutils.milliSecondsBetween $h $h0)" == 69330555 ]] || ok=false
[[ "$(dateutils.secondsBetween $h $h0)"      == 69330    ]] || ok=false
[[ "$(dateutils.minutesBetween $h $h0)"      == 1155     ]] || ok=false
[[ "$(dateutils.hoursBetween $h $h0)"        == 19       ]] || ok=false
# symmetric (order-independent)
[[ "$(dateutils.milliSecondsBetween $h0 $h)" == 69330555 ]] || ok=false
a=$(dateutils.encodeDate 2000 1 1); b=$(dateutils.encodeDate 2011 3 26)
[[ "$(dateutils.daysBetween $a $b)"  == 4102 ]] || ok=false
[[ "$(dateutils.weeksBetween $a $b)" == 586  ]] || ok=false   # 4102 div 7
$ok && kt_test_pass "milliSeconds/seconds/minutes/hours/days/weeksBetween on a known offset" \
     || kt_test_fail "fine-grained between wrong"

# --- yearsBetween/monthsBetween: approx default vs exact flag ----------------
# 2001-01-01 -> 2002-01-01 is 365 days: approx (365/365.25 -> 0y, 11m) diverges
# from the calendar-exact (1y, 12m). This pins that the exact flag matters.
kt_test_start "yearsBetween/monthsBetween: approx default differs from exact where expected"
y1=$(dateutils.encodeDate 2001 1 1); y2=$(dateutils.encodeDate 2002 1 1)
ok=true
[[ "$(dateutils.yearsBetween $y1 $y2)"        == 0  ]] || ok=false   # approx
[[ "$(dateutils.yearsBetween $y1 $y2 exact)"  == 1  ]] || ok=false   # calendar-true
[[ "$(dateutils.monthsBetween $y1 $y2)"       == 11 ]] || ok=false   # approx
[[ "$(dateutils.monthsBetween $y1 $y2 exact)" == 12 ]] || ok=false   # calendar-true
$ok && kt_test_pass "yearsBetween/monthsBetween: approx default differs from exact where expected" \
     || kt_test_fail "approx/exact between wrong"

# --- periodBetween borrow logic (values from the faithful FPC port) ---------
# NOTE: PLAN.md predicted 2004-02-29 -> 2005-02-28 = 0y 11m 30d, but the FPC
# PeriodBetween algorithm actually yields 0y 11m 28d. See TEST_COVERAGE_NOTES.md
# corrections table.
kt_test_start "periodBetween decomposes calendar spans (FPC borrow logic)"
ok=true
[[ "$(dateutils.periodBetween "$(dateutils.encodeDate 2004 2 29)" "$(dateutils.encodeDate 2005 2 28)")" == "0 11 28" ]] || ok=false
[[ "$(dateutils.periodBetween "$(dateutils.encodeDate 2000 1 15)" "$(dateutils.encodeDate 2000 3 20)")" == "0 2 5"   ]] || ok=false
[[ "$(dateutils.periodBetween "$(dateutils.encodeDate 2000 1 31)" "$(dateutils.encodeDate 2000 3 1)")"  == "0 1 1"   ]] || ok=false
[[ "$(dateutils.periodBetween "$(dateutils.encodeDate 2000 1 1)"  "$(dateutils.encodeDate 2011 3 26)")" == "11 2 25" ]] || ok=false
# symmetric
[[ "$(dateutils.periodBetween "$(dateutils.encodeDate 2011 3 26)" "$(dateutils.encodeDate 2000 1 1)")" == "11 2 25" ]] || ok=false
$ok && kt_test_pass "periodBetween decomposes calendar spans (FPC borrow logic)" \
     || kt_test_fail "periodBetween wrong"

# --- Span: fixed-point 6 dp -------------------------------------------------
kt_test_start "Span functions print 6-decimal fixed-point ratios"
ok=true
noon=$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)
[[ "$(dateutils.daySpan $noon $h0)"    == "0.500000" ]] || ok=false
[[ "$(dateutils.hourSpan "$(dateutils.encodeDateTime 2011 3 26 1 30 0 0)" $h0)" == "1.500000" ]] || ok=false
[[ "$(dateutils.secondSpan "$(dateutils.encodeDateTime 2011 3 26 0 0 1 500)" $h0)" == "1.500000" ]] || ok=false
[[ "$(dateutils.milliSecondSpan "$(dateutils.encodeDateTime 2011 3 26 0 0 0 250)" $h0)" == "250.000000" ]] || ok=false
# 3.5-day week span
[[ "$(dateutils.weekSpan "$(dateutils.incHour $h0 84)" $h0)" == "0.500000" ]] || ok=false
$ok && kt_test_pass "Span functions print 6-decimal fixed-point ratios" \
     || kt_test_fail "Span 6dp wrong"

# --- Span never overflows for a full-range span (plan risk #3 avoided) ------
kt_test_start "milliSecondSpan handles the full KDT range without overflow"
lo=$(dateutils.encodeDate 1 1 1); hi=$(dateutils.encodeDate 9999 12 31)
# whole part must equal |hi-lo| exactly, fraction .000000
exp=$(( hi - lo )); (( exp < 0 )) && exp=$(( -exp ))
if [[ "$(dateutils.milliSecondSpan $hi $lo)" == "${exp}.000000" ]]; then
    kt_test_pass "milliSecondSpan handles the full KDT range without overflow"
else
    kt_test_fail "milliSecondSpan overflow/mismatch: got $(dateutils.milliSecondSpan $hi $lo) want ${exp}.000000"
fi

# --- dateTimeDiff: signed ms ------------------------------------------------
kt_test_start "dateTimeDiff is signed (now-then) in ms"
if (( $(dateutils.dateTimeDiff $h $h0) == 69330555 )) \
   && (( $(dateutils.dateTimeDiff $h0 $h) == -69330555 )); then
    kt_test_pass "dateTimeDiff is signed (now-then) in ms"
else
    kt_test_fail "dateTimeDiff sign wrong"
fi
