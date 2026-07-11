#!/bin/bash
# P1.1 — encode*/decode* and try* variants (own-design coverage).
# FPC-traceable anchors live in 002_FpcParity.sh; every check here has a row in
# ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "EncodeDecode" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# --- encodeDateTime <-> decodeDateTime roundtrip over a grid -----------------
kt_test_start "encodeDateTime/decodeDateTime roundtrip over a grid (incl. pre-1970)"
fail=""; n=0
for spec in \
    "1970 1 1 0 0 0 0" "1969 12 31 23 59 59 999" "2000 2 29 12 30 45 123" \
    "1899 12 30 0 0 0 0" "2011 3 26 19 15 30 555" "2400 2 29 6 0 0 1" \
    "1 1 1 0 0 0 0" "9999 12 31 23 59 59 999" "2004 2 29 0 0 0 1"; do
    read -r y mo d h mi s ms <<< "$spec"
    kdt=$(dateutils.encodeDateTime "$y" "$mo" "$d" "$h" "$mi" "$s" "$ms") || { fail="encode failed: $spec"; break; }
    got=$(dateutils.decodeDateTime "$kdt")
    n=$((n+1))
    [[ "$got" == "$y $mo $d $h $mi $s $ms" ]] || { fail="$spec -> [$got]"; break; }
done
if [[ -z "$fail" ]]; then
    kt_test_pass "encodeDateTime/decodeDateTime roundtrip over a grid ($n cases)"
else
    kt_test_fail "roundtrip mismatch: $fail"
fi

# --- encodeDate == encodeDateTime at midnight; decodeDate agrees -------------
kt_test_start "encodeDate(y,m,d) == encodeDateTime(y,m,d,0,0,0,0); decodeDate matches"
a=$(dateutils.encodeDate 2011 3 26)
b=$(dateutils.encodeDateTime 2011 3 26 0 0 0 0)
if [[ "$a" == "$b" && "$(dateutils.decodeDate "$a")" == "2011 3 26" ]]; then
    kt_test_pass "encodeDate(y,m,d) == encodeDateTime(y,m,d,0,0,0,0); decodeDate matches"
else
    kt_test_fail "encodeDate=$a encodeDateTime=$b decode=[$(dateutils.decodeDate "$a")]"
fi

# --- encodeTime numeric contract + the 24:00:00.000 whole-day quirk ----------
kt_test_start "encodeTime returns time-of-day ms; 24:00:00.000 -> a full day (FPC quirk)"
ok=true
[[ "$(dateutils.encodeTime 0 0 0 0)" == 0 ]] || ok=false
[[ "$(dateutils.encodeTime 19 15 30 555)" == 69330555 ]] || ok=false
[[ "$(dateutils.encodeTime 23 59 59 999)" == 86399999 ]] || ok=false
[[ "$(dateutils.encodeTime 24 0 0 0)" == 86400000 ]] || ok=false
# encodeDateTime with h=24 rolls to next midnight (ComposeDateTime(date, 1.0)).
[[ "$(dateutils.encodeDateTime 2011 3 26 24 0 0 0)" == "$(dateutils.encodeDate 2011 3 27)" ]] || ok=false
if $ok; then
    kt_test_pass "encodeTime returns time-of-day ms; 24:00:00.000 -> a full day (FPC quirk)"
else
    kt_test_fail "encodeTime numeric contract wrong"
fi

# --- decodeTime -------------------------------------------------------------
kt_test_start "decodeTime splits time-of-day fields"
kdt=$(dateutils.encodeDateTime 2011 3 26 19 15 30 555)
if [[ "$(dateutils.decodeTime "$kdt")" == "19 15 30 555" ]]; then
    kt_test_pass "decodeTime splits time-of-day fields"
else
    kt_test_fail "decodeTime got [$(dateutils.decodeTime "$kdt")]"
fi

# --- encode* / tryEncode* failure contract ----------------------------------
kt_test_start "encode*/tryEncode* reject invalid inputs (status 1, echo nothing)"
ok=true; bad=""
check_reject() { local out; if out=$("$@" 2>/dev/null); then ok=false; bad="$* -> [$out]"; return 1; fi; [[ -z "$out" ]] || { ok=false; bad="$* echoed [$out]"; }; }
check_reject dateutils.encodeDate 2011 2 30
check_reject dateutils.encodeDate 0 1 1
check_reject dateutils.encodeDate 2011 13 1
check_reject dateutils.tryEncodeDate 2011 4 31
check_reject dateutils.encodeTime 25 0 0 0
check_reject dateutils.tryEncodeTime 10 60 0 0
check_reject dateutils.encodeDateTime 2011 2 29 12 0 0 0
check_reject dateutils.tryEncodeDateTime 2011 1 1 10 0 0 1000
if $ok; then
    kt_test_pass "encode*/tryEncode* reject invalid inputs (status 1, echo nothing)"
else
    kt_test_fail "not rejected: $bad"
fi

# --- tryEncode* success returns value + status 0 -----------------------------
kt_test_start "tryEncode* echo the value and return 0 on success"
if v=$(dateutils.tryEncodeDate 2011 3 26) && [[ "$v" == "$(dateutils.encodeDate 2011 3 26)" ]] \
   && v2=$(dateutils.tryEncodeDateTime 2011 3 26 19 15 30 555) && [[ "$v2" == 1301166930555 ]]; then
    kt_test_pass "tryEncode* echo the value and return 0 on success"
else
    kt_test_fail "tryEncode* success path wrong (v=$v v2=$v2)"
fi

# --- encodeDateDay / decodeDateDay ------------------------------------------
kt_test_start "encodeDateDay/decodeDateDay roundtrip + day-of-year anchors"
ok=true
# 2011 is non-leap: day 85 = Mar 26 (31+28+26), day 1 = Jan 1, day 365 = Dec 31.
[[ "$(dateutils.encodeDateDay 2011 1)"   == "$(dateutils.encodeDate 2011 1 1)"   ]] || ok=false
[[ "$(dateutils.encodeDateDay 2011 85)"  == "$(dateutils.encodeDate 2011 3 26)"  ]] || ok=false
[[ "$(dateutils.encodeDateDay 2011 365)" == "$(dateutils.encodeDate 2011 12 31)" ]] || ok=false
# 2000 is leap: day 366 = Dec 31, day 60 = Feb 29.
[[ "$(dateutils.encodeDateDay 2000 60)"  == "$(dateutils.encodeDate 2000 2 29)"  ]] || ok=false
[[ "$(dateutils.encodeDateDay 2000 366)" == "$(dateutils.encodeDate 2000 12 31)" ]] || ok=false
[[ "$(dateutils.decodeDateDay "$(dateutils.encodeDate 2011 3 26)")" == "2011 85" ]] || ok=false
[[ "$(dateutils.decodeDateDay "$(dateutils.encodeDate 2000 12 31)")" == "2000 366" ]] || ok=false
if $ok; then
    kt_test_pass "encodeDateDay/decodeDateDay roundtrip + day-of-year anchors"
else
    kt_test_fail "encodeDateDay/decodeDateDay wrong"
fi

kt_test_start "encodeDateDay rejects day-of-year past the year length"
ok=true
dateutils.encodeDateDay 2011 366 2>/dev/null && ok=false   # 2011 non-leap -> max 365
dateutils.encodeDateDay 2011 0 2>/dev/null && ok=false
dateutils.tryEncodeDateDay 2000 367 2>/dev/null && ok=false
dateutils.encodeDateDay 2000 366 2>/dev/null >/dev/null || ok=false   # leap -> 366 valid
if $ok; then
    kt_test_pass "encodeDateDay rejects day-of-year past the year length"
else
    kt_test_fail "encodeDateDay boundary handling wrong"
fi
