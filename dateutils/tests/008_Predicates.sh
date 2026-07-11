#!/bin/bash
# P3 — day predicates: isToday, isSameDay, isSameMonth, previousDayOfWeek.
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Predicates" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- isSameDay --------------------------------------------------------------
kt_test_start "isSameDay: same calendar day true, neighbours false, midnight boundary excluded"
ok=true
a=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
b=$(dateutils.encodeDateTime 2011 3 26 3 0 0 0)
[[ "$(dateutils.isSameDay "$a" "$b")" == true  ]] || ok=false
[[ "$(dateutils.isSameDay "$a" "$(dateutils.encodeDate 2011 3 27)")" == false ]] || ok=false
[[ "$(dateutils.isSameDay "$a" "$(dateutils.encodeDate 2011 3 25)")" == false ]] || ok=false
# boundary: exactly next midnight is NOT the same day as any time on 2011-03-26
[[ "$(dateutils.isSameDay "$(dateutils.encodeDate 2011 3 27)" "$b")" == false ]] || ok=false
# start-of-day is the same day as an evening basis
[[ "$(dateutils.isSameDay "$(dateutils.startOfTheDay "$a")" "$a")" == true ]] || ok=false
$ok && kt_test_pass "isSameDay: same calendar day true, neighbours false, midnight boundary excluded" \
     || kt_test_fail "isSameDay wrong"

# --- isSameDay only truncates the BASIS (FPC quirk) -------------------------
kt_test_start "isSameDay truncates only the basis argument (FPC semantics)"
# value = 2011-03-26 23:59:59.999, basis = 2011-03-26 00:00 -> same day (basis truncated, value kept)
v=$(dateutils.encodeDateTime 2011 3 26 23 59 59 999)
if [[ "$(dateutils.isSameDay "$v" "$(dateutils.encodeDate 2011 3 26)")" == true ]]; then
    kt_test_pass "isSameDay truncates only the basis argument (FPC semantics)"
else
    kt_test_fail "isSameDay basis-truncation semantics wrong"
fi

# --- isSameMonth ------------------------------------------------------------
kt_test_start "isSameMonth compares year AND month"
ok=true
m=$(dateutils.encodeDate 2011 3 26)
[[ "$(dateutils.isSameMonth "$m" "$(dateutils.encodeDate 2011 3 1)")"  == true  ]] || ok=false
[[ "$(dateutils.isSameMonth "$m" "$(dateutils.encodeDate 2011 4 1)")"  == false ]] || ok=false
[[ "$(dateutils.isSameMonth "$m" "$(dateutils.encodeDate 2010 3 26)")" == false ]] || ok=false   # same month, diff year
$ok && kt_test_pass "isSameMonth compares year AND month" \
     || kt_test_fail "isSameMonth wrong"

# --- isToday ----------------------------------------------------------------
kt_test_start "isToday: true for now, false for a fixed past date"
ok=true
[[ "$(dateutils.isToday "$(dateutils.now)")"        == true  ]] || ok=false
[[ "$(dateutils.isToday "$(dateutils.startOfTheDay "$(dateutils.now)")")" == true ]] || ok=false
[[ "$(dateutils.isToday "$(dateutils.encodeDate 2011 3 26)")" == false ]] || ok=false
$ok && kt_test_pass "isToday: true for now, false for a fixed past date" \
     || kt_test_fail "isToday wrong"

# --- previousDayOfWeek ------------------------------------------------------
kt_test_start "previousDayOfWeek: ISO weekday wraps (Mon->Sun); rejects out-of-range"
ok=true
declare -A prev=( [1]=7 [2]=1 [3]=2 [4]=3 [5]=4 [6]=5 [7]=6 )
for dw in 1 2 3 4 5 6 7; do
    [[ "$(dateutils.previousDayOfWeek $dw)" == "${prev[$dw]}" ]] || { ok=false; break; }
done
dateutils.previousDayOfWeek 0 2>/dev/null && ok=false
dateutils.previousDayOfWeek 8 2>/dev/null && ok=false
$ok && kt_test_pass "previousDayOfWeek: ISO weekday wraps (Mon->Sun); rejects out-of-range" \
     || kt_test_fail "previousDayOfWeek wrong"
