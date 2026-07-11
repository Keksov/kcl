#!/bin/bash
# P4.1 — Inc* family (own-design). Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Increment" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }

# --- incMonth clamps to the target month's length ---------------------------
kt_test_start "incMonth clamps day to the target month (Jan 31 +1m -> Feb 28/29)"
ok=true
[[ "$(fmt "$(dateutils.incMonth "$(dateutils.encodeDate 2004 1 31)" 1)")"  == "2004-02-29 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.incMonth "$(dateutils.encodeDate 2005 1 31)" 1)")"  == "2005-02-28 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.incMonth "$(dateutils.encodeDate 2011 12 15)" 1)")" == "2012-01-15 00:00:00.000" ]] || ok=false  # year roll
[[ "$(fmt "$(dateutils.incMonth "$(dateutils.encodeDate 2011 3 26)" -2)")" == "2011-01-26 00:00:00.000" ]] || ok=false  # negative
[[ "$(fmt "$(dateutils.incMonth "$(dateutils.encodeDate 2011 1 15)" -1)")" == "2010-12-15 00:00:00.000" ]] || ok=false  # year roll back
$ok && kt_test_pass "incMonth clamps day to the target month (Jan 31 +1m -> Feb 28/29)" \
     || kt_test_fail "incMonth wrong"

# --- incMonth preserves time-of-day -----------------------------------------
kt_test_start "incMonth/incYear preserve time-of-day"
d=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
if [[ "$(fmt "$(dateutils.incMonth $d 1)")" == "2011-04-26 19:15:30.555" \
   && "$(fmt "$(dateutils.incYear $d 1)")" == "2012-03-26 19:15:30.555" ]]; then
    kt_test_pass "incMonth/incYear preserve time-of-day"
else
    kt_test_fail "time-of-day not preserved"
fi

# --- incYear Feb-29 clamps to Feb-28 in a non-leap target -------------------
kt_test_start "incYear clamps Feb 29 to Feb 28 when the target year is non-leap"
ok=true
[[ "$(fmt "$(dateutils.incYear "$(dateutils.encodeDate 2004 2 29)" 1)")" == "2005-02-28 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.incYear "$(dateutils.encodeDate 2004 2 29)" 4)")" == "2008-02-29 00:00:00.000" ]] || ok=false  # leap target keeps 29
[[ "$(fmt "$(dateutils.incYear "$(dateutils.encodeDate 2000 2 29)" -1)")" == "1999-02-28 00:00:00.000" ]] || ok=false # negative
$ok && kt_test_pass "incYear clamps Feb 29 to Feb 28 when the target year is non-leap" \
     || kt_test_fail "incYear leap clamp wrong"

# --- incWeek/Day/Hour/Minute/Second/MilliSecond are exact ms shifts ---------
kt_test_start "incWeek/Day/Hour/Minute/Second/MilliSecond shift by exact ms"
base=$(dateutils.encodeDateTime 2011 3 26 12 0 0 0)
ok=true
(( $(dateutils.incWeek $base 2)   - base ==  2*604800000 )) || ok=false
(( $(dateutils.incDay $base 3)    - base ==  3*86400000 ))  || ok=false
(( $(dateutils.incHour $base -5)  - base == -5*3600000 ))   || ok=false
(( $(dateutils.incMinute $base 90) - base == 90*60000 ))    || ok=false
(( $(dateutils.incSecond $base 1) - base ==  1000 ))        || ok=false
(( $(dateutils.incMilliSecond $base 7) - base == 7 ))       || ok=false
# defaults (no count) == +1 unit
(( $(dateutils.incDay $base) - base == 86400000 )) || ok=false
$ok && kt_test_pass "incWeek/Day/Hour/Minute/Second/MilliSecond shift by exact ms" \
     || kt_test_fail "inc shift wrong"

# --- negative deltas are symmetric ------------------------------------------
kt_test_start "inc with +n then -n round-trips"
ok=true
for f in incDay incHour incMinute incSecond incMonth incYear incWeek; do
    r=$(dateutils.$f "$(dateutils.$f $base 5)" -5)
    [[ "$r" == "$base" ]] || { ok=false; echo "  $f +5 -5 -> $r != $base" >&2; }
done
$ok && kt_test_pass "inc with +n then -n round-trips" \
     || kt_test_fail "inc +n/-n not symmetric"
