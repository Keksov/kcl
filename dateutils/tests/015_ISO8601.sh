#!/bin/bash
# P6 — ISO 8601 strings, TZ offsets, local<->UTC, time intervals (own-design).
# Rows in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "ISO8601" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

fmt() { dateutils._fmt_datetime "$1"; printf '%s' "$REPLY"; }

# --- dateToISO8601 / iso8601ToDate roundtrip (UTC) --------------------------
kt_test_start "dateToISO8601 emits ...Z (UTC) and iso8601ToDate round-trips it"
dt=$(dateutils.encodeDateTime 2010 3 22 6 30 15 250)
s=$(dateutils.dateToISO8601 $dt)
ok=true
[[ "$s" == "2010-03-22T06:30:15.250Z" ]] || ok=false
[[ "$(dateutils.iso8601ToDate "$s")" == "$dt" ]] || ok=false
$ok && kt_test_pass "dateToISO8601 emits ...Z (UTC) and iso8601ToDate round-trips it" \
     || kt_test_fail "dateToISO8601/iso8601ToDate roundtrip wrong (s=$s)"

# --- iso8601ToDate converts zoned strings to UTC ----------------------------
kt_test_start "iso8601ToDate converts +hh:mm / -hh:mm / Z to UTC"
ok=true
[[ "$(fmt "$(dateutils.iso8601ToDate 2010-03-22T09:00:00.000+03:00)")" == "2010-03-22 06:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.iso8601ToDate 2010-03-22T01:00:00.000-05:00)")" == "2010-03-22 06:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.iso8601ToDate 2010-03-22T06:00:00.000Z)")"      == "2010-03-22 06:00:00.000" ]] || ok=false
$ok && kt_test_pass "iso8601ToDate converts +hh:mm / -hh:mm / Z to UTC" \
     || kt_test_fail "iso8601ToDate zone conversion wrong"

kt_test_start "tryISO8601ToDate rejects malformed; iso8601ToDateDef falls back"
ok=true
dateutils.tryISO8601ToDate "not-a-date" 2>/dev/null && ok=false
dateutils.tryISO8601ToDate "2010-13-01T00:00:00Z" 2>/dev/null && ok=false
[[ "$(dateutils.iso8601ToDateDef "garbage" 42)" == 42 ]] || ok=false
[[ "$(dateutils.iso8601ToDateDef "2010-03-22T06:00:00.000Z" 42)" == "$(dateutils.encodeDateTime 2010 3 22 6 0 0 0)" ]] || ok=false
$ok && kt_test_pass "tryISO8601ToDate rejects malformed; iso8601ToDateDef falls back" \
     || kt_test_fail "try/Def ISO handling wrong"

# --- tryISOStrToDate / Time / DateTime --------------------------------------
kt_test_start "tryISOStrToDate accepts the 5 ISO date forms"
ok=true
[[ "$(dateutils.tryISOStrToDate 2011)"       == "$(dateutils.encodeDate 2011 1 1)"  ]] || ok=false   # YYYY
[[ "$(dateutils.tryISOStrToDate 201103)"     == "$(dateutils.encodeDate 2011 3 1)"  ]] || ok=false   # YYYYMM
[[ "$(dateutils.tryISOStrToDate 2011-03)"    == "$(dateutils.encodeDate 2011 3 1)"  ]] || ok=false   # YYYY-MM
[[ "$(dateutils.tryISOStrToDate 20110326)"   == "$(dateutils.encodeDate 2011 3 26)" ]] || ok=false   # YYYYMMDD
[[ "$(dateutils.tryISOStrToDate 2011-03-26)" == "$(dateutils.encodeDate 2011 3 26)" ]] || ok=false   # YYYY-MM-DD
dateutils.tryISOStrToDate "2011-13-01" 2>/dev/null && ok=false   # invalid month
$ok && kt_test_pass "tryISOStrToDate accepts the 5 ISO date forms" \
     || kt_test_fail "tryISOStrToDate wrong"

kt_test_start "tryISOStrToTime -> ms-of-day; tryISOStrToDateTime -> naive datetime"
ok=true
[[ "$(dateutils.tryISOStrToTime 19:15:30.555)" == 69330555 ]] || ok=false
[[ "$(dateutils.tryISOStrToTime 08:05)"        == 29100000 ]] || ok=false   # 8*3600000+5*60000
[[ "$(dateutils.tryISOStrToTime 19:15:30Z)"    == 69330000 ]] || ok=false   # trailing Z tolerated
[[ "$(dateutils.tryISOStrToDateTime '2011-03-26T19:15:30.555')" == "$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)" ]] || ok=false
dateutils.tryISOStrToTime "25:00:00" 2>/dev/null && ok=false
$ok && kt_test_pass "tryISOStrToTime -> ms-of-day; tryISOStrToDateTime -> naive datetime" \
     || kt_test_fail "tryISOStr Time/DateTime wrong"

# --- isoTZStrToTZOffset (FPC sign: '+' -> negative) -------------------------
kt_test_start "isoTZStrToTZOffset uses the FPC sign convention (+03:00 -> -180)"
ok=true
[[ "$(dateutils.isoTZStrToTZOffset +03:00)" == -180 ]] || ok=false
[[ "$(dateutils.isoTZStrToTZOffset -0530)"  == 330  ]] || ok=false
[[ "$(dateutils.isoTZStrToTZOffset +05)"    == -300 ]] || ok=false
[[ "$(dateutils.isoTZStrToTZOffset Z)"      == 0    ]] || ok=false
dateutils.isoTZStrToTZOffset "0300" 2>/dev/null && ok=false   # missing sign
$ok && kt_test_pass "isoTZStrToTZOffset uses the FPC sign convention (+03:00 -> -180)" \
     || kt_test_fail "isoTZStrToTZOffset wrong"

# --- local <-> universal ----------------------------------------------------
kt_test_start "universalTimeToLocal/localTimeToUniversal with explicit east offset"
ut=$(dateutils.encodeDateTime 2011 1 1 12 0 0 0)
ok=true
[[ "$(fmt "$(dateutils.universalTimeToLocal $ut 180)")"    == "2011-01-01 15:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.universalTimeToLocal $ut +03:00)")" == "2011-01-01 15:00:00.000" ]] || ok=false  # string form
[[ "$(fmt "$(dateutils.localTimeToUniversal $ut 180)")"    == "2011-01-01 09:00:00.000" ]] || ok=false
[[ "$(fmt "$(dateutils.localTimeToUniversal $ut -300)")"   == "2011-01-01 17:00:00.000" ]] || ok=false  # UTC-5
# system-offset roundtrip (offset cancels)
[[ "$(dateutils.universalTimeToLocal "$(dateutils.localTimeToUniversal $ut)")" == "$ut" ]] || ok=false
$ok && kt_test_pass "universalTimeToLocal/localTimeToUniversal with explicit east offset" \
     || kt_test_fail "local<->universal wrong"

# --- encodeTimeInterval -----------------------------------------------------
kt_test_start "encodeTimeInterval allows hours > 24; validates m/s/ms"
ok=true
[[ "$(dateutils.encodeTimeInterval 30 15 0 0)" == 108900000 ]] || ok=false   # 30h15m
[[ "$(dateutils.encodeTimeInterval 100 0 0 0)" == 360000000 ]] || ok=false   # 100h
[[ "$(dateutils.tryEncodeTimeInterval 0 0 0 1000)" == 1000 ]] || ok=false    # FPC allows ms == 1000
dateutils.tryEncodeTimeInterval 5 60 0 0 2>/dev/null && ok=false   # min 60 invalid
dateutils.tryEncodeTimeInterval 5 0 60 0 2>/dev/null && ok=false   # sec 60 invalid
$ok && kt_test_pass "encodeTimeInterval allows hours > 24; validates m/s/ms" \
     || kt_test_fail "encodeTimeInterval wrong"
