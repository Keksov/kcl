#!/bin/bash
# 022_G3_LocalOffset.sh — finding G3-05, default R7 (date-aware local offset).
#
# `_local_offset_ms` used `printf '%(%z)T' -1`, i.e. the offset RIGHT NOW, for
# every conversion, so in any DST zone a January date was converted with the
# July offset and back. FPC asks for the offset OF THE VALUE
# (GetLocalTimeOffset(AValue, AInputIsUTC)).
#
# The review could not reproduce it: this host is +0300 with no DST and MSYS2
# has no tzdata. It does not need any — bash's `printf '%(%z)T' <epoch>` parses
# a POSIX TZ string itself, so `TZ=EST5EDT,M3.2.0,M11.1.0` gives -0500 for a
# January epoch and -0400 for a July one with no zoneinfo files at all. That is
# what this file uses; the first assertion proves the mechanism before the rest
# relies on it.
#
# R7 also says `now`/`today` are unchanged: they ARE the current instant, so the
# current offset is the right one for them.
#
# Sourcing this unit in a child shell costs ~15 s (kklass builds a 185-member
# class), so all the assertions for one zone are collected in ONE child that
# prints `key<TAB>value` lines, and the checks below read them back.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_LocalOffset" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/dateutils.sh"
source "$UNIT"

# A POSIX TZ with DST, and one without, neither needing tzdata.
DSTZONE='EST5EDT,M3.2.0,M11.1.0'
FIXZONE='XXX-3'                       # a fixed +03:00 zone, no DST

JAN=1768478400000     # 2026-01-15 12:00:00.000
JUL=1784116800000     # 2026-07-15 12:00:00.000
JAN_S=$(( JAN / 1000 ))
JUL_S=$(( JUL / 1000 ))

# The probe: one child shell per zone. `fmt` turns a KDT into a readable
# datetime through the unit's own formatter; every direct call is followed by
# $RESULT, because a direct call is silent by contract (D3).
PROBE='
fmt() { dateutils._fmt_datetime "$1"; printf "%s" "$REPLY"; }
emit() { printf "%s\t%s\n" "$1" "$2"; }

dateutils.dateToISO8601 '"$JAN"' false >/dev/null; emit iso_jan "$RESULT"
dateutils.dateToISO8601 '"$JUL"' false >/dev/null; emit iso_jul "$RESULT"

dateutils.universalTimeToLocal '"$JAN"' >/dev/null; emit u2l_jan "$(fmt "$RESULT")"
dateutils.universalTimeToLocal '"$JUL"' >/dev/null; emit u2l_jul "$(fmt "$RESULT")"

dateutils.localTimeToUniversal '"$JAN"' >/dev/null; emit l2u_jan "$(fmt "$RESULT")"
dateutils.localTimeToUniversal '"$JUL"' >/dev/null; emit l2u_jul "$(fmt "$RESULT")"

dateutils.unixToDateTime '"$JAN_S"' false >/dev/null; emit u2d_jan "$(fmt "$RESULT")"
dateutils.unixToDateTime '"$JUL_S"' false >/dev/null; emit u2d_jul "$(fmt "$RESULT")"

dateutils.dateTimeToUnix '"$JAN"' false >/dev/null; emit d2u_jan "$RESULT"
dateutils.dateTimeToUnix '"$JUL"' false >/dev/null; emit d2u_jul "$RESULT"

dateutils.tryISO8601ToDate "2026-01-15T12:00:00.000Z" false >/dev/null; emit iso2l_jan "$(fmt "$RESULT")"
dateutils.tryISO8601ToDate "2026-07-15T12:00:00.000Z" false >/dev/null; emit iso2l_jul "$(fmt "$RESULT")"

# now/today keep using the CURRENT offset (R7).
dateutils.nowUTC >/dev/null; u=$RESULT
dateutils.now    >/dev/null; n=$RESULT
printf -v z "%(%z)T" -1
off=$(( (10#${z:1:2}*3600 + 10#${z:3:2}*60) * 1000 ))
[[ "${z:0:1}" == "-" ]] && off=$(( -off ))
d=$(( n - u - off )); (( d < 0 )) && d=$(( -d ))
emit now_offset_delta "$d"
dateutils.today >/dev/null; t=$RESULT
if (( t % 86400000 == 0 && n >= t && n < t + 86400000 )); then emit today_ok yes; else emit today_ok "t=$t n=$n"; fi

# The whole path is fork-free: no external process, no $( ) (kcl/README.md 1.8).
( PATH=""; dateutils.dateToISO8601 '"$JAN"' false >/dev/null; printf "nopath\t%s\n" "$RESULT" )
'

probe_zone() {   # TZ -> fills the global assoc array Z
    local tz="$1" key val
    Z=()
    while IFS=$'\t' read -r key val; do
        [[ -n "$key" ]] && Z[$key]="$val"
    done < <(TZ="$tz" bash -c "source '$UNIT'
$PROBE" 2>&1)
}

declare -A Z

kt_test_start "bash printf '%(%z)T' is date-aware under a POSIX TZ (no tzdata needed)"
got="$(TZ="$DSTZONE" bash -c "printf '%(%z)T %(%z)T' $JAN_S $JUL_S")"
if [[ "$got" == "-0500 -0400" ]]; then
    kt_test_pass "January -0500, July -0400"
else
    kt_test_fail "got '$got', expected '-0500 -0400' — the rest of this file assumes it"
fi

probe_zone "$DSTZONE"

pair() {   # TITLE KEY_JAN KEY_JUL WANT_JAN WANT_JUL
    kt_test_start "$1"
    if [[ "${Z[$2]:-}" == "$4" && "${Z[$3]:-}" == "$5" ]]; then
        kt_test_pass "jan='${Z[$2]}' jul='${Z[$3]}'"
    else
        kt_test_fail "jan='${Z[$2]:-<missing>}' (want '$4'), jul='${Z[$3]:-<missing>}' (want '$5')"
    fi
}

# --- 1. dateToISO8601 stamps the offset OF THE DATE [G3-05] -----------------
pair "dateToISO8601 uses the offset of the value, not of today [G3-05]" \
     iso_jan iso_jul \
     "2026-01-15T12:00:00.000-05:00" "2026-07-15T12:00:00.000-04:00"

# --- 2. universalTimeToLocal / localTimeToUniversal [G3-05] -----------------
pair "universalTimeToLocal applies the offset in force at that instant [G3-05]" \
     u2l_jan u2l_jul \
     "2026-01-15 07:00:00.000" "2026-07-15 08:00:00.000"
pair "localTimeToUniversal applies the offset in force at that instant [G3-05]" \
     l2u_jan l2u_jul \
     "2026-01-15 17:00:00.000" "2026-07-15 16:00:00.000"

# --- 3. unixToDateTime / dateTimeToUnix with utc=false [G3-05] --------------
pair "unixToDateTime utc=false uses the offset at that Unix time [G3-05]" \
     u2d_jan u2d_jul \
     "2026-01-15 07:00:00.000" "2026-07-15 08:00:00.000"
pair "dateTimeToUnix utc=false uses the offset at that local time [G3-05]" \
     d2u_jan d2u_jul \
     "$(( JAN_S + 5*3600 ))" "$(( JUL_S + 4*3600 ))"

# --- 4. tryISO8601ToDate with returnUTC=false [G3-05] -----------------------
pair "tryISO8601ToDate returnUTC=false converts with the date's offset [G3-05]" \
     iso2l_jan iso2l_jul \
     "2026-01-15 07:00:00.000" "2026-07-15 08:00:00.000"

# --- 5. now/today keep using the CURRENT offset [R7] ------------------------
kt_test_start "now() still equals nowUTC() + the offset in force right now [R7]"
if [[ "${Z[now_offset_delta]:-}" =~ ^[0-9]+$ ]] && (( ${Z[now_offset_delta]} <= 2000 )); then
    kt_test_pass "now() - nowUTC() == the current offset (delta ${Z[now_offset_delta]} ms)"
else
    kt_test_fail "delta='${Z[now_offset_delta]:-<missing>}'"
fi

kt_test_start "today() is midnight of the local day containing now() [R7]"
if [[ "${Z[today_ok]:-}" == "yes" ]]; then
    kt_test_pass "today() is the local midnight containing now()"
else
    kt_test_fail "${Z[today_ok]:-<missing>}"
fi

# --- 6. The offset is still read without a fork [1.8, D3] -------------------
kt_test_start "the local offset is computed with no external process [1.8, D3]"
if [[ "${Z[nopath]:-}" == "2026-01-15T12:00:00.000-05:00" ]]; then
    kt_test_pass "direct call under PATH='': ${Z[nopath]}"
else
    kt_test_fail "got '${Z[nopath]:-<missing>}' with an empty PATH"
fi

# --- 7. A zone without DST answers the same for January and July [R7] -------
probe_zone "$FIXZONE"
pair "a fixed-offset zone gives the same answer for January and July [R7]" \
     iso_jan iso_jul \
     "2026-01-15T12:00:00.000+03:00" "2026-07-15T12:00:00.000+03:00"
pair "... and so does the UTC->local conversion [R7]" \
     u2l_jan u2l_jul \
     "2026-01-15 15:00:00.000" "2026-07-15 15:00:00.000"
