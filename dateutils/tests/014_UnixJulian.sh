#!/bin/bash
# P6.1/P6.2 — Unix + Julian/MJD conversions (own-design). tw16040 Julian and
# tunitdt1 Unix anchors live in 002_FpcParity.sh. Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "UnixJulian" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }

# --- Unix anchors -----------------------------------------------------------
kt_test_start "unixToDateTime/dateTimeToUnix anchors (0, day, negative)"
ok=true
[[ "$(fmt "$(dateutils.unixToDateTime 0)")"     == "1970-01-01 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.unixToDateTime 86400)")" == "1970-01-02 00:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.unixToDateTime -1)")"    == "1969-12-31 23:59:59.000" ]] || ok=false
[[ "$(dateutils.dateTimeToUnix "$(dateutils.encodeDate 1970 1 1)")" == 0 ]] || ok=false
# ms are truncated to the second
[[ "$(dateutils.dateTimeToUnix "$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)")" == 1301166930 ]] || ok=false
$ok && kt_test_pass "unixToDateTime/dateTimeToUnix anchors (0, day, negative)" \
     || kt_test_fail "Unix anchors wrong"

kt_test_start "Unix round-trips over a grid (UTC)"
ok=true
for u in 0 1 86400 1000000000 1301166930 -100000 15796372693; do
    [[ "$(dateutils.dateTimeToUnix "$(dateutils.unixToDateTime $u)")" == "$u" ]] || { ok=false; break; }
done
$ok && kt_test_pass "Unix round-trips over a grid (UTC)" \
     || kt_test_fail "Unix roundtrip broke at u=$u"

# --- Julian date anchors ----------------------------------------------------
kt_test_start "Julian anchors: epoch JD, J2000, and 6-dp formatting"
ok=true
[[ "$(dateutils.dateTimeToJulianDate 0)" == "2440587.500000" ]] || ok=false             # 1970-01-01
[[ "$(dateutils.dateTimeToJulianDate "$(dateutils.encodeDateTime 2000 1 1 12 0 0 0)")" == "2451545.000000" ]] || ok=false  # J2000
[[ "$(fmt "$(dateutils.julianDateToDateTime 2451545.0)")" == "2000-01-01 12:00:00.000" ]] || ok=false
$ok && kt_test_pass "Julian anchors: epoch JD, J2000, and 6-dp formatting" \
     || kt_test_fail "Julian anchors wrong"

kt_test_start "Julian roundtrip is exact at midnight/noon (JD lands on X.5/X.0)"
ok=true
# 00:00 -> X.5, 12:00 -> X.0 are exactly representable at 6 dp.
for spec in "2010 3 22 0 0 0 0" "2000 1 1 12 0 0 0" "1970 1 1 0 0 0 0" "1900 6 15 12 0 0 0" "2470 7 26 0 0 0 0"; do
    read -r y mo d h mi s ms <<< "$spec"
    dt=$(dateutils.encodeDateTime $y $mo $d $h $mi $s $ms)
    back=$(dateutils.julianDateToDateTime "$(dateutils.dateTimeToJulianDate $dt)")
    [[ "$back" == "$dt" ]] || { ok=false; echo "  $spec -> $(fmt "$back")" >&2; break; }
done
$ok && kt_test_pass "Julian roundtrip is exact at midnight/noon (JD lands on X.5/X.0)" \
     || kt_test_fail "Julian midnight/noon roundtrip broke"

kt_test_start "Julian intraday roundtrip is within the documented 6-dp resolution (~86ms)"
# 1e-6 day = 86.4 ms, so an arbitrary time-of-day round-trips to within ~1 JD ulp.
dt=$(dateutils.encodeDateTime 2470 7 26 9 18 13 0)      # tunitdt1's far-future instant
back=$(dateutils.julianDateToDateTime "$(dateutils.dateTimeToJulianDate $dt)")
diff=$(( back - dt )); (( diff < 0 )) && diff=$(( -diff ))
if (( diff <= 87 )); then
    kt_test_pass "Julian intraday roundtrip is within the documented 6-dp resolution (~86ms)"
else
    kt_test_fail "Julian intraday roundtrip off by ${diff}ms (> 87ms)"
fi

# --- Modified Julian --------------------------------------------------------
kt_test_start "Modified Julian: MJD = JD - 2400000.5, epoch MJD 40587, roundtrip"
ok=true
[[ "$(dateutils.dateTimeToModifiedJulianDate 0)" == "40587.000000" ]] || ok=false
d1=$(dateutils.encodeDate 2010 3 22)
mjd=$(dateutils.dateTimeToModifiedJulianDate $d1)
[[ "$mjd" == "55277.000000" ]] || ok=false
[[ "$(dateutils.modifiedJulianDateToDateTime $mjd)" == "$d1" ]] || ok=false
$ok && kt_test_pass "Modified Julian: MJD = JD - 2400000.5, epoch MJD 40587, roundtrip" \
     || kt_test_fail "MJD wrong"

# --- optional GNU date cross-check (skipped if date absent) -----------------
kt_test_start "unixToDateTime cross-checks GNU date -u on sampled epochs"
if command -v date >/dev/null 2>&1 && date -u -d @0 +%Y >/dev/null 2>&1; then
    ok=true
    for u in 0 1000000000 1301166930 1600000000; do
        want=$(date -u -d "@$u" '+%Y-%m-%d %H:%M:%S').000
        got=$(fmt "$(dateutils.unixToDateTime $u)")
        [[ "$got" == "$want" ]] || { ok=false; echo "  u=$u got [$got] want [$want]" >&2; break; }
    done
    $ok && kt_test_pass "unixToDateTime cross-checks GNU date -u on sampled epochs" \
         || kt_test_fail "GNU date cross-check mismatch"
else
    kt_test_pass "unixToDateTime cross-checks GNU date -u on sampled epochs (skipped: date -u unavailable)"
fi
