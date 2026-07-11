#!/bin/bash

# ===========================================================================
# dateutils — a bash port of Free Pascal's DateUtils unit (kcl static class).
#
# Source of truth:
#   C:/projects/KKMindWave/VendorsCore/fpc/sources/main/packages/rtl-objpas/
#   src/inc/dateutil.inc
# Plan / ledger: kcl/dateutils/PLAN.md, kcl/dateutils/dateutils_ledger.json
#
# ---- The KDT representation ------------------------------------------------
# FPC's TDateTime is a Double (days since 1899-12-30, time = day fraction).
# Bash has no floating point, so this port uses:
#
#     KDT (KDateTime) = integer milliseconds since 1970-01-01 00:00:00,
#     naive (no timezone), proleptic Gregorian calendar.
#
# A plain 64-bit bash integer: exact $(( )) arithmetic, negatives = pre-1970
# (works past 1899-12-30 = -2209161600000). Millisecond resolution matches the
# finest unit the FPC API exposes. Calendar math uses the Hinnant civil
# algorithms (pure integer, correct for all years). Wall clock comes from the
# EPOCHREALTIME builtin and the local offset from printf '%(%z)T' — NO `date`
# forks anywhere on the hot paths.
#
# ---- Class shape / performance ---------------------------------------------
# Pascal DSL static utility class (same pattern as tpath/tfile): the class
# STRUCTURE first, method BODIES as real bash functions, then `build dateutils`.
# Every member is `static` — no per-instance state — so the API stays
# `dateutils.<Method>`.
#
# The class declares NO `static var`, so every method gets the thin,
# capture-free dispatcher (fast on bash 5.2 and 5.3 alike). Constants are
# therefore NOT class members but top-level variables. Bash has no file scope,
# so a top-level variable is a process-wide global — hence the `__KDT_` prefix
# and `readonly` (behind the re-source guard). The public way to read them is
# the dateutils.msPer*/approx* getters (FPC exposes the same constants). See
# PLAN.md "Why not a TDateUtils class with static var constants".
#
# Internal helpers (dateutils._days_from_civil, _civil_from_days, _split_kdt,
# _join_kdt, _parse_iso, ...) are plain functions, NOT class members: they set
# well-known scratch globals (REPLY, __kdt_*) and rely on bash dynamic scoping
# so callers read them back through their own `local` declarations with zero
# subshells.
# ===========================================================================

# Re-source guard: the __KDT_* constants below are readonly, and the class only
# needs to be built once per process.
if [[ -n "$_DATEUTILS_SOURCED" ]]; then
    return
fi
declare -g _DATEUTILS_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
DATEUTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DATEUTILS_DIR/../../kklass/kklass_pascal.sh"

# ---- KDT constants (readonly, __KDT_-prefixed process globals) --------------
# All millisecond counts. The two "approx" values mirror FPC's ApproxDaysPer*
# (365.25 / 30.4375 days) used by the approximate yearsBetween/monthsBetween.
__KDT_MS_PER_SECOND=1000
__KDT_MS_PER_MINUTE=60000
__KDT_MS_PER_HOUR=3600000
__KDT_MS_PER_DAY=86400000
__KDT_MS_PER_WEEK=604800000
__KDT_APPROX_MS_PER_MONTH=2629800000    # 30.4375 days
__KDT_APPROX_MS_PER_YEAR=31557600000    # 365.25  days
# FPC ApproxDaysPerMonth / ApproxDaysPerYear as decimal strings (getters only).
__KDT_APPROX_DAYS_PER_MONTH='30.4375'
__KDT_APPROX_DAYS_PER_YEAR='365.25'

readonly __KDT_MS_PER_SECOND __KDT_MS_PER_MINUTE __KDT_MS_PER_HOUR \
         __KDT_MS_PER_DAY __KDT_MS_PER_WEEK __KDT_APPROX_MS_PER_MONTH \
         __KDT_APPROX_MS_PER_YEAR __KDT_APPROX_DAYS_PER_MONTH \
         __KDT_APPROX_DAYS_PER_YEAR

# ---------------------------------------------------------------------------
# Class interface (grows per implementation phase; P0 = core only).
# ---------------------------------------------------------------------------
class dateutils
    public
        # wall clock & trivial constructors
        static proc now
        static proc nowUTC
        static proc today
        static proc yesterday
        static proc tomorrow
        static proc dateOf
        static proc timeOf
        # public constant getters (FPC exposes the same constants)
        static proc msPerSecond
        static proc msPerMinute
        static proc msPerHour
        static proc msPerDay
        static proc msPerWeek
        static proc approxMsPerMonth
        static proc approxMsPerYear
        static proc approxDaysPerMonth
        static proc approxDaysPerYear
        # --- P1: encode / decode ---
        static proc encodeDate
        static proc encodeTime
        static proc encodeDateTime
        static proc tryEncodeDate
        static proc tryEncodeTime
        static proc tryEncodeDateTime
        static proc decodeDate
        static proc decodeTime
        static proc decodeDateTime
        static proc encodeDateDay
        static proc tryEncodeDateDay
        static proc decodeDateDay
        # --- P1: validity & calendar sizes ---
        static proc isValidDate
        static proc isValidTime
        static proc isValidDateTime
        static proc isValidDateDay
        static proc isValidDateWeek
        static proc isValidDateMonthWeek
        static proc isInLeapYear
        static proc daysInAMonth
        static proc daysInMonth
        static proc daysInAYear
        static proc daysInYear
        static proc weeksInAYear
        static proc weeksInYear
        # --- P2: simple field extractors ---
        static proc yearOf
        static proc monthOf
        static proc weekOf
        static proc dayOf
        static proc hourOf
        static proc minuteOf
        static proc secondOf
        static proc milliSecondOf
        static proc dayOfTheWeek
        static proc dayOfTheMonth
        static proc dayOfTheYear
        static proc monthOfTheYear
        static proc weekOfTheYear
        static proc weekOfTheMonth
        static proc isAM
        static proc isPM
        # --- P2: OfThe* families ---
        static proc hourOfTheDay
        static proc minuteOfTheHour
        static proc secondOfTheMinute
        static proc milliSecondOfTheSecond
        static proc minuteOfTheDay
        static proc secondOfTheDay
        static proc milliSecondOfTheDay
        static proc secondOfTheHour
        static proc milliSecondOfTheHour
        static proc milliSecondOfTheMinute
        static proc hourOfTheWeek
        static proc minuteOfTheWeek
        static proc secondOfTheWeek
        static proc milliSecondOfTheWeek
        static proc hourOfTheMonth
        static proc minuteOfTheMonth
        static proc secondOfTheMonth
        static proc milliSecondOfTheMonth
        static proc hourOfTheYear
        static proc minuteOfTheYear
        static proc secondOfTheYear
        static proc milliSecondOfTheYear
        static proc nthDayOfWeek
        static proc decodeDayOfWeekInMonth
        # --- P3: start/end of period + day predicates ---
        static proc startOfTheYear
        static proc startOfAYear
        static proc endOfTheYear
        static proc endOfAYear
        static proc startOfTheMonth
        static proc startOfAMonth
        static proc endOfTheMonth
        static proc endOfAMonth
        static proc startOfTheWeek
        static proc startOfAWeek
        static proc endOfTheWeek
        static proc endOfAWeek
        static proc startOfTheDay
        static proc startOfADay
        static proc endOfTheDay
        static proc endOfADay
        static proc isToday
        static proc isSameDay
        static proc isSameMonth
        static proc previousDayOfWeek
        # --- P4: increment ---
        static proc incYear
        static proc incMonth
        static proc incWeek
        static proc incDay
        static proc incHour
        static proc incMinute
        static proc incSecond
        static proc incMilliSecond
        # --- P4: between / period / span / diff ---
        static proc yearsBetween
        static proc monthsBetween
        static proc weeksBetween
        static proc daysBetween
        static proc hoursBetween
        static proc minutesBetween
        static proc secondsBetween
        static proc milliSecondsBetween
        static proc periodBetween
        static proc dateTimeDiff
        static proc yearSpan
        static proc monthSpan
        static proc weekSpan
        static proc daySpan
        static proc hourSpan
        static proc minuteSpan
        static proc secondSpan
        static proc milliSecondSpan
        # --- P4: within-past / compare / same / range ---
        static proc withinPastYears
        static proc withinPastMonths
        static proc withinPastWeeks
        static proc withinPastDays
        static proc withinPastHours
        static proc withinPastMinutes
        static proc withinPastSeconds
        static proc withinPastMilliSeconds
        static proc compareDateTime
        static proc compareDate
        static proc compareTime
        static proc sameDateTime
        static proc sameDate
        static proc sameTime
        static proc dateInRange
        static proc timeInRange
        static proc dateTimeInRange
        # --- P5: recode (field surgery; '-' = leave as is) ---
        static proc recodeYear
        static proc recodeMonth
        static proc recodeDay
        static proc recodeHour
        static proc recodeMinute
        static proc recodeSecond
        static proc recodeMilliSecond
        static proc recodeDate
        static proc recodeTime
        static proc recodeDateTime
        static proc tryRecodeDateTime
        # --- P5: week-date and day-of-week-in-month encodings ---
        static proc encodeDateWeek
        static proc tryEncodeDateWeek
        static proc decodeDateWeek
        static proc encodeDateMonthWeek
        static proc tryEncodeDateMonthWeek
        static proc decodeDateMonthWeek
        static proc encodeDayOfWeekInMonth
        static proc tryEncodeDayOfWeekInMonth
        # --- P6: Unix / Julian conversions ---
        static proc dateTimeToUnix
        static proc unixToDateTime
        static proc dateTimeToJulianDate
        static proc julianDateToDateTime
        static proc tryJulianDateToDateTime
        static proc dateTimeToModifiedJulianDate
        static proc modifiedJulianDateToDateTime
        static proc tryModifiedJulianDateToDateTime
        # --- P6: local<->UTC + time intervals ---
        static proc localTimeToUniversal
        static proc universalTimeToLocal
        static proc encodeTimeInterval
        static proc tryEncodeTimeInterval
        # --- P6: ISO 8601 strings + timezone offsets ---
        static proc dateToISO8601
        static proc iso8601ToDate
        static proc iso8601ToDateDef
        static proc tryISO8601ToDate
        static proc tryISOStrToDate
        static proc tryISOStrToTime
        static proc tryISOStrToDateTime
        static proc isoTZStrToTZOffset
        static proc tryISOTZStrToTZOffset
        # --- P7: practical scanner ---
        static proc scanDateTime
end

# ===========================================================================
# Internal helpers (plain functions, NOT class members). They return through
# scratch globals: REPLY (single value) or __kdt_* (multi-field), consumed by
# the caller's `local` of the same name (bash dynamic scoping — zero subshells).
# ===========================================================================

# --- Civil calendar (Howard Hinnant's algorithms) --------------------------
# Both are written for C-style truncated-toward-zero division, which is exactly
# what bash $(( )) does — so the `(y >= 0 ? y : y-399)` style floor tricks port
# verbatim and stay correct for negative (pre-Gregorian-epoch) years.

# _days_from_civil Y M D -> REPLY = days since 1970-01-01 (day 0 = Thu).
dateutils._days_from_civil() {
    local y=$1 m=$2 d=$3 era yoe doy doe
    (( y -= (m <= 2) ))
    if (( y >= 0 )); then era=$(( y / 400 )); else era=$(( (y - 399) / 400 )); fi
    yoe=$(( y - era * 400 ))                     # [0, 399]
    if (( m > 2 )); then
        doy=$(( (153 * (m - 3) + 2) / 5 + d - 1 ))
    else
        doy=$(( (153 * (m + 9) + 2) / 5 + d - 1 ))
    fi
    doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
    REPLY=$(( era * 146097 + doe - 719468 ))
}

# _civil_from_days Z -> sets __kdt_y __kdt_mo __kdt_d  (Z = days since 1970).
dateutils._civil_from_days() {
    local z=$(( $1 + 719468 )) era doe yoe doy mp
    if (( z >= 0 )); then era=$(( z / 146097 )); else era=$(( (z - 146096) / 146097 )); fi
    doe=$(( z - era * 146097 ))                  # [0, 146096]
    yoe=$(( (doe - doe/1460 + doe/36524 - doe/146096) / 365 ))   # [0, 399]
    __kdt_y=$(( yoe + era * 400 ))
    doy=$(( doe - (365*yoe + yoe/4 - yoe/100) )) # [0, 365]
    mp=$(( (5*doy + 2) / 153 ))                  # [0, 11]
    __kdt_d=$(( doy - (153*mp + 2)/5 + 1 ))      # [1, 31]
    if (( mp < 10 )); then __kdt_mo=$(( mp + 3 )); else __kdt_mo=$(( mp - 9 )); fi
    (( __kdt_mo <= 2 )) && (( __kdt_y += 1 ))
}

# _split_kdt KDT -> sets __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms.
dateutils._split_kdt() {
    local kdt=$1 total_days ms_of_day rem
    total_days=$(( kdt / 86400000 ))
    ms_of_day=$(( kdt - total_days * 86400000 ))
    if (( ms_of_day < 0 )); then                 # floor division for pre-1970
        ms_of_day=$(( ms_of_day + 86400000 ))
        total_days=$(( total_days - 1 ))
    fi
    dateutils._civil_from_days "$total_days"     # -> __kdt_y __kdt_mo __kdt_d
    __kdt_h=$(( ms_of_day / 3600000 ))
    rem=$(( ms_of_day % 3600000 ))
    __kdt_mi=$(( rem / 60000 ))
    rem=$(( rem % 60000 ))
    __kdt_s=$(( rem / 1000 ))
    __kdt_ms=$(( rem % 1000 ))
}

# _join_kdt Y M D h m s ms -> REPLY = KDT.
dateutils._join_kdt() {
    local y=$1 mo=$2 d=$3 h=$4 mi=$5 s=$6 ms=$7
    dateutils._days_from_civil "$y" "$mo" "$d"   # -> REPLY = days
    REPLY=$(( REPLY * 86400000 + h*3600000 + mi*60000 + s*1000 + ms ))
}

# _weekday_iso KDT -> REPLY = ISO weekday (Mon=1 .. Sun=7). Day 0 = Thursday(4).
dateutils._weekday_iso() {
    local kdt=$1 total_days
    total_days=$(( kdt / 86400000 ))
    (( kdt - total_days*86400000 < 0 )) && total_days=$(( total_days - 1 ))
    REPLY=$(( ( (total_days + 3) % 7 + 7 ) % 7 + 1 ))
}

# --- ISO 8601 format / parse ------------------------------------------------
# Canonical forms: date "YYYY-MM-DD", time "hh:mm:ss.zzz", datetime joined by a
# single space. _parse_iso accepts a 'T' or ' ' separator, optional seconds/ms,
# and an optional trailing zone (Z or ±hh[:]mm) captured for P6 (naive in P0).

# _fmt_date KDT -> REPLY "YYYY-MM-DD".
dateutils._fmt_date() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"
    printf -v REPLY '%04d-%02d-%02d' "$__kdt_y" "$__kdt_mo" "$__kdt_d"
}

# _fmt_time KDT -> REPLY "hh:mm:ss.zzz".
dateutils._fmt_time() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"
    printf -v REPLY '%02d:%02d:%02d.%03d' "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
}

# _fmt_datetime KDT -> REPLY "YYYY-MM-DD hh:mm:ss.zzz".
dateutils._fmt_datetime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"
    printf -v REPLY '%04d-%02d-%02d %02d:%02d:%02d.%03d' \
        "$__kdt_y" "$__kdt_mo" "$__kdt_d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
}

# _parse_iso STRING -> REPLY = KDT; also sets __kdt_has_tz / __kdt_tzoff_min.
# Returns 1 (echo nothing) on malformed input or out-of-range fields.
dateutils._parse_iso() {
    local s="$1"
    local re='^([0-9]{4})-([0-9]{2})-([0-9]{2})([T ]([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.([0-9]{1,3}))?)?)?(Z|([+-])([0-9]{2}):?([0-9]{2}))?$'
    [[ "$s" =~ $re ]] || return 1
    local y=$((10#${BASH_REMATCH[1]})) mo=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]}))
    local h=$((10#${BASH_REMATCH[5]:-0})) mi=$((10#${BASH_REMATCH[6]:-0})) sec=$((10#${BASH_REMATCH[8]:-0}))
    local msraw="${BASH_REMATCH[10]:-}" ms=0
    if [[ -n "$msraw" ]]; then msraw="${msraw}000"; ms=$(( 10#${msraw:0:3} )); fi
    # Range check (light — full per-month validity is P1's isValidDate).
    (( mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && h <= 23 && mi <= 59 && sec <= 59 )) || return 1
    # Timezone capture (not applied here; P6 conversions consume it).
    __kdt_has_tz=0; __kdt_tzoff_min=0
    if [[ -n "${BASH_REMATCH[11]}" ]]; then
        __kdt_has_tz=1
        if [[ "${BASH_REMATCH[11]}" != "Z" ]]; then
            __kdt_tzoff_min=$(( 10#${BASH_REMATCH[13]}*60 + 10#${BASH_REMATCH[14]} ))
            [[ "${BASH_REMATCH[12]}" == "-" ]] && __kdt_tzoff_min=$(( -__kdt_tzoff_min ))
        fi
    fi
    dateutils._join_kdt "$y" "$mo" "$d" "$h" "$mi" "$sec" "$ms"   # -> REPLY
}

# --- Wall clock (zero forks) ------------------------------------------------

# _now_utc_ms -> REPLY = UTC wall clock in ms (Unix time, naive).
dateutils._now_utc_ms() {
    local er="${EPOCHREALTIME}" secs frac
    if [[ -z "$er" ]]; then                      # fallback for bash < 5.0
        printf -v er '%(%s)T' -1
        REPLY=$(( er * 1000 ))
        return
    fi
    if [[ "$er" == *[.,]* ]]; then
        secs="${er%[.,]*}"; frac="${er##*[.,]}"
    else
        secs="$er"; frac="000000"
    fi
    REPLY=$(( secs * 1000 + 10#${frac:0:6} / 1000 ))
}

# _local_offset_ms -> REPLY = local offset EAST of UTC in ms (from %(%z)T).
dateutils._local_offset_ms() {
    local z sign hh mm secs
    printf -v z '%(%z)T' -1                       # e.g. +0300 / -0500
    sign="${z:0:1}"; hh="${z:1:2}"; mm="${z:3:2}"
    secs=$(( 10#$hh * 3600 + 10#$mm * 60 ))
    [[ "$sign" == "-" ]] && secs=$(( -secs ))
    REPLY=$(( secs * 1000 ))
}

# _now_local_ms -> REPLY = local naive now in ms.
dateutils._now_local_ms() {
    local u off
    dateutils._now_utc_ms;      u=$REPLY
    dateutils._local_offset_ms; off=$REPLY
    REPLY=$(( u + off ))
}

# _floor_day KDT -> REPLY = day number (floor(KDT / MS_PER_DAY)).
dateutils._floor_day() {
    local kdt=$1 d=$(( $1 / 86400000 ))
    (( kdt - d*86400000 < 0 )) && d=$(( d - 1 ))
    REPLY=$d
}

# --- calendar predicates / sizes (used by P1 validity & encode) -------------

# _is_leap YEAR -> REPLY = 1 (leap) / 0. Proleptic Gregorian, matches SysUtils.
dateutils._is_leap() {
    local y=$1
    if (( y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) )); then REPLY=1; else REPLY=0; fi
}

# _days_in_month YEAR MONTH -> REPLY = day count (0 for an invalid month).
dateutils._days_in_month() {
    case "$2" in
        1|3|5|7|8|10|12) REPLY=31 ;;
        4|6|9|11)        REPLY=30 ;;
        2)               dateutils._is_leap "$1"; REPLY=$(( 28 + REPLY )) ;;
        *)               REPLY=0 ;;
    esac
}

# _weeks_in_year YEAR -> REPLY = 52 or 53 (ISO-8601). FPC WeeksInAYear: 52, +1
# if Jan 1 is Thursday, or Wednesday in a leap year.
dateutils._weeks_in_year() {
    local y=$1 dow leap days
    dateutils._days_from_civil "$y" 1 1; days=$REPLY
    dow=$(( ( (days + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of Jan 1
    dateutils._is_leap "$y"; leap=$REPLY
    if (( dow == 4 || (dow == 3 && leap) )); then REPLY=53; else REPLY=52; fi
}

# _valid_date YEAR MONTH DAY -> REPLY = 1/0 (FPC IsValidDate: year 1..9999).
dateutils._valid_date() {
    local y=$1 m=$2 d=$3
    REPLY=0
    (( y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 )) || return
    dateutils._days_in_month "$y" "$m"
    (( d <= REPLY )) && REPLY=1 || REPLY=0
}

# _valid_time HOUR MIN SEC MS -> REPLY = 1/0. FPC IsValidTime: 24:00:00.000 is
# valid (whole-day marker), else h<24 & m<60 & s<60 & ms<1000.
dateutils._valid_time() {
    local h=$1 mi=$2 s=$3 ms=$4
    if (( h == 24 && mi == 0 && s == 0 && ms == 0 )) || \
       (( h >= 0 && h < 24 && mi >= 0 && mi < 60 && s >= 0 && s < 60 && ms >= 0 && ms < 1000 )); then
        REPLY=1
    else
        REPLY=0
    fi
}

# _debug MSG -> stderr, only under VERBOSE_KKLASS=debug (encode* error channel).
dateutils._debug() { [[ "$VERBOSE_KKLASS" == debug ]] && echo "dateutils: $*" >&2; return 0; }

# _decode_date_week KDT -> __kdt_wy_year __kdt_wy_week __kdt_wy_dow (ISO-8601).
# Faithful port of FPC DecodeDateWeek (recurses once into the prior year for
# early-January days that belong to the last ISO week of the previous year).
dateutils._decode_date_week() {
    local kdt=$1
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$kdt"
    local year=$__kdt_y dow ys_day doy ysdow week yedow leap
    dateutils._weekday_iso "$kdt"; dow=$REPLY
    dateutils._days_from_civil "$year" 1 1; ys_day=$REPLY
    dateutils._floor_day "$kdt"; doy=$(( REPLY - ys_day + 1 ))
    ysdow=$(( ( (ys_day + 3) % 7 + 7 ) % 7 + 1 ))       # ISO weekday of Jan 1
    if (( ysdow < 5 )); then doy=$(( doy + ysdow - 1 )); else doy=$(( doy - (8 - ysdow) )); fi
    if (( doy <= 0 )); then                              # last week of previous year
        dateutils._decode_date_week "$(( (ys_day - 1) * 86400000 ))"
        __kdt_wy_dow=$dow
        return
    fi
    week=$(( doy / 7 )); (( doy % 7 != 0 )) && week=$(( week + 1 ))
    if (( week > 52 )); then                             # maybe first week of next year
        yedow=$ysdow
        dateutils._is_leap "$year"; leap=$REPLY
        if (( leap )); then yedow=$(( yedow + 1 )); (( yedow > 7 )) && yedow=1; fi
        if (( yedow < 4 )); then year=$(( year + 1 )); week=1; fi
    fi
    __kdt_wy_year=$year; __kdt_wy_week=$week; __kdt_wy_dow=$dow
}

# _decode_date_month_week KDT -> __kdt_mw_year __kdt_mw_month __kdt_mw_week
# __kdt_mw_dow. Faithful port of FPC DecodeDateMonthWeek.
dateutils._decode_date_month_week() {
    local kdt=$1
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$kdt"
    local year=$__kdt_y month=$__kdt_mo d=$__kdt_d dow som_day sdom dom week dim eom_day edom
    dateutils._weekday_iso "$kdt"; dow=$REPLY
    dateutils._days_from_civil "$year" "$month" 1; som_day=$REPLY
    sdom=$(( ( (som_day + 3) % 7 + 7 ) % 7 + 1 ))        # ISO weekday of the 1st
    dom=$(( d - 1 + sdom )); (( sdom > 4 )) && dom=$(( dom - 7 ))
    if (( dom <= 0 )); then                              # belongs to previous month
        dateutils._decode_date_month_week "$(( (som_day - 1) * 86400000 ))"
        __kdt_mw_dow=$dow
        return
    fi
    week=$(( dom / 7 )); (( dom % 7 != 0 )) && week=$(( week + 1 ))
    dateutils._days_in_month "$year" "$month"; dim=$REPLY
    dateutils._days_from_civil "$year" "$month" "$dim"; eom_day=$REPLY
    edom=$(( ( (eom_day + 3) % 7 + 7 ) % 7 + 1 ))        # ISO weekday of the last day
    if (( edom < 4 && (dim - d) < edom )); then          # tail days spill into next month
        week=1; month=$(( month + 1 ))
        (( month == 13 )) && { month=1; year=$(( year + 1 )); }
    fi
    __kdt_mw_year=$year; __kdt_mw_month=$month; __kdt_mw_week=$week; __kdt_mw_dow=$dow
}

# _encode_date_week YEAR WEEK DOW -> REPLY = KDT at 00:00; return 1 if the
# (year, week, dow) triple is invalid. Faithful port of FPC TryEncodeDateWeek;
# reused by startOfAWeek/endOfAWeek (P3) and encodeDateWeek/decodeDateWeek (P5).
dateutils._encode_date_week() {
    local y=$1 w=$2 dow=$3 base dowb rest
    dateutils._weeks_in_year "$y"
    (( y >= 1 && y <= 9999 && dow >= 1 && dow <= 7 && w >= 1 && w <= REPLY )) || return 1
    dateutils._days_from_civil "$y" 1 1
    base=$(( REPLY + 7*(w-1) ))
    dowb=$(( ( (base + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of that Monday-anchor
    rest=$(( dow - dowb )); (( dowb > 4 )) && rest=$(( rest + 7 ))
    REPLY=$(( (base + rest) * 86400000 ))
}

# _period_between NOW THEN -> __kdt_pb_y __kdt_pb_m __kdt_pb_d (calendar
# decomposition of |NOW-THEN|, date parts only). Faithful port of FPC
# PeriodBetween with its month/day borrow logic.
dateutils._period_between() {
    local lo hi
    if (( $2 > $1 )); then lo=$1; hi=$2; else lo=$2; hi=$1; fi
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$lo"; local y1=$__kdt_y m1=$__kdt_mo d1=$__kdt_d
    dateutils._split_kdt "$hi"; local y2=$__kdt_y m2=$__kdt_mo d2=$__kdt_d
    local years=$(( y2 - y1 )) months days
    if (( m1 > m2 || (m1 == m2 && d1 > d2) )); then years=$(( years - 1 )); fi
    (( m1 > m2 )) && m2=$(( m2 + 12 ))
    months=$(( m2 - m1 ))
    if (( d2 >= d1 )); then
        days=$(( d2 - d1 ))
    else
        if (( months == 0 )); then months=11; else months=$(( months - 1 )); fi
        dateutils._days_in_month "$y1" "$m1"       # DaysInAMonth(Y1,M1)
        days=$(( (REPLY - d1) + d2 ))
    fi
    __kdt_pb_y=$years; __kdt_pb_m=$months; __kdt_pb_d=$days
}

# _span_fixed ABSDIFF_MS DIVISOR_MS -> REPLY = "whole.ffffff" (6 dp), computed
# whole/remainder-wise so ABSDIFF*10^6 never overflows int64 (plan risk #3).
dateutils._span_fixed() {
    local n=$1 div=$2 whole frac
    whole=$(( n / div ))
    frac=$(( (n % div) * 1000000 / div ))
    printf -v REPLY '%d.%06d' "$whole" "$frac"
}

# _recode DT Y M D H N S MS -> REPLY = KDT, return 1 if invalid. Any field equal
# to the literal '-' (RecodeLeaveFieldAsIs) keeps the original. FPC TryRecodeDateTime.
dateutils._recode() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"
    local y=$__kdt_y m=$__kdt_mo d=$__kdt_d h=$__kdt_h n=$__kdt_mi s=$__kdt_s ms=$__kdt_ms
    [[ "$2" != - ]] && y=$2;  [[ "$3" != - ]] && m=$3;  [[ "$4" != - ]] && d=$4
    [[ "$5" != - ]] && h=$5;  [[ "$6" != - ]] && n=$6;  [[ "$7" != - ]] && s=$7;  [[ "$8" != - ]] && ms=$8
    dateutils._valid_date "$y" "$m" "$d"; (( REPLY )) || return 1
    dateutils._valid_time "$h" "$n" "$s" "$ms"; (( REPLY )) || return 1
    dateutils._join_kdt "$y" "$m" "$d" "$h" "$n" "$s" "$ms"
}

# _encode_date_month_week YEAR MONTH WEEKOFMONTH DOW -> REPLY = KDT@00:00,
# return 1 if invalid. Faithful port of FPC TryEncodeDateMonthWeek (the result
# may fall in an adjacent month — FPC only range-checks the inputs).
dateutils._encode_date_month_week() {
    local y=$1 mo=$2 wom=$3 dow=$4 base dom s
    (( y >= 1 && y <= 9999 && mo >= 1 && mo <= 12 && wom >= 1 && wom <= 5 && dow >= 1 && dow <= 7 )) || return 1
    dateutils._days_from_civil "$y" "$mo" 1; base=$REPLY
    dom=$(( (wom-1)*7 + dow - 1 ))
    s=$(( ( (base + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of the 1st
    dom=$(( dom - (s - 1) ))
    (( s >= 5 )) && dom=$(( dom + 7 ))           # S in [Fri..Sun]
    REPLY=$(( (base + dom) * 86400000 ))
}

# _encode_dow_in_month YEAR MONTH NTH DOW -> REPLY = KDT@00:00, return 1 if the
# Nth weekday does not exist that month. Faithful port of FPC
# TryEncodeDayOfWeekInMonth. NOTE: FPC ANthDayOfWeek is Word (>=1) — there is no
# negative/"last" form (see TEST_COVERAGE_NOTES.md).
dateutils._encode_dow_in_month() {
    local y=$1 mo=$2 nth=$3 dow=$4 som d
    dateutils._days_from_civil "$y" "$mo" 1
    som=$(( ( (REPLY + 3) % 7 + 7 ) % 7 + 1 ))   # ISO weekday of the 1st
    d=$(( 1 + dow - som + 7*(nth-1) ))
    (( som > dow )) && d=$(( d + 7 ))
    dateutils._valid_date "$y" "$mo" "$d"; (( REPLY )) || return 1
    dateutils._join_kdt "$y" "$mo" "$d" 0 0 0 0
}

# _jd_str_to_ms JDSTR -> REPLY = round(JD * 86400000) as an integer numerator.
# KDT day 0 (1970-01-01) is JD 2440587.5, so JD = 2440587.5 + KDT/86400000,
# i.e. KDT = REPLY - 210866760000000 (= 2440587.5 * 86400000). Frac parsed to
# 9 digits (rounded); frac9*86400000 < 9.2e18 so no int64 overflow.
dateutils._jd_str_to_ms() {
    local s=$1 sign=1 whole frac
    [[ "$s" == -* ]] && { sign=-1; s=${s#-}; }
    [[ "$s" == +* ]] && s=${s#+}
    if [[ "$s" == *.* ]]; then whole=${s%%.*}; frac=${s#*.}; else whole=$s; frac=0; fi
    whole=${whole:-0}; frac=${frac}000000000; frac=${frac:0:9}
    REPLY=$(( sign * (10#$whole * 86400000 + (10#$frac * 86400000 + 500000000) / 1000000000) ))
}

# _normalize_offset_min_east ARG -> REPLY = minutes EAST of UTC; return 1 if bad.
# Accepts integer minutes (+/-), 'Z'/'' (0), or '±hh[:]mm' / '±hh'.
dateutils._normalize_offset_min_east() {
    local a=$1
    if [[ "$a" == Z || -z "$a" ]]; then REPLY=0; return 0; fi
    if [[ "$a" =~ ^[+-]?[0-9]+$ ]]; then REPLY=$(( a )); return 0; fi
    if [[ "$a" =~ ^([+-])([0-9]{2}):?([0-9]{2})$ ]]; then
        REPLY=$(( 10#${BASH_REMATCH[2]}*60 + 10#${BASH_REMATCH[3]} ))
        [[ "${BASH_REMATCH[1]}" == - ]] && REPLY=$(( -REPLY )); return 0
    fi
    if [[ "$a" =~ ^([+-])([0-9]{2})$ ]]; then
        REPLY=$(( 10#${BASH_REMATCH[2]}*60 ))
        [[ "${BASH_REMATCH[1]}" == - ]] && REPLY=$(( -REPLY )); return 0
    fi
    return 1
}

# ===========================================================================
# Method bodies (real bash functions; extracted by `build`). `proc`, not
# `func`: results are echoed (the kcl convention), never via RESULT.
# ===========================================================================

# --- wall clock & trivial constructors ---
dateutils.now()    { dateutils._now_local_ms; echo "$REPLY"; }
dateutils.nowUTC() { dateutils._now_utc_ms;   echo "$REPLY"; }
dateutils.today()  { dateutils._now_local_ms; dateutils._floor_day "$REPLY"; echo $(( REPLY * 86400000 )); }
dateutils.yesterday() { dateutils._now_local_ms; dateutils._floor_day "$REPLY"; echo $(( (REPLY - 1) * 86400000 )); }
dateutils.tomorrow()  { dateutils._now_local_ms; dateutils._floor_day "$REPLY"; echo $(( (REPLY + 1) * 86400000 )); }

# dateOf: drop the time-of-day (floor to midnight). timeOf: keep only it.
dateutils.dateOf() { dateutils._floor_day "$1"; echo $(( REPLY * 86400000 )); }
dateutils.timeOf() { dateutils._floor_day "$1"; echo $(( $1 - REPLY * 86400000 )); }

# --- public constant getters ---
dateutils.msPerSecond()        { echo "$__KDT_MS_PER_SECOND"; }
dateutils.msPerMinute()        { echo "$__KDT_MS_PER_MINUTE"; }
dateutils.msPerHour()          { echo "$__KDT_MS_PER_HOUR"; }
dateutils.msPerDay()           { echo "$__KDT_MS_PER_DAY"; }
dateutils.msPerWeek()          { echo "$__KDT_MS_PER_WEEK"; }
dateutils.approxMsPerMonth()   { echo "$__KDT_APPROX_MS_PER_MONTH"; }
dateutils.approxMsPerYear()    { echo "$__KDT_APPROX_MS_PER_YEAR"; }
dateutils.approxDaysPerMonth() { echo "$__KDT_APPROX_DAYS_PER_MONTH"; }
dateutils.approxDaysPerYear()  { echo "$__KDT_APPROX_DAYS_PER_YEAR"; }

# --- P1: encode / decode ---------------------------------------------------
# encode* echo the KDT (or time-of-day ms) and, on invalid input, log under
# VERBOSE_KKLASS=debug and return 1. try* are identical but silent. FPC raises
# EConvertError where we return 1 (bash has no exceptions).

dateutils.tryEncodeDate() {
    dateutils._valid_date "$1" "$2" "$3"; (( REPLY )) || return 1
    dateutils._join_kdt "$1" "$2" "$3" 0 0 0 0; echo "$REPLY"
}
dateutils.encodeDate() {
    dateutils._valid_date "$1" "$2" "$3"
    if (( REPLY )); then dateutils._join_kdt "$1" "$2" "$3" 0 0 0 0; echo "$REPLY"
    else dateutils._debug "invalid date $1-$2-$3"; return 1; fi
}

dateutils.tryEncodeTime() {
    dateutils._valid_time "$1" "$2" "$3" "$4"; (( REPLY )) || return 1
    echo $(( $1*3600000 + $2*60000 + $3*1000 + $4 ))
}
dateutils.encodeTime() {
    dateutils._valid_time "$1" "$2" "$3" "$4"
    if (( REPLY )); then echo $(( $1*3600000 + $2*60000 + $3*1000 + $4 ))
    else dateutils._debug "invalid time $1:$2:$3.$4"; return 1; fi
}

dateutils.tryEncodeDateTime() {
    dateutils._valid_date "$1" "$2" "$3"; (( REPLY )) || return 1
    dateutils._valid_time "$4" "$5" "$6" "$7"; (( REPLY )) || return 1
    dateutils._join_kdt "$1" "$2" "$3" "$4" "$5" "$6" "$7"; echo "$REPLY"
}
dateutils.encodeDateTime() {
    dateutils._valid_date "$1" "$2" "$3"; local vd=$REPLY
    dateutils._valid_time "$4" "$5" "$6" "$7"
    if (( vd && REPLY )); then
        dateutils._join_kdt "$1" "$2" "$3" "$4" "$5" "$6" "$7"; echo "$REPLY"
    else
        dateutils._debug "invalid datetime $1-$2-$3 $4:$5:$6.$7"; return 1
    fi
}

dateutils.decodeDate() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; echo "$__kdt_y $__kdt_mo $__kdt_d"
}
dateutils.decodeTime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; echo "$__kdt_h $__kdt_mi $__kdt_s $__kdt_ms"
}
dateutils.decodeDateTime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"
    echo "$__kdt_y $__kdt_mo $__kdt_d $__kdt_h $__kdt_mi $__kdt_s $__kdt_ms"
}

# encodeDateDay: date from (year, day-of-year 1..365/366). FPC's try* omits the
# year check (it raises inside EncodeDate); we treat "would-raise" as failure,
# so try* here validates year 1..9999 too (== isValidDateDay + compute).
dateutils.tryEncodeDateDay() {
    local y=$1 doy=$2 dpy
    dateutils._is_leap "$y"; dpy=$(( 365 + REPLY ))
    (( y >= 1 && y <= 9999 && doy >= 1 && doy <= dpy )) || return 1
    dateutils._days_from_civil "$y" 1 1; echo $(( (REPLY + doy - 1) * 86400000 ))
}
dateutils.encodeDateDay() {
    local y=$1 doy=$2 dpy
    dateutils._is_leap "$y"; dpy=$(( 365 + REPLY ))
    if (( y >= 1 && y <= 9999 && doy >= 1 && doy <= dpy )); then
        dateutils._days_from_civil "$y" 1 1; echo $(( (REPLY + doy - 1) * 86400000 ))
    else
        dateutils._debug "invalid date-day $y/$doy"; return 1
    fi
}
dateutils.decodeDateDay() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys
    dateutils._split_kdt "$1"
    dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"
    echo "$__kdt_y $(( REPLY - ys + 1 ))"
}

# --- P1: validity & calendar sizes -----------------------------------------
dateutils.isValidDate() { dateutils._valid_date "$1" "$2" "$3"; (( REPLY )) && echo true || echo false; }
dateutils.isValidTime() { dateutils._valid_time "$1" "$2" "$3" "$4"; (( REPLY )) && echo true || echo false; }
dateutils.isValidDateTime() {
    dateutils._valid_date "$1" "$2" "$3"; local vd=$REPLY
    dateutils._valid_time "$4" "$5" "$6" "$7"
    (( vd && REPLY )) && echo true || echo false
}
dateutils.isValidDateDay() {
    local y=$1 doy=$2 dpy
    dateutils._is_leap "$y"; dpy=$(( 365 + REPLY ))
    (( y >= 1 && y <= 9999 && doy >= 1 && doy <= dpy )) && echo true || echo false
}
dateutils.isValidDateWeek() {
    local y=$1 w=$2 dow=$3
    dateutils._weeks_in_year "$y"
    (( y >= 1 && y <= 9999 && dow >= 1 && dow <= 7 && w >= 1 && w <= REPLY )) && echo true || echo false
}
dateutils.isValidDateMonthWeek() {
    local y=$1 m=$2 wom=$3 dow=$4
    (( y >= 1 && y <= 9999 && m >= 1 && m <= 12 && wom >= 1 && wom <= 5 && dow >= 1 && dow <= 7 )) \
        && echo true || echo false
}
dateutils.isInLeapYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._is_leap "$__kdt_y"
    (( REPLY )) && echo true || echo false
}
dateutils.daysInAMonth() { dateutils._days_in_month "$1" "$2"; (( REPLY > 0 )) && echo "$REPLY" || return 1; }
dateutils.daysInMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._days_in_month "$__kdt_y" "$__kdt_mo"; echo "$REPLY"
}
dateutils.daysInAYear() { dateutils._is_leap "$1"; echo $(( 365 + REPLY )); }
dateutils.daysInYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._is_leap "$__kdt_y"; echo $(( 365 + REPLY ))
}
dateutils.weeksInAYear() { dateutils._weeks_in_year "$1"; echo "$REPLY"; }
dateutils.weeksInYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._weeks_in_year "$__kdt_y"; echo "$REPLY"
}

# --- P2: simple field extractors -------------------------------------------
dateutils.yearOf()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_y"; }
dateutils.monthOf()       { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_mo"; }
dateutils.dayOf()         { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_d"; }
dateutils.hourOf()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_h"; }
dateutils.minuteOf()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_mi"; }
dateutils.secondOf()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_s"; }
dateutils.milliSecondOf() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo "$__kdt_ms"; }
# aliases / ISO-week
dateutils.monthOfTheYear() { dateutils.monthOf "$1"; }
dateutils.dayOfTheMonth()  { dateutils.dayOf "$1"; }
dateutils.dayOfTheWeek()   { dateutils._weekday_iso "$1"; echo "$REPLY"; }   # ISO Mon=1..Sun=7
dateutils.dayOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"; echo $(( REPLY - ys + 1 ))
}
dateutils.weekOfTheYear()  { dateutils._decode_date_week "$1"; echo "$__kdt_wy_week"; }
dateutils.weekOf()         { dateutils._decode_date_week "$1"; echo "$__kdt_wy_week"; }
dateutils.weekOfTheMonth() { dateutils._decode_date_month_week "$1"; echo "$__kdt_mw_week"; }
dateutils.isAM() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; (( __kdt_h < 12 ))  && echo true || echo false; }
dateutils.isPM() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; (( __kdt_h >= 12 )) && echo true || echo false; }

# --- P2: OfThe* families (units elapsed since the start of the larger period)
# Same-unit aliases:
dateutils.hourOfTheDay()          { dateutils.hourOf "$1"; }
dateutils.minuteOfTheHour()       { dateutils.minuteOf "$1"; }
dateutils.secondOfTheMinute()     { dateutils.secondOf "$1"; }
dateutils.milliSecondOfTheSecond(){ dateutils.milliSecondOf "$1"; }
# ...of the day
dateutils.minuteOfTheDay()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( __kdt_h*60 + __kdt_mi )); }
dateutils.secondOfTheDay()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( (__kdt_h*60 + __kdt_mi)*60 + __kdt_s )); }
dateutils.milliSecondOfTheDay() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( ((__kdt_h*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the hour
dateutils.secondOfTheHour()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( __kdt_mi*60 + __kdt_s )); }
dateutils.milliSecondOfTheHour() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( (__kdt_mi*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the minute
dateutils.milliSecondOfTheMinute() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( __kdt_s*1000 + __kdt_ms )); }
# ...of the week (Monday-based; dow 1..7)
dateutils.hourOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dow
    dateutils._split_kdt "$1"; dateutils._weekday_iso "$1"; dow=$REPLY
    echo $(( (dow-1)*24 + __kdt_h ))
}
dateutils.minuteOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dow
    dateutils._split_kdt "$1"; dateutils._weekday_iso "$1"; dow=$REPLY
    echo $(( ((dow-1)*24 + __kdt_h)*60 + __kdt_mi ))
}
dateutils.secondOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dow
    dateutils._split_kdt "$1"; dateutils._weekday_iso "$1"; dow=$REPLY
    echo $(( (((dow-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s ))
}
dateutils.milliSecondOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dow
    dateutils._split_kdt "$1"; dateutils._weekday_iso "$1"; dow=$REPLY
    echo $(( ((((dow-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms ))
}
# ...of the month (D = day-of-month)
dateutils.hourOfTheMonth()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( (__kdt_d-1)*24 + __kdt_h )); }
dateutils.minuteOfTheMonth()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( ((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi )); }
dateutils.secondOfTheMonth()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( (((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s )); }
dateutils.milliSecondOfTheMonth() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms; dateutils._split_kdt "$1"; echo $(( ((((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the year (via day-of-year)
dateutils.hourOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys doy
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"; doy=$(( REPLY - ys + 1 ))
    echo $(( __kdt_h + (doy-1)*24 ))
}
dateutils.minuteOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys doy
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"; doy=$(( REPLY - ys + 1 ))
    echo $(( __kdt_mi + (__kdt_h + (doy-1)*24)*60 ))
}
dateutils.secondOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys doy
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"; doy=$(( REPLY - ys + 1 ))
    echo $(( (__kdt_mi + (__kdt_h + (doy-1)*24)*60)*60 + __kdt_s ))
}
dateutils.milliSecondOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ys doy
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; ys=$REPLY
    dateutils._floor_day "$1"; doy=$(( REPLY - ys + 1 ))
    echo $(( ((__kdt_mi + (__kdt_h + (doy-1)*24)*60)*60 + __kdt_s)*1000 + __kdt_ms ))
}
# nth-weekday-in-month helpers
dateutils.nthDayOfWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; echo $(( (__kdt_d - 1) / 7 + 1 ))
}
dateutils.decodeDayOfWeekInMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dow
    dateutils._split_kdt "$1"; dateutils._weekday_iso "$1"; dow=$REPLY
    echo "$__kdt_y $__kdt_mo $(( (__kdt_d - 1) / 7 + 1 )) $dow"
}

# --- P3: start/end of year --------------------------------------------------
dateutils.startOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" 1 1; echo $(( REPLY * 86400000 ))
}
dateutils.startOfAYear() { dateutils._days_from_civil "$1" 1 1; echo $(( REPLY * 86400000 )); }
dateutils.endOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._join_kdt "$__kdt_y" 12 31 23 59 59 999; echo "$REPLY"
}
dateutils.endOfAYear() { dateutils._join_kdt "$1" 12 31 23 59 59 999; echo "$REPLY"; }

# --- P3: start/end of month -------------------------------------------------
dateutils.startOfTheMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; dateutils._days_from_civil "$__kdt_y" "$__kdt_mo" 1; echo $(( REPLY * 86400000 ))
}
dateutils.startOfAMonth() { dateutils._days_from_civil "$1" "$2" 1; echo $(( REPLY * 86400000 )); }
dateutils.endOfTheMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms dim
    dateutils._split_kdt "$1"; dateutils._days_in_month "$__kdt_y" "$__kdt_mo"; dim=$REPLY
    dateutils._join_kdt "$__kdt_y" "$__kdt_mo" "$dim" 23 59 59 999; echo "$REPLY"
}
dateutils.endOfAMonth() {
    local dim; dateutils._days_in_month "$1" "$2"; dim=$REPLY
    dateutils._join_kdt "$1" "$2" "$dim" 23 59 59 999; echo "$REPLY"
}

# --- P3: start/end of week (Monday-based, ISO) ------------------------------
dateutils.startOfTheWeek() {
    local dow day; dateutils._weekday_iso "$1"; dow=$REPLY; dateutils._floor_day "$1"; day=$REPLY
    echo $(( (day - dow + 1) * 86400000 ))
}
dateutils.startOfAWeek() { dateutils._encode_date_week "$1" "$2" "${3:-1}" || return 1; echo "$REPLY"; }
dateutils.endOfTheWeek() {
    local dow day; dateutils._weekday_iso "$1"; dow=$REPLY; dateutils._floor_day "$1"; day=$REPLY
    echo $(( (day - dow + 7) * 86400000 + 86399999 ))
}
dateutils.endOfAWeek() { dateutils._encode_date_week "$1" "$2" "${3:-7}" || return 1; echo $(( REPLY + 86399999 )); }

# --- P3: start/end of day (start/endOfADay overload on arg count) -----------
dateutils.startOfTheDay() { dateutils._floor_day "$1"; echo $(( REPLY * 86400000 )); }
dateutils.startOfADay() {
    if (( $# == 3 )); then dateutils._days_from_civil "$1" "$2" "$3"; echo $(( REPLY * 86400000 ))
    else dateutils._days_from_civil "$1" 1 1; echo $(( (REPLY + $2 - 1) * 86400000 )); fi
}
dateutils.endOfTheDay() { dateutils._floor_day "$1"; echo $(( REPLY * 86400000 + 86399999 )); }
dateutils.endOfADay() {
    if (( $# == 3 )); then dateutils._days_from_civil "$1" "$2" "$3"; echo $(( REPLY * 86400000 + 86399999 ))
    else dateutils._days_from_civil "$1" 1 1; echo $(( (REPLY + $2 - 1) * 86400000 + 86399999 )); fi
}

# --- P3: day predicates -----------------------------------------------------
# isSameDay truncates ONLY the basis (FPC quirk): value is in [floor(basis), +1day).
dateutils.isSameDay() {
    local base; dateutils._floor_day "$2"; base=$(( REPLY * 86400000 ))
    (( $1 >= base && $1 < base + 86400000 )) && echo true || echo false
}
dateutils.isToday() {
    local n base; dateutils._now_local_ms; n=$REPLY; dateutils._floor_day "$n"; base=$(( REPLY * 86400000 ))
    (( $1 >= base && $1 < base + 86400000 )) && echo true || echo false
}
dateutils.isSameMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms ya ma
    dateutils._split_kdt "$1"; ya=$__kdt_y; ma=$__kdt_mo
    dateutils._split_kdt "$2"
    (( ya == __kdt_y && ma == __kdt_mo )) && echo true || echo false
}
# previousDayOfWeek takes an ISO weekday NUMBER (1..7) and returns the prior one.
dateutils.previousDayOfWeek() {
    local d=$1; (( d >= 1 && d <= 7 )) || { dateutils._debug "invalid day-of-week $d"; return 1; }
    (( d == 1 )) && echo 7 || echo $(( d - 1 ))
}

# --- P4: increment (default step = 1; time-of-day preserved) ----------------
dateutils.incYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; local n=${2:-1} y=$(( __kdt_y + ${2:-1} ))
    if (( __kdt_mo == 2 && __kdt_d == 29 )); then dateutils._is_leap "$y"; (( REPLY )) || __kdt_d=28; fi
    dateutils._join_kdt "$y" "$__kdt_mo" "$__kdt_d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"; echo "$REPLY"
}
dateutils.incMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$1"; local n=${2:-1} total newy newm dim
    total=$(( __kdt_y*12 + __kdt_mo - 1 + n ))
    newy=$(( total / 12 )); (( total % 12 < 0 )) && newy=$(( newy - 1 ))   # floor division
    newm=$(( total - newy*12 + 1 ))
    dateutils._days_in_month "$newy" "$newm"; dim=$REPLY
    (( __kdt_d > dim )) && __kdt_d=$dim                                    # clamp to month length
    dateutils._join_kdt "$newy" "$newm" "$__kdt_d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"; echo "$REPLY"
}
dateutils.incWeek()        { echo $(( $1 + ${2:-1} * 604800000 )); }
dateutils.incDay()         { echo $(( $1 + ${2:-1} * 86400000 )); }
dateutils.incHour()        { echo $(( $1 + ${2:-1} * 3600000 )); }
dateutils.incMinute()      { echo $(( $1 + ${2:-1} * 60000 )); }
dateutils.incSecond()      { echo $(( $1 + ${2:-1} * 1000 )); }
dateutils.incMilliSecond() { echo $(( $1 + ${2:-1} )); }

# --- P4: between (|now-then| / unit; exact ones use periodBetween) -----------
dateutils.milliSecondsBetween() { local d=$(( $1 - $2 )); echo $(( d < 0 ? -d : d )); }
dateutils.secondsBetween()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 1000 )); }
dateutils.minutesBetween()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 60000 )); }
dateutils.hoursBetween()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 3600000 )); }
dateutils.daysBetween()         { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 86400000 )); }
dateutils.weeksBetween()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 86400000 / 7 )); }
# yearsBetween/monthsBetween: approximate by default (365.25 / 30.4375 days);
# 3rd arg "exact"/"true"/"1" switches to the calendar-true periodBetween.
dateutils.yearsBetween() {
    if [[ "$3" == exact || "$3" == true || "$3" == 1 ]]; then
        dateutils._period_between "$1" "$2"; echo "$__kdt_pb_y"
    else
        local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 31557600000 ))
    fi
}
dateutils.monthsBetween() {
    if [[ "$3" == exact || "$3" == true || "$3" == 1 ]]; then
        dateutils._period_between "$1" "$2"; echo $(( __kdt_pb_y*12 + __kdt_pb_m ))
    else
        local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); echo $(( d / 2629800000 ))
    fi
}
dateutils.periodBetween() { dateutils._period_between "$1" "$2"; echo "$__kdt_pb_y $__kdt_pb_m $__kdt_pb_d"; }
dateutils.dateTimeDiff()  { echo $(( $1 - $2 )); }   # signed ms

# --- P4: span (fractional ratio, 6 dp) --------------------------------------
dateutils.milliSecondSpan() { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 1;           echo "$REPLY"; }
dateutils.secondSpan()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 1000;        echo "$REPLY"; }
dateutils.minuteSpan()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 60000;       echo "$REPLY"; }
dateutils.hourSpan()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 3600000;     echo "$REPLY"; }
dateutils.daySpan()         { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 86400000;    echo "$REPLY"; }
dateutils.weekSpan()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 604800000;   echo "$REPLY"; }
dateutils.monthSpan()       { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 2629800000;  echo "$REPLY"; }
dateutils.yearSpan()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 31557600000; echo "$REPLY"; }

# --- P4: within-past (xxxBetween(now,then) <= range; approx for years/months)
dateutils.withinPastMilliSeconds() { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d           <= $3 )) && echo true || echo false; }
dateutils.withinPastSeconds()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/1000      <= $3 )) && echo true || echo false; }
dateutils.withinPastMinutes()      { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/60000     <= $3 )) && echo true || echo false; }
dateutils.withinPastHours()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/3600000   <= $3 )) && echo true || echo false; }
dateutils.withinPastDays()         { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/86400000  <= $3 )) && echo true || echo false; }
dateutils.withinPastWeeks()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/86400000/7 <= $3 )) && echo true || echo false; }
dateutils.withinPastMonths()       { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/2629800000  <= $3 )) && echo true || echo false; }
dateutils.withinPastYears()        { local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d/31557600000 <= $3 )) && echo true || echo false; }

# --- P4: compare (echo -1/0/1) / same (true/false) --------------------------
# Integer KDT is linear, so compare = sign(a-b); FPC's frac/trunc branches only
# exist to tame negative-TDateTime float weirdness that KDT does not have.
dateutils.compareDateTime() { local r=0; (( $1 > $2 )) && r=1; (( $1 < $2 )) && r=-1; printf '%d\n' "$r"; }
dateutils.compareDate() {
    local a b r=0; dateutils._floor_day "$1"; a=$REPLY; dateutils._floor_day "$2"; b=$REPLY
    (( a > b )) && r=1; (( a < b )) && r=-1; printf '%d\n' "$r"
}
dateutils.compareTime() {
    local ta tb r=0
    dateutils._floor_day "$1"; ta=$(( $1 - REPLY*86400000 ))
    dateutils._floor_day "$2"; tb=$(( $2 - REPLY*86400000 ))
    (( ta > tb )) && r=1; (( ta < tb )) && r=-1; printf '%d\n' "$r"
}
dateutils.sameDateTime() { (( $1 == $2 )) && echo true || echo false; }
dateutils.sameDate() {
    local a b; dateutils._floor_day "$1"; a=$REPLY; dateutils._floor_day "$2"; b=$REPLY
    (( a == b )) && echo true || echo false
}
dateutils.sameTime() {
    local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d )); (( d % 86400000 == 0 )) && echo true || echo false
}

# --- P4: range (inclusive by default; timeInRange handles overnight wrap) ----
dateutils.dateTimeInRange() {
    local dt=$1 s=$2 e=$3 inc=${4:-true}
    if [[ "$inc" == true || "$inc" == 1 ]]; then (( s <= dt && dt <= e )) && echo true || echo false
    else (( s < dt && dt < e )) && echo true || echo false; fi
}
dateutils.dateInRange() {
    local dd ds de inc=${4:-true}
    dateutils._floor_day "$1"; dd=$REPLY; dateutils._floor_day "$2"; ds=$REPLY; dateutils._floor_day "$3"; de=$REPLY
    if [[ "$inc" == true || "$inc" == 1 ]]; then (( ds <= dd && dd <= de )) && echo true || echo false
    else (( ds < dd && dd < de )) && echo true || echo false; fi
}
dateutils.timeInRange() {
    local lt ls le inc=${4:-true} res=false
    dateutils._floor_day "$1"; lt=$(( $1 - REPLY*86400000 ))
    dateutils._floor_day "$2"; ls=$(( $2 - REPLY*86400000 ))
    dateutils._floor_day "$3"; le=$(( $3 - REPLY*86400000 ))
    if (( le < ls )); then                         # overnight range (end before start)
        if [[ "$inc" == true || "$inc" == 1 ]]; then (( ls <= lt || lt <= le )) && res=true
        else (( ls < lt || lt < le )) && res=true; fi
    else
        if [[ "$inc" == true || "$inc" == 1 ]]; then (( ls <= lt && lt <= le )) && res=true
        else (( ls < lt && lt < le )) && res=true; fi
    fi
    echo "$res"
}

# --- P5: recode (field surgery; '-' keeps a field; recode* logs, try* silent)
dateutils.recodeDateTime()    { dateutils._recode "$@"                     || { dateutils._debug "invalid recodeDateTime"; return 1; }; echo "$REPLY"; }
dateutils.tryRecodeDateTime() { dateutils._recode "$@"                     || return 1; echo "$REPLY"; }
dateutils.recodeYear()        { dateutils._recode "$1" "$2" -  -  -  -  -  -  || { dateutils._debug "invalid recodeYear";        return 1; }; echo "$REPLY"; }
dateutils.recodeMonth()       { dateutils._recode "$1" -  "$2" -  -  -  -  -  || { dateutils._debug "invalid recodeMonth";       return 1; }; echo "$REPLY"; }
dateutils.recodeDay()         { dateutils._recode "$1" -  -  "$2" -  -  -  -  || { dateutils._debug "invalid recodeDay";         return 1; }; echo "$REPLY"; }
dateutils.recodeHour()        { dateutils._recode "$1" -  -  -  "$2" -  -  -  || { dateutils._debug "invalid recodeHour";        return 1; }; echo "$REPLY"; }
dateutils.recodeMinute()      { dateutils._recode "$1" -  -  -  -  "$2" -  -  || { dateutils._debug "invalid recodeMinute";      return 1; }; echo "$REPLY"; }
dateutils.recodeSecond()      { dateutils._recode "$1" -  -  -  -  -  "$2" -  || { dateutils._debug "invalid recodeSecond";      return 1; }; echo "$REPLY"; }
dateutils.recodeMilliSecond() { dateutils._recode "$1" -  -  -  -  -  -  "$2" || { dateutils._debug "invalid recodeMilliSecond"; return 1; }; echo "$REPLY"; }
dateutils.recodeDate()        { dateutils._recode "$1" "$2" "$3" "$4" -  -  -  -  || { dateutils._debug "invalid recodeDate"; return 1; }; echo "$REPLY"; }
dateutils.recodeTime()        { dateutils._recode "$1" -  -  -  "$2" "$3" "$4" "$5" || { dateutils._debug "invalid recodeTime"; return 1; }; echo "$REPLY"; }

# --- P5: week-date / day-of-week-in-month encodings -------------------------
dateutils.encodeDateWeek()    { dateutils._encode_date_week "$1" "$2" "${3:-1}" || { dateutils._debug "invalid dateWeek $1/$2"; return 1; }; echo "$REPLY"; }
dateutils.tryEncodeDateWeek() { dateutils._encode_date_week "$1" "$2" "${3:-1}" || return 1; echo "$REPLY"; }
dateutils.decodeDateWeek()    { dateutils._decode_date_week "$1"; echo "$__kdt_wy_year $__kdt_wy_week $__kdt_wy_dow"; }
dateutils.encodeDateMonthWeek()    { dateutils._encode_date_month_week "$1" "$2" "$3" "$4" || { dateutils._debug "invalid dateMonthWeek"; return 1; }; echo "$REPLY"; }
dateutils.tryEncodeDateMonthWeek() { dateutils._encode_date_month_week "$1" "$2" "$3" "$4" || return 1; echo "$REPLY"; }
dateutils.decodeDateMonthWeek()    { dateutils._decode_date_month_week "$1"; echo "$__kdt_mw_year $__kdt_mw_month $__kdt_mw_week $__kdt_mw_dow"; }
dateutils.encodeDayOfWeekInMonth()    { dateutils._encode_dow_in_month "$1" "$2" "$3" "$4" || { dateutils._debug "invalid dayOfWeekInMonth"; return 1; }; echo "$REPLY"; }
dateutils.tryEncodeDayOfWeekInMonth() { dateutils._encode_dow_in_month "$1" "$2" "$3" "$4" || return 1; echo "$REPLY"; }

# --- P6: Unix (KDT 0 == Unix 0; conversion is a trivial ms<->s scaling) ------
dateutils.dateTimeToUnix() {
    local dt=$1 utc=${2:-true} sec
    [[ "$utc" != true && "$utc" != 1 ]] && { dateutils._local_offset_ms; dt=$(( dt - REPLY )); }  # local -> UTC
    sec=$(( dt / 1000 )); (( dt < 0 && dt % 1000 != 0 )) && sec=$(( sec - 1 ))   # floor to the second
    echo "$sec"
}
dateutils.unixToDateTime() {
    local kdt=$(( $1 * 1000 )) utc=${2:-true}
    [[ "$utc" != true && "$utc" != 1 ]] && { dateutils._local_offset_ms; kdt=$(( kdt + REPLY )); }  # UTC -> local
    echo "$kdt"
}

# --- P6: Julian / Modified Julian (6-dp decimal strings) --------------------
dateutils.dateTimeToJulianDate()         { dateutils._span_fixed $(( 210866760000000 + $1 )) 86400000; echo "$REPLY"; }
dateutils.dateTimeToModifiedJulianDate() { dateutils._span_fixed $(( 3506716800000 + $1 )) 86400000; echo "$REPLY"; }
dateutils.tryJulianDateToDateTime() {
    dateutils._jd_str_to_ms "$1"; local kdt=$(( REPLY - 210866760000000 ))
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$kdt"; (( __kdt_y >= 1 && __kdt_y <= 9999 )) || return 1
    echo "$kdt"
}
dateutils.julianDateToDateTime() { dateutils.tryJulianDateToDateTime "$1" || { dateutils._debug "invalid JD $1"; return 1; }; }
dateutils.tryModifiedJulianDateToDateTime() {
    dateutils._jd_str_to_ms "$1"; local kdt=$(( REPLY - 3506716800000 ))
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$kdt"; (( __kdt_y >= 1 && __kdt_y <= 9999 )) || return 1
    echo "$kdt"
}
dateutils.modifiedJulianDateToDateTime() { dateutils.tryModifiedJulianDateToDateTime "$1" || { dateutils._debug "invalid MJD $1"; return 1; }; }

# --- P6: local <-> UTC (explicit offset is minutes EAST of UTC, like %(%z)T) -
dateutils.universalTimeToLocal() {
    local ut=$1 off
    if (( $# >= 2 )); then dateutils._normalize_offset_min_east "$2" || return 1; off=$REPLY
    else dateutils._local_offset_ms; off=$(( REPLY / 60000 )); fi
    echo $(( ut + off*60000 ))
}
dateutils.localTimeToUniversal() {
    local lt=$1 off
    if (( $# >= 2 )); then dateutils._normalize_offset_min_east "$2" || return 1; off=$REPLY
    else dateutils._local_offset_ms; off=$(( REPLY / 60000 )); fi
    echo $(( lt - off*60000 ))
}

# --- P6: time interval (a duration; hours may exceed 24) --------------------
dateutils.tryEncodeTimeInterval() {
    local h=$1 m=$2 s=$3 ms=$4
    (( m < 60 && s < 60 && ms <= 1000 )) || return 1      # FPC allows ms == 1000
    echo $(( h*3600000 + m*60000 + s*1000 + ms ))
}
dateutils.encodeTimeInterval() { dateutils.tryEncodeTimeInterval "$@" || { dateutils._debug "invalid interval"; return 1; }; }

# --- P6: timezone-offset strings (FPC sign: '+03:00' -> -180) ---------------
dateutils.tryISOTZStrToTZOffset() {
    local tz=$1 sign h m=0 off
    if [[ "$tz" == Z || -z "$tz" ]]; then echo 0; return 0; fi
    [[ "$tz" == [+-]* ]] || return 1
    sign=${tz:0:1}
    case ${#tz} in
        3) [[ "${tz:1:2}" =~ ^[0-9]{2}$ ]] || return 1; h=${tz:1:2} ;;
        5) [[ "${tz:1}" =~ ^[0-9]{4}$ ]] || return 1; h=${tz:1:2}; m=${tz:3:2} ;;
        6) [[ "${tz:1}" =~ ^[0-9]{2}:[0-9]{2}$ ]] || return 1; h=${tz:1:2}; m=${tz:4:2} ;;
        *) return 1 ;;
    esac
    off=$(( 10#$h*60 + 10#$m )); [[ "$sign" == + ]] && off=$(( -off ))   # FPC negates '+'
    echo "$off"
}
dateutils.isoTZStrToTZOffset() { dateutils.tryISOTZStrToTZOffset "$1" || { dateutils._debug "invalid TZ $1"; return 1; }; }

# --- P6: ISO 8601 date/datetime strings -------------------------------------
# tryISOStrToDate: date-only (YYYY / YYYYMM / YYYY-MM / YYYYMMDD / YYYY-MM-DD).
dateutils.tryISOStrToDate() {
    local s=$1 y m=1 d=1
    case ${#s} in
        4)  [[ "$s" =~ ^[0-9]{4}$ ]] || return 1; y=$s ;;
        6)  [[ "$s" =~ ^[0-9]{6}$ ]] || return 1; y=${s:0:4}; m=${s:4:2} ;;
        7)  [[ "$s" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1; y=${s:0:4}; m=${s:5:2} ;;
        8)  [[ "$s" =~ ^[0-9]{8}$ ]] || return 1; y=${s:0:4}; m=${s:4:2}; d=${s:6:2} ;;
        10) [[ "$s" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1; y=${s:0:4}; m=${s:5:2}; d=${s:8:2} ;;
        *)  return 1 ;;
    esac
    dateutils._valid_date "$((10#$y))" "$((10#$m))" "$((10#$d))"; (( REPLY )) || return 1
    dateutils._join_kdt "$((10#$y))" "$((10#$m))" "$((10#$d))" 0 0 0 0; echo "$REPLY"
}
# tryISOStrToTime: hh:mm[:ss[.zzz]] with an optional trailing zone -> ms-of-day.
dateutils.tryISOStrToTime() {
    local s=${1%Z} h m sec msraw ms=0
    [[ "$s" =~ ^([0-9]{2}):([0-9]{2})(:([0-9]{2})(\.([0-9]{1,3}))?)?([+-][0-9]{2}:?[0-9]{2})?$ ]] || return 1
    h=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); sec=$((10#${BASH_REMATCH[4]:-0}))
    msraw=${BASH_REMATCH[6]:-}; [[ -n "$msraw" ]] && { msraw=${msraw}000; ms=$((10#${msraw:0:3})); }
    (( h <= 23 && m <= 59 && sec <= 59 )) || return 1
    echo $(( h*3600000 + m*60000 + sec*1000 + ms ))
}
# tryISOStrToDateTime: naive datetime as written (no zone conversion).
dateutils.tryISOStrToDateTime() { dateutils._parse_iso "$1" || return 1; echo "$REPLY"; }

# dateToISO8601: 'YYYY-MM-DDThh:mm:ss.zzz' + 'Z' (UTC) or '±hh:mm' (local).
dateutils.dateToISO8601() {
    local dt=$1 utc=${2:-true} s off sign m
    dateutils._fmt_datetime "$dt"; s=${REPLY/ /T}
    if [[ "$utc" == true || "$utc" == 1 ]]; then echo "${s}Z"; return; fi
    dateutils._local_offset_ms; off=$REPLY
    if (( off == 0 )); then echo "${s}Z"; return; fi
    sign=+; (( off < 0 )) && { sign=-; off=$(( -off )); }
    m=$(( off / 60000 )); printf '%s%s%02d:%02d\n' "$s" "$sign" "$(( m/60 ))" "$(( m%60 ))"
}
# tryISO8601ToDate: parse datetime+zone, convert to UTC (or local if returnUTC=false).
dateutils.tryISO8601ToDate() {
    local str=$1 rutc=${2:-true} kdt
    dateutils._parse_iso "$str" || return 1        # REPLY=naive kdt, __kdt_has_tz, __kdt_tzoff_min (east+)
    kdt=$REPLY
    (( __kdt_has_tz )) && kdt=$(( kdt - __kdt_tzoff_min*60000 ))   # zoned wall clock -> UTC
    [[ "$rutc" != true && "$rutc" != 1 ]] && { dateutils._local_offset_ms; kdt=$(( kdt + REPLY )); }
    echo "$kdt"
}
dateutils.iso8601ToDate() { dateutils.tryISO8601ToDate "$@" || { dateutils._debug "invalid ISO8601 $1"; return 1; }; }
dateutils.iso8601ToDateDef() {
    local r; if r=$(dateutils.tryISO8601ToDate "$1" "${3:-true}"); then echo "$r"; else echo "$2"; fi
}

# --- P7: scanDateTime (practical subset of FPC ScanDateTime) ----------------
# Tokens (case-insensitive): yyyy/yy year, mm month, dd day, hh hour, nn minute,
# ss second, zzz millisecond. Minutes use NN (mm is always month). Each numeric
# token reads up to its width in digits (greedy, like FPC scanfixedint). Quoted
# 'literals'/"literals" match verbatim; whitespace in the pattern is elastic;
# other characters must match exactly. 2-digit years pivot at 50 (00-49 -> 20xx,
# 50-99 -> 19xx). Echoes the KDT; returns 1 (echoes nothing) on any mismatch.
# Out of scope (full FPC matcher): month/day NAMES, ampm, T/date-format tokens,
# [] optionals (decision gate P7.1: add only if the subset proves insufficient).
dateutils.scanDateTime() {
    local pat=$1 inp=$2 plen=${#1} ilen=${#2}
    # Unset fields default to the epoch (1970-01-01 00:00), so a partial pattern
    # still yields a valid KDT; a time-only pattern gives the ms-of-day.
    local pind=0 ind=0 yy=1970 mm=1 dd=1 h=0 n=0 s=0 ms=0
    local pc upc runlen maxv val cnt c q
    while (( pind < plen )); do
        pc=${pat:pind:1}
        if [[ "$pc" == "'" || "$pc" == '"' ]]; then           # quoted literal
            q=$pc; pind=$(( pind + 1 ))
            while (( pind < plen )) && [[ "${pat:pind:1}" != "$q" ]]; do
                { (( ind < ilen )) && [[ "${inp:ind:1}" == "${pat:pind:1}" ]]; } || return 1
                pind=$(( pind + 1 )); ind=$(( ind + 1 ))
            done
            (( pind < plen )) && pind=$(( pind + 1 ))
            continue
        fi
        upc=${pc^^}
        case "$upc" in
            Y|M|D|H|N|S|Z)
                runlen=0
                while (( pind + runlen < plen )) && [[ "${pat:pind+runlen:1}" == "$pc" ]]; do runlen=$(( runlen + 1 )); done
                case "$upc" in
                    Y) (( runlen <= 2 )) && maxv=2 || maxv=$runlen ;;
                    Z) maxv=3 ;;
                    *) maxv=2 ;;
                esac
                val=0; cnt=0
                while (( maxv > 0 && ind < ilen )); do
                    c=${inp:ind:1}; [[ "$c" == [0-9] ]] || break
                    val=$(( val*10 + 10#$c )); ind=$(( ind + 1 )); cnt=$(( cnt + 1 )); maxv=$(( maxv - 1 ))
                done
                (( cnt > 0 )) || return 1
                pind=$(( pind + runlen ))
                case "$upc" in
                    Y) (( runlen <= 2 )) && { (( val < 50 )) && val=$(( 2000 + val )) || val=$(( 1900 + val )); }; yy=$val ;;
                    M) mm=$val ;;  D) dd=$val ;;  H) h=$val ;;
                    N) n=$val ;;   S) s=$val ;;   Z) ms=$val ;;
                esac
                ;;
            *)
                if [[ "$pc" == " " || "$pc" == $'\t' ]]; then   # elastic whitespace
                    while (( pind < plen )) && [[ "${pat:pind:1}" == " " || "${pat:pind:1}" == $'\t' ]]; do pind=$(( pind + 1 )); done
                    while (( ind < ilen )) && [[ "${inp:ind:1}" == " " || "${inp:ind:1}" == $'\t' ]]; do ind=$(( ind + 1 )); done
                else
                    { (( ind < ilen )) && [[ "${inp:ind:1}" == "$pc" ]]; } || return 1
                    pind=$(( pind + 1 )); ind=$(( ind + 1 ))
                fi
                ;;
        esac
    done
    dateutils._valid_date "$yy" "$mm" "$dd"; (( REPLY )) || return 1
    dateutils._valid_time "$h" "$n" "$s" "$ms"; (( REPLY )) || return 1
    dateutils._join_kdt "$yy" "$mm" "$dd" "$h" "$n" "$s" "$ms"; echo "$REPLY"
}

# Finalize: extract the bodies above into the `dateutils` class and generate the
# thin static dispatchers. The class is named `dateutils`, so the public API is
# `dateutils.<Method>` and kklass metadata `dateutils_class_static_methods` is
# populated. Internal dateutils._* helpers are left untouched (plain functions).
build dateutils
