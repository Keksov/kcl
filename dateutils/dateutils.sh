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
if [[ -n "${_DATEUTILS_SOURCED:-}" ]]; then
    return
fi
declare -g _DATEUTILS_SOURCED=1

# Character semantics are part of this unit's contract (kcl/README.md 1.6,
# decision D6); an empty environment means the C locale, where ${#s} counts
# bytes and ${s,,} corrupts UTF-8.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

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

# The return contract of every member (kcl/README.md 1.1, decision D3).
# $1 = value, $2 = exit status (default 0). A DIRECT call is silent and leaves
# the value in RESULT; inside `$( )` the value is printed exactly once, so a
# caller written against the pre-P6 `printf` bodies keeps working.
#
# `static proc` + this helper, NOT `static func`: kklass's thin static
# dispatcher re-prints kk._return's value unconditionally, i.e. on a direct
# call too (recorded in kcl/README.md 1.1 and first used by tpath in P3).
dateutils._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# Boolean answer: RESULT/stdout carry true|false and the exit status carries
# the same answer (default R8). $1 = 0 for true, anything else for false.
dateutils._retBool() {
    if [[ "$1" == "0" ]]; then
        dateutils._ret "true" 0
    else
        dateutils._ret "false" 1
    fi
}

# --- Civil calendar (Howard Hinnant's algorithms) --------------------------
# Both are written for C-style truncated-toward-zero division, which is exactly
# what bash $(( )) does — so the `(y >= 0 ? y : y-399)` style floor tricks port
# verbatim and stay correct for negative (pre-Gregorian-epoch) years.

# _days_from_civil Y M D -> REPLY = days since 1970-01-01 (day 0 = Thu).
# Validating form, for the members that take a year/month/day from the caller.
# Internal callers that already hold normalised integers use the `_i` core: a
# kk.isInt is ~52 us on this box and three of them dominated weekOfTheYear.
dateutils._days_from_civil() {
    local __kdt_fy __kdt_fm __kdt_fd
    REPLY=0
    kk.isInt "${1:-}" __kdt_fy || return 1
    kk.isInt "${2:-}" __kdt_fm || return 1
    kk.isInt "${3:-}" __kdt_fd || return 1
    dateutils._days_from_civil_i "$__kdt_fy" "$__kdt_fm" "$__kdt_fd"
}

# _days_from_civil_i Y M D -> REPLY. The three fields MUST already be
# normalised decimal integers (see the note above _join_kdt).
dateutils._days_from_civil_i() {
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
    if (( __kdt_mo <= 2 )); then (( __kdt_y += 1 )); fi
}

# _split_kdt KDT -> sets __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s
# __kdt_ms, and — because it has them anyway — __kdt_n (the KDT normalised to a
# decimal integer), __kdt_day (the floor day number) and __kdt_dow (the ISO
# weekday). Publishing those three costs two arithmetic ops here and saves a
# _floor_day and a _weekday_iso call, i.e. two kk.isInt at ~52 us each, in every
# member that needs them.
dateutils._split_kdt() {
    local kdt total_days ms_of_day rem
    if ! kk.isInt "${1:-}" kdt; then
        __kdt_y=0 __kdt_mo=1 __kdt_d=1 __kdt_h=0 __kdt_mi=0 __kdt_s=0 __kdt_ms=0
        __kdt_n=0 __kdt_day=0 __kdt_dow=4
        return 1
    fi
    __kdt_n=$kdt
    total_days=$(( kdt / 86400000 ))
    ms_of_day=$(( kdt - total_days * 86400000 ))
    if (( ms_of_day < 0 )); then                 # floor division for pre-1970
        ms_of_day=$(( ms_of_day + 86400000 ))
        total_days=$(( total_days - 1 ))
    fi
    __kdt_day=$total_days
    __kdt_dow=$(( ( (total_days + 3) % 7 + 7 ) % 7 + 1 ))    # ISO Mon=1..Sun=7
    dateutils._civil_from_days "$total_days"     # -> __kdt_y __kdt_mo __kdt_d
    __kdt_h=$(( ms_of_day / 3600000 ))
    rem=$(( ms_of_day % 3600000 ))
    __kdt_mi=$(( rem / 60000 ))
    rem=$(( rem % 60000 ))
    __kdt_s=$(( rem / 1000 ))
    __kdt_ms=$(( rem % 1000 ))
}

# _join_kdt Y M D h m s ms -> REPLY = KDT.
# The seven fields must ALREADY be normalised decimals: the y/m/d go through
# _days_from_civil (which validates), but h/m/s/ms land straight in (( )), and
# `08` there is an octal parse error (G3-01). Every caller therefore passes the
# __kdt_v* values published by _valid_date / _valid_time / _encodable_time, or
# integers it computed itself.
dateutils._join_kdt() {
    local y=$1 mo=$2 d=$3 h=$4 mi=$5 s=$6 ms=$7
    dateutils._days_from_civil_i "$y" "$mo" "$d"   # -> REPLY = days
    REPLY=$(( REPLY * 86400000 + h*3600000 + mi*60000 + s*1000 + ms ))
}

# _weekday_iso KDT -> REPLY = ISO weekday (Mon=1 .. Sun=7). Day 0 = Thursday(4).
# rc 1 (REPLY 0) if the KDT is not an integer (G3-04).
dateutils._weekday_iso() {
    local kdt total_days
    REPLY=0
    kk.isInt "${1:-}" kdt || return 1
    total_days=$(( kdt / 86400000 ))
    if (( kdt - total_days*86400000 < 0 )); then total_days=$(( total_days - 1 )); fi
    REPLY=$(( ( (total_days + 3) % 7 + 7 ) % 7 + 1 ))
}

# --- ISO 8601 format / parse ------------------------------------------------
# Canonical forms: date "YYYY-MM-DD", time "hh:mm:ss.zzz", datetime joined by a
# single space. _parse_iso accepts a 'T' or ' ' separator, optional seconds/ms,
# and an optional trailing zone (Z or ±hh[:]mm) captured for P6 (naive in P0).

# _fmt_date KDT -> REPLY "YYYY-MM-DD".
dateutils._fmt_date() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$1"
    printf -v REPLY '%04d-%02d-%02d' "$__kdt_y" "$__kdt_mo" "$__kdt_d"
}

# _fmt_time KDT -> REPLY "hh:mm:ss.zzz".
dateutils._fmt_time() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$1"
    printf -v REPLY '%02d:%02d:%02d.%03d' "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
}

# _fmt_datetime KDT -> REPLY "YYYY-MM-DD hh:mm:ss.zzz".
dateutils._fmt_datetime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$1"
    printf -v REPLY '%04d-%02d-%02d %02d:%02d:%02d.%03d' \
        "$__kdt_y" "$__kdt_mo" "$__kdt_d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
}

# --- ISO 8601 parsing, ported member by member from FPC ---------------------
# The old `_parse_iso` was one regex that checked `d <= 31` and let _join_kdt
# roll `2011-02-31` over to March 3rd with rc 0 (G3-02), and it knew only the
# fully punctuated forms (G3-09). These four helpers follow
# packages/rtl-objpas/src/inc/dateutil.inc line for line instead.

# _tz_offset_east TZSTR -> REPLY = minutes EAST of UTC; rc 1 if malformed.
# 'Z' and '' are 0. FPC TryISOTZStrToTZOffset (dateutil.inc:2876) accepts
# exactly the lengths 3 (`±hh`), 5 (`±hhmm`) and 6 (`±hh:mm`) and returns the
# NEGATED value; the public member re-applies FPC's sign, this helper keeps the
# natural one so the conversions below read as arithmetic.
dateutils._tz_offset_east() {
    local tz="${1:-}" h m=0
    REPLY=0
    if [[ "$tz" == Z || -z "$tz" ]]; then
        return 0
    fi
    [[ "$tz" == [+-]* ]] || return 1
    case ${#tz} in
        3) [[ "${tz:1:2}" =~ ^[0-9]{2}$ ]] || return 1; h=${tz:1:2} ;;
        5) [[ "${tz:1}" =~ ^[0-9]{4}$ ]] || return 1; h=${tz:1:2}; m=${tz:3:2} ;;
        6) [[ "${tz:1}" =~ ^[0-9]{2}:[0-9]{2}$ ]] || return 1; h=${tz:1:2}; m=${tz:4:2} ;;
        *) return 1 ;;
    esac
    REPLY=$(( 10#$h * 60 + 10#$m ))
    if [[ "${tz:0:1}" == "-" ]]; then
        REPLY=$(( -REPLY ))
    fi
    return 0
}

# _iso_date STRING -> REPLY = KDT at midnight; rc 1 otherwise.
# FPC TryISOStrToDate (dateutil.inc:2740) accepts exactly two lengths, 8
# (YYYYMMDD) and 10 (YYYY-MM-DD), and validates through TryEncodeDate — which
# is what refuses Feb 31 and year 0000 (G3-02). Lengths 4, 6 and 7 are a
# documented port EXTENSION (README "ISO 8601 forms"); they are unreachable
# from _iso_datetime, which splits at a fixed position, so the datetime grammar
# stays exactly FPC's.
dateutils._iso_date() {
    local s="${1:-}" y m=1 d=1
    case ${#s} in
        4)  [[ "$s" =~ ^[0-9]{4}$ ]] || return 1; y=${s:0:4} ;;
        6)  [[ "$s" =~ ^[0-9]{6}$ ]] || return 1; y=${s:0:4}; m=${s:4:2} ;;
        7)  [[ "$s" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1; y=${s:0:4}; m=${s:5:2} ;;
        8)  [[ "$s" =~ ^[0-9]{8}$ ]] || return 1; y=${s:0:4}; m=${s:4:2}; d=${s:6:2} ;;
        10) [[ "$s" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1; y=${s:0:4}; m=${s:5:2}; d=${s:8:2} ;;
        *)  return 1 ;;
    esac
    dateutils._valid_date "$y" "$m" "$d" || return 1
    (( REPLY )) || return 1
    dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" 0 0 0 0
}

# _iso_time STRING -> REPLY = ms of day; sets __kdt_has_tz / __kdt_tzoff_min.
# FPC TryISOStrToTime (dateutil.inc:2763): a trailing zone is peeled off first
# (`Z`, `±hh:mm`, `±hhmm`, `±hh`, tested in that order by POSITION), then the
# remaining LENGTH selects the form — 2, 4, 5, 6, 8, 10 or 12. FPC discards the
# offset it just parsed; this port keeps it, because TryISO8601ToDate needs it.
#
# The length-2 branch parses the WHOLE original string, not the prefix — that
# is verbatim FPC (`TryStrToInt(aString, xHour)`), and it is why `19-15` and
# `19Z` are refused while `1915+03` is accepted.
dateutils._iso_time() {
    local s="${1:-}" n=${#1} t h mi=0 sec=0 ms=0
    __kdt_has_tz=0
    __kdt_tzoff_min=0
    if (( n > 0 )) && [[ "${s:n-1:1}" == "Z" ]]; then
        __kdt_has_tz=1
        n=$(( n - 1 ))
    elif (( n > 6 )) && [[ "${s:n-6:1}" == [+-] ]]; then
        [[ "${s:n-5:2}" =~ ^[0-9]{2}$ && "${s:n-3:1}" == ":" && "${s:n-2:2}" =~ ^[0-9]{2}$ ]] || return 1
        __kdt_has_tz=1
        __kdt_tzoff_min=$(( 10#${s:n-5:2} * 60 + 10#${s:n-2:2} ))
        [[ "${s:n-6:1}" == "-" ]] && __kdt_tzoff_min=$(( -__kdt_tzoff_min ))
        n=$(( n - 6 ))
    elif (( n > 5 )) && [[ "${s:n-5:1}" == [+-] ]]; then
        [[ "${s:n-4:2}" =~ ^[0-9]{2}$ && "${s:n-2:2}" =~ ^[0-9]{2}$ ]] || return 1
        __kdt_has_tz=1
        __kdt_tzoff_min=$(( 10#${s:n-4:2} * 60 + 10#${s:n-2:2} ))
        [[ "${s:n-5:1}" == "-" ]] && __kdt_tzoff_min=$(( -__kdt_tzoff_min ))
        n=$(( n - 5 ))
    elif (( n > 3 )) && [[ "${s:n-3:1}" == [+-] ]]; then
        [[ "${s:n-2:2}" =~ ^[0-9]{2}$ ]] || return 1
        __kdt_has_tz=1
        __kdt_tzoff_min=$(( 10#${s:n-2:2} * 60 ))
        [[ "${s:n-3:1}" == "-" ]] && __kdt_tzoff_min=$(( -__kdt_tzoff_min ))
        n=$(( n - 3 ))
    fi
    t=${s:0:n}
    case $n in
        2)  [[ "$s" =~ ^[0-9]{1,2}$ ]] || return 1; h=$s ;;
        4)  [[ "$t" =~ ^[0-9]{4}$ ]] || return 1; h=${t:0:2}; mi=${t:2:2} ;;
        5)  [[ "$t" =~ ^[0-9]{2}:[0-9]{2}$ ]] || return 1; h=${t:0:2}; mi=${t:3:2} ;;
        6)  [[ "$t" =~ ^[0-9]{6}$ ]] || return 1; h=${t:0:2}; mi=${t:2:2}; sec=${t:4:2} ;;
        8)  [[ "$t" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || return 1; h=${t:0:2}; mi=${t:3:2}; sec=${t:6:2} ;;
        10) [[ "$t" =~ ^[0-9]{6}\.[0-9]{3}$ ]] || return 1; h=${t:0:2}; mi=${t:2:2}; sec=${t:4:2}; ms=${t:7:3} ;;
        12) [[ "$t" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}$ ]] || return 1
            h=${t:0:2}; mi=${t:3:2}; sec=${t:6:2}; ms=${t:9:3} ;;
        *)  return 1 ;;
    esac
    dateutils._encodable_time "$h" "$mi" "$sec" "$ms" || return 1
    (( REPLY )) || return 1
    REPLY=$(( __kdt_vh*3600000 + __kdt_vmi*60000 + __kdt_vs*1000 + __kdt_vms ))
    return 0
}

# _iso_datetime STRING -> REPLY = naive KDT; rc 1 otherwise.
# FPC TryISOStrToDateTime (dateutil.inc:2849) splits by POSITION: character 11
# then character 9 must be ' ' or 'T'. So `20110326T19:15` is a datetime and a
# bare `2011`, `20110326` or `T19:15` is not — contrary to the review report,
# which listed those three as FPC-valid.
dateutils._iso_datetime() {
    local s="${1:-}" n=${#1} sdate stime kd
    if (( n > 11 )) && [[ "${s:10:1}" == " " || "${s:10:1}" == "T" ]]; then
        sdate=${s:0:10}; stime=${s:11}
    elif (( n > 9 )) && [[ "${s:8:1}" == " " || "${s:8:1}" == "T" ]]; then
        sdate=${s:0:8};  stime=${s:9}
    else
        return 1
    fi
    dateutils._iso_date "$sdate" || return 1
    kd=$REPLY
    dateutils._iso_time "$stime" || return 1
    REPLY=$(( kd + REPLY ))
    return 0
}

# _parse_iso STRING -> REPLY = naive KDT; also sets __kdt_has_tz /
# __kdt_tzoff_min (minutes EAST). rc 1 on anything malformed.
#
# FPC TryISO8601ToDate (dateutil.inc:2915) peels the zone off the END of the
# whole string first, then hands the rest to TryISOStrToDateTime. Its rule is
# purely positional, which is why FPC reads the `-26` of `2011-03-26` as a
# timezone and rejects every date-only ISO 8601 string; this port keeps
# date-only input working by trying the FPC path first and falling back to the
# date parser on the ORIGINAL string (documented in README).
dateutils._parse_iso() {
    local s="${1:-}" n=${#1} tzs="" kdt
    __kdt_has_tz=0
    __kdt_tzoff_min=0
    if (( n == 0 )); then
        return 1
    fi
    if [[ "${s:n-1:1}" == "Z" ]]; then
        tzs=Z; s=${s:0:n-1}
    elif (( n > 2 )) && [[ "${s:n-3:1}" == [+-] ]]; then
        tzs=${s:n-3}; s=${s:0:n-3}
    elif (( n > 4 )) && [[ "${s:n-5:1}" == [+-] ]]; then
        tzs=${s:n-5}; s=${s:0:n-5}
    elif (( n > 5 )) && [[ "${s:n-6:1}" == [+-] ]]; then
        tzs=${s:n-6}; s=${s:0:n-6}
    fi
    if dateutils._iso_datetime "$s"; then
        kdt=$REPLY
        dateutils._tz_offset_east "$tzs" || return 1
        __kdt_tzoff_min=$REPLY
        if [[ -n "$tzs" ]]; then __kdt_has_tz=1; else __kdt_has_tz=0; fi
        REPLY=$kdt
        return 0
    fi
    __kdt_has_tz=0
    __kdt_tzoff_min=0
    dateutils._iso_date "${1:-}"
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

# _local_offset_ms [EPOCH_SECONDS] -> REPLY = the local offset EAST of UTC, in
# ms, IN FORCE AT THAT INSTANT. No argument (or -1) = right now.
#
# G3-05 / default R7: the old body always passed -1, so every conversion used
# today's offset — in a DST zone a January date was converted with the July
# rule and back. FPC asks for the offset of the VALUE
# (GetLocalTimeOffset(AValue, AInputIsUTC)).
#
# `printf '%(%z)T' <epoch>` is date-aware and parses a POSIX TZ string itself,
# so this works with no tzdata (verified on this MSYS2 box: with
# TZ=EST5EDT,M3.2.0,M11.1.0 a January epoch gives -0500 and a July one -0400).
# It is a builtin: still zero forks (kcl/README.md 1.8).
dateutils._local_offset_ms() {
    local z sign hh mm secs
    printf -v z '%(%z)T' "${1:--1}"               # e.g. +0300 / -0500
    sign="${z:0:1}"; hh="${z:1:2}"; mm="${z:3:2}"
    secs=$(( 10#$hh * 3600 + 10#$mm * 60 ))
    [[ "$sign" == "-" ]] && secs=$(( -secs ))
    REPLY=$(( secs * 1000 ))
}

# _now_local_ms -> REPLY = local naive now in ms.
dateutils._now_local_ms() {
    local u off
    dateutils._now_utc_ms;      u=$REPLY
    dateutils._local_offset_ms -1; off=$REPLY     # `now` IS the current instant
    REPLY=$(( u + off ))
}

# _floor_day KDT -> REPLY = day number (floor(KDT / MS_PER_DAY)). Validating
# form; `_i` is the core for a KDT that is already a normalised integer.
dateutils._floor_day() {
    local kdt
    REPLY=0
    kk.isInt "${1:-}" kdt || return 1
    dateutils._floor_day_i "$kdt"
}
dateutils._floor_day_i() {
    local kdt=$1 d
    d=$(( kdt / 86400000 ))
    if (( kdt - d*86400000 < 0 )); then d=$(( d - 1 )); fi
    REPLY=$d
}

# --- calendar predicates / sizes (used by P1 validity & encode) -------------

# _is_leap YEAR -> REPLY = 1 (leap) / 0. Proleptic Gregorian, matches SysUtils.
# The year MUST already be a normalised integer: every caller either validated
# it (daysInAYear, isValidDateDay, _weeks_in_year, _valid_date via
# _days_in_month) or computed it (incYear, _split_kdt output).
dateutils._is_leap() {
    local y=$1
    if (( y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) )); then REPLY=1; else REPLY=0; fi
}

# _days_in_month YEAR MONTH -> REPLY = day count (0 for an invalid month).
# Both fields MUST already be normalised integers — `08` here would be an octal
# parse error (G3-01). Every caller has them: _valid_date and endOfAMonth
# validate, daysInAMonth validates, the rest read them out of _split_kdt.
dateutils._days_in_month() {
    case "$2" in
        1|3|5|7|8|10|12) REPLY=31 ;;
        4|6|9|11)        REPLY=30 ;;
        2)               dateutils._is_leap "$1"; REPLY=$(( 28 + REPLY )) ;;
        *)               REPLY=0 ;;
    esac
}

# _weeks_in_year YEAR -> REPLY = 52 or 53 (ISO-8601). FPC WeeksInAYear: 52, +1
# if Jan 1 is Thursday, or Wednesday in a leap year. rc 1 on a bad year.
dateutils._weeks_in_year() {
    local y dow leap days
    REPLY=0
    kk.isInt "${1:-}" y || return 1
    dateutils._days_from_civil_i "$y" 1 1; days=$REPLY
    dow=$(( ( (days + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of Jan 1
    dateutils._is_leap "$y"; leap=$REPLY
    if (( dow == 4 || (dow == 3 && leap) )); then REPLY=53; else REPLY=52; fi
}

# _valid_date YEAR MONTH DAY -> REPLY = 1/0 (FPC IsValidDate: year 1..9999),
# and, when REPLY is 1, the NORMALISED fields in __kdt_vy __kdt_vmo __kdt_vd.
dateutils._valid_date() {
    # G3-01 / G3-04 (X-INJ, decision D1): these fields arrive straight from
    # `IFS=- read y m d`, so `08`/`09` are the NORMAL case and an octal parse
    # error here made `isValidDate 2011 08 15` answer false; a field shaped like
    # `x[$(cmd)]` executed the command inside (( )). kk.isInt validates and
    # rewrites the value as decimal.
    #
    # The normalised values are published because the encode* members must not
    # hand the RAW strings to _join_kdt afterwards — that is where `08` used to
    # reach `(( ))` a second time (G3-01).
    local y m d
    REPLY=0
    # rc 1 means "not a number at all" — a malformed CALL, which the boolean
    # members must report as rc 1 + RESULT="" rather than as the answer `false`
    # (kcl/README.md 1.2). rc 0 means the fields ARE numbers and REPLY carries
    # the yes/no answer.
    kk.isInt "${1:-}" y || return 1
    kk.isInt "${2:-}" m || return 1
    kk.isInt "${3:-}" d || return 1
    (( y >= 1 && y <= 9999 && m >= 1 && m <= 12 && d >= 1 )) || return 0
    dateutils._days_in_month "$y" "$m"
    if (( d <= REPLY )); then
        __kdt_vy=$y __kdt_vmo=$m __kdt_vd=$d
        REPLY=1
    else
        REPLY=0
    fi
}

# _valid_time HOUR MIN SEC MS -> REPLY = 1/0, normalised fields in
# __kdt_vh __kdt_vmi __kdt_vs __kdt_vms. FPC DateUtils.IsValidTime
# (dateutil.inc:535): 24:00:00.000 is valid (the whole-day marker), else
# h<24 & m<60 & s<60 & ms<1000.
dateutils._valid_time() {
    # Same as _valid_date: `08`/`09` are ordinary time fields (G3-01, D1).
    local h mi s ms
    REPLY=0
    kk.isInt "${1:-}" h  || return 1     # rc 1 = not a number (see _valid_date)
    kk.isInt "${2:-}" mi || return 1
    kk.isInt "${3:-}" s  || return 1
    kk.isInt "${4:-0}" ms || return 1
    if (( h == 24 && mi == 0 && s == 0 && ms == 0 )) || \
       (( h >= 0 && h < 24 && mi >= 0 && mi < 60 && s >= 0 && s < 60 && ms >= 0 && ms < 1000 )); then
        __kdt_vh=$h __kdt_vmi=$mi __kdt_vs=$s __kdt_vms=$ms
        REPLY=1
    else
        REPLY=0
    fi
}

# _encodable_time HOUR MIN SEC MS -> REPLY = 1/0, same normalised outputs.
# This is SysUtils.TryEncodeTime (rtl/objpas/sysutils/dati.inc:117-123):
#
#     Result := (Hour<24) and (Min<60) and (Sec<60) and (MSec<1000);
#
# which is NOT IsValidTime: FPC accepts 24:00:00.000 as a valid time and still
# refuses to ENCODE it, so `EncodeDateTime(9999,12,31,24,0,0,0)` raises instead
# of silently producing year 10000 (finding G3-10). Both halves are FPC.
dateutils._encodable_time() {
    local h mi s ms
    REPLY=0
    kk.isInt "${1:-}" h  || return 1     # rc 1 = not a number (see _valid_date)
    kk.isInt "${2:-}" mi || return 1
    kk.isInt "${3:-}" s  || return 1
    kk.isInt "${4:-0}" ms || return 1
    if (( h >= 0 && h < 24 && mi >= 0 && mi < 60 && s >= 0 && s < 60 && ms >= 0 && ms < 1000 )); then
        __kdt_vh=$h __kdt_vmi=$mi __kdt_vs=$s __kdt_vms=$ms
        REPLY=1
    else
        REPLY=0
    fi
}

# _debug MSG -> stderr, only under VERBOSE_KKLASS=debug (encode* error channel).
dateutils._debug() { kk.debug "dateutils: $*"; return 0; }

# _decode_date_week KDT -> __kdt_wy_year __kdt_wy_week __kdt_wy_dow (ISO-8601).
# Faithful port of FPC DecodeDateWeek (recurses once into the prior year for
# early-January days that belong to the last ISO week of the previous year).
dateutils._decode_date_week() {
    local kdt
    kk.isInt "${1:-}" kdt || return 1            # G3-04
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$kdt"
    local year=$__kdt_y dow ys_day doy ysdow week yedow leap
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._days_from_civil_i "$year" 1 1; ys_day=$REPLY
    doy=$(( __kdt_day - ys_day + 1 ))
    ysdow=$(( ( (ys_day + 3) % 7 + 7 ) % 7 + 1 ))       # ISO weekday of Jan 1
    if (( ysdow < 5 )); then doy=$(( doy + ysdow - 1 )); else doy=$(( doy - (8 - ysdow) )); fi
    if (( doy <= 0 )); then                              # last week of previous year
        dateutils._decode_date_week "$(( (ys_day - 1) * 86400000 ))"
        __kdt_wy_dow=$dow
        return
    fi
    week=$(( doy / 7 )); if (( doy % 7 != 0 )); then week=$(( week + 1 )); fi
    if (( week > 52 )); then                             # maybe first week of next year
        yedow=$ysdow
        dateutils._is_leap "$year"; leap=$REPLY
        if (( leap )); then yedow=$(( yedow + 1 )); if (( yedow > 7 )); then yedow=1; fi; fi
        if (( yedow < 4 )); then year=$(( year + 1 )); week=1; fi
    fi
    __kdt_wy_year=$year; __kdt_wy_week=$week; __kdt_wy_dow=$dow
}

# _decode_date_month_week KDT -> __kdt_mw_year __kdt_mw_month __kdt_mw_week
# __kdt_mw_dow. Faithful port of FPC DecodeDateMonthWeek.
dateutils._decode_date_month_week() {
    local kdt
    kk.isInt "${1:-}" kdt || return 1            # G3-04
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$kdt"
    local year=$__kdt_y month=$__kdt_mo d=$__kdt_d dow som_day sdom dom week dim eom_day edom
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._days_from_civil_i "$year" "$month" 1; som_day=$REPLY
    sdom=$(( ( (som_day + 3) % 7 + 7 ) % 7 + 1 ))        # ISO weekday of the 1st
    dom=$(( d - 1 + sdom )); if (( sdom > 4 )); then dom=$(( dom - 7 )); fi
    if (( dom <= 0 )); then                              # belongs to previous month
        dateutils._decode_date_month_week "$(( (som_day - 1) * 86400000 ))"
        __kdt_mw_dow=$dow
        return
    fi
    week=$(( dom / 7 )); if (( dom % 7 != 0 )); then week=$(( week + 1 )); fi
    dateutils._days_in_month "$year" "$month"; dim=$REPLY
    dateutils._days_from_civil_i "$year" "$month" "$dim"; eom_day=$REPLY
    edom=$(( ( (eom_day + 3) % 7 + 7 ) % 7 + 1 ))        # ISO weekday of the last day
    if (( edom < 4 && (dim - d) < edom )); then          # tail days spill into next month
        week=1; month=$(( month + 1 ))
        if (( month == 13 )); then month=1; year=$(( year + 1 )); fi
    fi
    __kdt_mw_year=$year; __kdt_mw_month=$month; __kdt_mw_week=$week; __kdt_mw_dow=$dow
}

# _encode_date_week YEAR WEEK DOW -> REPLY = KDT at 00:00; return 1 if the
# (year, week, dow) triple is invalid. Faithful port of FPC TryEncodeDateWeek;
# reused by startOfAWeek/endOfAWeek (P3) and encodeDateWeek/decodeDateWeek (P5).
dateutils._encode_date_week() {
    local y w dow base dowb rest
    kk.isInt "${1:-}" y   || return 1
    kk.isInt "${2:-}" w   || return 1
    kk.isInt "${3:-}" dow || return 1
    dateutils._weeks_in_year "$y" || return 1
    (( y >= 1 && y <= 9999 && dow >= 1 && dow <= 7 && w >= 1 && w <= REPLY )) || return 1
    dateutils._days_from_civil_i "$y" 1 1
    base=$(( REPLY + 7*(w-1) ))
    dowb=$(( ( (base + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of that Monday-anchor
    rest=$(( dow - dowb )); if (( dowb > 4 )); then rest=$(( rest + 7 )); fi
    REPLY=$(( (base + rest) * 86400000 ))
}

# _period_between NOW THEN -> __kdt_pb_y __kdt_pb_m __kdt_pb_d (calendar
# decomposition of |NOW-THEN|, date parts only). Faithful port of FPC
# PeriodBetween with its month/day borrow logic.
dateutils._period_between() {
    local lo hi __du_a __du_b
    dateutils._two "${1:-}" "${2:-}" || return 1
    if (( __du_b > __du_a )); then lo=$__du_a; hi=$__du_b; else lo=$__du_b; hi=$__du_a; fi
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "$lo"; local y1=$__kdt_y m1=$__kdt_mo d1=$__kdt_d
    dateutils._split_kdt "$hi"; local y2=$__kdt_y m2=$__kdt_mo d2=$__kdt_d
    local years=$(( y2 - y1 )) months days
    if (( m1 > m2 || (m1 == m2 && d1 > d2) )); then years=$(( years - 1 )); fi
    if (( m1 > m2 )); then m2=$(( m2 + 12 )); fi
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
# G3-04 (X-INJ, decision D1): the one-liner members below take two (sometimes
# three) caller-supplied KDT values straight into `(( ))`, which EVALUATES an
# array subscript — `incDay 'x[$(cmd)]'` ran the command, and an empty string
# silently became the epoch. This validates and 10#-normalises them in one call;
# the caller declares `local __du_a __du_b __du_c` and uses those.
#
# P1 covers the shared helpers plus the entry points the review reproduced. The
# remaining public members get their guard in P6, where decision D3 rewrites
# every body as `func` + kk._return and the boundary is touched once anyway
# (finding G3-04 is therefore "partial" in the ledger until then).
# P6 completes G3-04: every remaining public member validates too, either
# through one of these three or through _split_kdt / _valid_date / _valid_time /
# _jd_str_to_ms, which all reject and normalise. dateutils/tests/018 walks the
# whole interface and proves it.
#
# These three end on a `&&` list on purpose — they ARE rc predicates, and every
# call site is under `|| return` or `if !` (X-SETE, PLAN.md P1 note).
dateutils._one()   { kk.isInt "${1:-}" __du_a; }
dateutils._two()   { kk.isInt "${1:-}" __du_a && kk.isInt "${2:-}" __du_b; }
dateutils._three() { dateutils._two "${1:-}" "${2:-}" && kk.isInt "${3:-}" __du_c; }

# G3-03: the sign has to come off FIRST. bash truncates division toward zero,
# so for a negative numerator `whole` was 0 and `frac` was -500000, and the two
# were printed side by side as `0.-500000` — malformed, and the inverse member
# could not read it back. Every Modified Julian Date before 1858-11-17 hit this.
dateutils._span_fixed() {
    local n=$1 div=$2 sign='' whole frac
    if (( n < 0 )); then
        sign='-'
        n=$(( -n ))
    fi
    whole=$(( n / div ))
    frac=$(( (n % div) * 1000000 / div ))
    printf -v REPLY '%s%d.%06d' "$sign" "$whole" "$frac"
}

# _recode DT Y M D H N S MS -> REPLY = KDT, return 1 if invalid. Any field equal
# to the literal '-' (RecodeLeaveFieldAsIs) keeps the original. FPC TryRecodeDateTime.
dateutils._recode() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || return 1
    local y=$__kdt_y m=$__kdt_mo d=$__kdt_d h=$__kdt_h n=$__kdt_mi s=$__kdt_s ms=$__kdt_ms
    [[ "${2:--}" != - ]] && y=$2;  [[ "${3:--}" != - ]] && m=$3;  [[ "${4:--}" != - ]] && d=$4
    [[ "${5:--}" != - ]] && h=$5;  [[ "${6:--}" != - ]] && n=$6
    [[ "${7:--}" != - ]] && s=$7;  [[ "${8:--}" != - ]] && ms=$8
    dateutils._valid_date "$y" "$m" "$d" || return 1
    (( REPLY )) || return 1
    dateutils._encodable_time "$h" "$n" "$s" "$ms" || return 1
    (( REPLY )) || return 1
    dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" \
                        "$__kdt_vh" "$__kdt_vmi" "$__kdt_vs" "$__kdt_vms"
}

# _encode_date_month_week YEAR MONTH WEEKOFMONTH DOW -> REPLY = KDT@00:00,
# return 1 if invalid. Faithful port of FPC TryEncodeDateMonthWeek (the result
# may fall in an adjacent month — FPC only range-checks the inputs).
dateutils._encode_date_month_week() {
    local y mo wom dow base dom s
    kk.isInt "${1:-}" y   || return 1
    kk.isInt "${2:-}" mo  || return 1
    kk.isInt "${3:-}" wom || return 1
    kk.isInt "${4:-}" dow || return 1
    (( y >= 1 && y <= 9999 && mo >= 1 && mo <= 12 && wom >= 1 && wom <= 5 && dow >= 1 && dow <= 7 )) || return 1
    dateutils._days_from_civil_i "$y" "$mo" 1; base=$REPLY
    dom=$(( (wom-1)*7 + dow - 1 ))
    s=$(( ( (base + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of the 1st
    dom=$(( dom - (s - 1) ))
    if (( s >= 5 )); then dom=$(( dom + 7 )); fi           # S in [Fri..Sun]
    REPLY=$(( (base + dom) * 86400000 ))
}

# _encode_dow_in_month YEAR MONTH NTH DOW -> REPLY = KDT@00:00, return 1 if the
# Nth weekday does not exist that month. Faithful port of FPC
# TryEncodeDayOfWeekInMonth. NOTE: FPC ANthDayOfWeek is Word (>=1) — there is no
# negative/"last" form (see TEST_COVERAGE_NOTES.md).
dateutils._encode_dow_in_month() {
    local y mo nth dow som d
    kk.isInt "${1:-}" y   || return 1
    kk.isInt "${2:-}" mo  || return 1
    kk.isInt "${3:-}" nth || return 1
    kk.isInt "${4:-}" dow || return 1
    (( nth >= 1 && dow >= 1 && dow <= 7 )) || return 1
    dateutils._days_from_civil_i "$y" "$mo" 1
    som=$(( ( (REPLY + 3) % 7 + 7 ) % 7 + 1 ))   # ISO weekday of the 1st
    d=$(( 1 + dow - som + 7*(nth-1) ))
    if (( som > dow )); then d=$(( d + 7 )); fi
    dateutils._valid_date "$y" "$mo" "$d" || return 1
    (( REPLY )) || return 1
    dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" 0 0 0 0
}

# _jd_str_to_ms JDSTR -> REPLY = round(JD * 86400000) as an integer numerator.
# KDT day 0 (1970-01-01) is JD 2440587.5, so JD = 2440587.5 + KDT/86400000,
# i.e. KDT = REPLY - 210866760000000 (= 2440587.5 * 86400000). Frac parsed to
# 9 digits (rounded); frac9*86400000 < 9.2e18 so no int64 overflow.
dateutils._jd_str_to_ms() {
    # G3-04 (X-INJ, D1): `whole` and `frac` end up under `10#` inside (( )),
    # which evaluates an array subscript — a JD string shaped like `x[$(cmd)]`
    # ran the command. kk.isNum accepts exactly the JD shape ([+-]d[.d]) and
    # rejects everything else before the split.
    local s sign=1 whole frac
    REPLY=0
    kk.isNum "${1:-}" s || return 1
    [[ "$s" == -* ]] && { sign=-1; s=${s#-}; }
    [[ "$s" == +* ]] && s=${s#+}
    if [[ "$s" == *.* ]]; then whole=${s%%.*}; frac=${s#*.}; else whole=$s; frac=0; fi
    whole=${whole:-0}; frac=${frac:-0}; frac=${frac}000000000; frac=${frac:0:9}
    REPLY=$(( sign * (10#$whole * 86400000 + (10#$frac * 86400000 + 500000000) / 1000000000) ))
}

# _normalize_offset_min_east ARG -> REPLY = minutes EAST of UTC; return 1 if bad.
# Accepts integer minutes (+/-), 'Z'/'' (0), or '±hh[:]mm' / '±hh'.
dateutils._normalize_offset_min_east() {
    local a="${1:-}"
    REPLY=0
    if [[ "$a" == Z || -z "$a" ]]; then return 0; fi
    # `+180` and `-0060` are plain minute counts; kk.isInt strips the sign and
    # the leading zeros, so `060` is 60 rather than an octal parse error.
    if kk.isInt "$a"; then REPLY=$__KK_INT; return 0; fi
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

# _jd_to_kdt JDSTR EPOCH_MS -> REPLY = KDT; rc 1 on a malformed string or on a
# result outside year 1..9999. G3-07: the four public members used to ignore
# _jd_str_to_ms's exit status, so `modifiedJulianDateToDateTime ''` answered the
# MJD epoch with rc 0.
dateutils._jd_to_kdt() {
    local kdt
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._jd_str_to_ms "${1:-}" || return 1
    kdt=$(( REPLY - $2 ))
    dateutils._split_kdt "$kdt" || return 1
    (( __kdt_y >= 1 && __kdt_y <= 9999 )) || return 1
    REPLY=$kdt
    return 0
}

# _time_interval H M S MS -> REPLY = ms; rc 1 if invalid.
# FPC TryEncodeTimeInterval (dateutil.inc:1899) takes four `word`s and tests
# `(Min<60) and (Sec<60) and (MSec<1000)`. A `word` cannot be negative and
# cannot exceed 65535 — G3-06: the port accepted `-5` and, on the strength of a
# wrong comment, MSec = 1000.
dateutils._time_interval() {
    local h m s ms
    kk.isInt "${1:-}" h  || return 1
    kk.isInt "${2:-}" m  || return 1
    kk.isInt "${3:-}" s  || return 1
    kk.isInt "${4:-}" ms || return 1
    (( h >= 0 && h <= 65535 && m >= 0 && m < 60 && s >= 0 && s < 60 && ms >= 0 && ms < 1000 )) || return 1
    REPLY=$(( h*3600000 + m*60000 + s*1000 + ms ))
    return 0
}


# ===========================================================================
# Method bodies (real bash functions; extracted by `build`).
#
# `static proc` + dateutils._ret, NOT `printf` and NOT `static func`
# (decision D3, kcl/README.md 1.1): a direct call is silent and sets RESULT,
# `$( )` prints the value exactly once. Boolean members answer through
# dateutils._retBool — rc AND the word true|false (default R8).
#
# Every member validates its numeric arguments before they reach `(( ))`,
# either directly (kk.isInt / _one / _two / _three) or through a helper that
# does (_split_kdt, _floor_day, _valid_date, _valid_time, _encodable_time,
# _days_from_civil, _weekday_iso, _days_in_month, _weeks_in_year,
# _jd_str_to_ms) — findings G3-01 and G3-04, decision D1.
#
# The failure contract is rc 1 + RESULT='' + silence (kcl/README.md 1.2); the
# `x || { RESULT=""; return 1; }` idiom is used because it is safe under
# `set -e` (the assignment cannot fail, and the explicit `return` follows).
# ===========================================================================

# --- wall clock & trivial constructors ---
dateutils.now()    { dateutils._now_local_ms; dateutils._ret "$REPLY"; }
dateutils.nowUTC() { dateutils._now_utc_ms;   dateutils._ret "$REPLY"; }
dateutils.today()     { dateutils._now_local_ms; dateutils._floor_day_i "$REPLY"; dateutils._ret $(( REPLY * 86400000 )); }
dateutils.yesterday() { dateutils._now_local_ms; dateutils._floor_day_i "$REPLY"; dateutils._ret $(( (REPLY - 1) * 86400000 )); }
dateutils.tomorrow()  { dateutils._now_local_ms; dateutils._floor_day_i "$REPLY"; dateutils._ret $(( (REPLY + 1) * 86400000 )); }

# dateOf: drop the time-of-day (floor to midnight). timeOf: keep only it.
dateutils.dateOf() {
    dateutils._floor_day "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.timeOf() {
    local __du_a
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"
    dateutils._ret $(( __du_a - REPLY * 86400000 ))
}

# --- public constant getters ---
dateutils.msPerSecond()        { dateutils._ret "$__KDT_MS_PER_SECOND"; }
dateutils.msPerMinute()        { dateutils._ret "$__KDT_MS_PER_MINUTE"; }
dateutils.msPerHour()          { dateutils._ret "$__KDT_MS_PER_HOUR"; }
dateutils.msPerDay()           { dateutils._ret "$__KDT_MS_PER_DAY"; }
dateutils.msPerWeek()          { dateutils._ret "$__KDT_MS_PER_WEEK"; }
dateutils.approxMsPerMonth()   { dateutils._ret "$__KDT_APPROX_MS_PER_MONTH"; }
dateutils.approxMsPerYear()    { dateutils._ret "$__KDT_APPROX_MS_PER_YEAR"; }
dateutils.approxDaysPerMonth() { dateutils._ret "$__KDT_APPROX_DAYS_PER_MONTH"; }
dateutils.approxDaysPerYear()  { dateutils._ret "$__KDT_APPROX_DAYS_PER_YEAR"; }

# --- P1: encode / decode ---------------------------------------------------
# encode* log under VERBOSE_KKLASS=debug and return 1; try* are identical but
# silent. FPC raises EConvertError where we return 1 (bash has no exceptions).
#
# The TIME rule here is SysUtils.TryEncodeTime (`Hour < 24`), not
# DateUtils.IsValidTime (which also accepts the 24:00:00.000 whole-day marker):
# that asymmetry is FPC's own, and it is what stops
# `encodeDateTime 9999 12 31 24 0 0 0` from producing year 10000 (G3-10).

dateutils.tryEncodeDate() {
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" 0 0 0 0
    dateutils._ret "$REPLY"
}
dateutils.encodeDate() {
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || REPLY=0
    if (( REPLY )); then
        dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" 0 0 0 0
        dateutils._ret "$REPLY"
    else
        dateutils._debug "invalid date ${1:-}-${2:-}-${3:-}"
        RESULT=""
        return 1
    fi
}

dateutils.tryEncodeTime() {
    dateutils._encodable_time "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._ret $(( __kdt_vh*3600000 + __kdt_vmi*60000 + __kdt_vs*1000 + __kdt_vms ))
}
dateutils.encodeTime() {
    dateutils._encodable_time "${1:-}" "${2:-}" "${3:-}" "${4:-}" || REPLY=0
    if (( REPLY )); then
        dateutils._ret $(( __kdt_vh*3600000 + __kdt_vmi*60000 + __kdt_vs*1000 + __kdt_vms ))
    else
        dateutils._debug "invalid time ${1:-}:${2:-}:${3:-}.${4:-}"
        RESULT=""
        return 1
    fi
}

dateutils.tryEncodeDateTime() {
    local y mo d
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    y=$__kdt_vy mo=$__kdt_vmo d=$__kdt_vd
    dateutils._encodable_time "${4:-}" "${5:-}" "${6:-}" "${7:-}" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$y" "$mo" "$d" "$__kdt_vh" "$__kdt_vmi" "$__kdt_vs" "$__kdt_vms"
    dateutils._ret "$REPLY"
}
dateutils.encodeDateTime() {
    local y mo d vd
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || REPLY=0
    vd=$REPLY
    if (( vd )); then y=$__kdt_vy mo=$__kdt_vmo d=$__kdt_vd; fi
    dateutils._encodable_time "${4:-}" "${5:-}" "${6:-}" "${7:-}" || REPLY=0
    if (( vd && REPLY )); then
        dateutils._join_kdt "$y" "$mo" "$d" "$__kdt_vh" "$__kdt_vmi" "$__kdt_vs" "$__kdt_vms"
        dateutils._ret "$REPLY"
    else
        dateutils._debug "invalid datetime ${1:-}-${2:-}-${3:-} ${4:-}:${5:-}:${6:-}.${7:-}"
        RESULT=""
        return 1
    fi
}

dateutils.decodeDate() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_y $__kdt_mo $__kdt_d"
}
dateutils.decodeTime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_h $__kdt_mi $__kdt_s $__kdt_ms"
}
dateutils.decodeDateTime() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_y $__kdt_mo $__kdt_d $__kdt_h $__kdt_mi $__kdt_s $__kdt_ms"
}

# encodeDateDay: date from (year, day-of-year 1..365/366). FPC's try* omits the
# year check (it raises inside EncodeDate); we treat "would-raise" as failure,
# so try* here validates year 1..9999 too (== isValidDateDay + compute).
dateutils._date_day() {   # YEAR DOY -> REPLY = KDT@00:00, rc 1 if invalid
    local y doy dpy
    kk.isInt "${1:-}" y   || return 1
    kk.isInt "${2:-}" doy || return 1
    dateutils._is_leap "$y"
    dpy=$(( 365 + REPLY ))
    (( y >= 1 && y <= 9999 && doy >= 1 && doy <= dpy )) || return 1
    dateutils._days_from_civil_i "$y" 1 1
    REPLY=$(( (REPLY + doy - 1) * 86400000 ))
    return 0
}
dateutils.tryEncodeDateDay() {
    dateutils._date_day "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.encodeDateDay() {
    if dateutils._date_day "${1:-}" "${2:-}"; then
        dateutils._ret "$REPLY"
    else
        dateutils._debug "invalid date-day ${1:-}/${2:-}"
        RESULT=""
        return 1
    fi
}
dateutils.decodeDateDay() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    dateutils._ret "$__kdt_y $(( __kdt_day - ys + 1 ))"
}

# --- P1: validity & calendar sizes -----------------------------------------
# A field that is not a number at all is a malformed CALL: rc 1 with RESULT=''
# (kcl/README.md 1.2), NOT the answer `false`. A field that IS a number but out
# of range is the answer `false` (rc 1 with RESULT='false', default R8). Both
# are rc 1; RESULT tells them apart, exactly as tstringhelper.toBoolean does.
dateutils.isValidDate() {
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    if (( REPLY )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isValidTime() {
    dateutils._valid_time "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { RESULT=""; return 1; }
    if (( REPLY )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isValidDateTime() {
    local vd
    dateutils._valid_date "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    vd=$REPLY
    dateutils._valid_time "${4:-}" "${5:-}" "${6:-}" "${7:-}" || { RESULT=""; return 1; }
    if (( vd && REPLY )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isValidDateDay() {
    local y doy dpy
    kk.isInt "${1:-}" y   || { RESULT=""; return 1; }
    kk.isInt "${2:-}" doy || { RESULT=""; return 1; }
    dateutils._is_leap "$y"
    dpy=$(( 365 + REPLY ))
    if (( y >= 1 && y <= 9999 && doy >= 1 && doy <= dpy )); then
        dateutils._retBool 0
    else
        dateutils._retBool 1
    fi
}
dateutils.isValidDateWeek() {
    local y w dow
    kk.isInt "${1:-}" y   || { RESULT=""; return 1; }
    kk.isInt "${2:-}" w   || { RESULT=""; return 1; }
    kk.isInt "${3:-}" dow || { RESULT=""; return 1; }
    dateutils._weeks_in_year "$y"
    if (( y >= 1 && y <= 9999 && dow >= 1 && dow <= 7 && w >= 1 && w <= REPLY )); then
        dateutils._retBool 0
    else
        dateutils._retBool 1
    fi
}
dateutils.isValidDateMonthWeek() {
    local y m wom dow
    kk.isInt "${1:-}" y   || { RESULT=""; return 1; }
    kk.isInt "${2:-}" m   || { RESULT=""; return 1; }
    kk.isInt "${3:-}" wom || { RESULT=""; return 1; }
    kk.isInt "${4:-}" dow || { RESULT=""; return 1; }
    if (( y >= 1 && y <= 9999 && m >= 1 && m <= 12 && wom >= 1 && wom <= 5 && dow >= 1 && dow <= 7 )); then
        dateutils._retBool 0
    else
        dateutils._retBool 1
    fi
}
dateutils.isInLeapYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._is_leap "$__kdt_y"
    if (( REPLY )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.daysInAMonth() {
    local y m
    kk.isInt "${1:-}" y || { RESULT=""; return 1; }
    kk.isInt "${2:-}" m || { RESULT=""; return 1; }
    dateutils._days_in_month "$y" "$m"
    (( REPLY > 0 )) || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.daysInMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_in_month "$__kdt_y" "$__kdt_mo"
    dateutils._ret "$REPLY"
}
dateutils.daysInAYear() {
    local y
    kk.isInt "${1:-}" y || { RESULT=""; return 1; }
    dateutils._is_leap "$y"
    dateutils._ret $(( 365 + REPLY ))
}
dateutils.daysInYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._is_leap "$__kdt_y"
    dateutils._ret $(( 365 + REPLY ))
}
dateutils.weeksInAYear() {
    dateutils._weeks_in_year "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.weeksInYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._weeks_in_year "$__kdt_y"
    dateutils._ret "$REPLY"
}

# --- P2: simple field extractors -------------------------------------------
dateutils.yearOf()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_y"; }
dateutils.monthOf()       { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_mo"; }
dateutils.dayOf()         { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_d"; }
dateutils.hourOf()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_h"; }
dateutils.minuteOf()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_mi"; }
dateutils.secondOf()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_s"; }
dateutils.milliSecondOf() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret "$__kdt_ms"; }
# aliases / ISO-week. A tail call to another member is the whole body, so the
# value is returned (and printed under `$( )`) exactly once.
dateutils.monthOfTheYear() { dateutils.monthOf "${1:-}"; }
dateutils.dayOfTheMonth()  { dateutils.dayOf "${1:-}"; }
dateutils.dayOfTheWeek() {                                    # ISO Mon=1..Sun=7
    # _weekday_iso inlined: this is the hottest single-field extractor and the
    # kk.isInt the boundary now owes (G3-04) already costs ~52 us of its budget.
    local __du_a d
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    d=$(( __du_a / 86400000 ))
    if (( __du_a - d*86400000 < 0 )); then d=$(( d - 1 )); fi
    dateutils._ret $(( ( (d + 3) % 7 + 7 ) % 7 + 1 ))
}
dateutils.dayOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    dateutils._ret $(( __kdt_day - ys + 1 ))
}
dateutils.weekOfTheYear() {
    dateutils._decode_date_week "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_wy_week"
}
dateutils.weekOf() { dateutils.weekOfTheYear "${1:-}"; }
dateutils.weekOfTheMonth() {
    dateutils._decode_date_month_week "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_mw_week"
}
dateutils.isAM() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    if (( __kdt_h < 12 )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isPM() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    if (( __kdt_h >= 12 )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}

# --- P2: OfThe* families (units elapsed since the start of the larger period)
# Same-unit aliases:
dateutils.hourOfTheDay()          { dateutils.hourOf "${1:-}"; }
dateutils.minuteOfTheHour()       { dateutils.minuteOf "${1:-}"; }
dateutils.secondOfTheMinute()     { dateutils.secondOf "${1:-}"; }
dateutils.milliSecondOfTheSecond(){ dateutils.milliSecondOf "${1:-}"; }
# ...of the day
dateutils.minuteOfTheDay()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( __kdt_h*60 + __kdt_mi )); }
dateutils.secondOfTheDay()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( (__kdt_h*60 + __kdt_mi)*60 + __kdt_s )); }
dateutils.milliSecondOfTheDay() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( ((__kdt_h*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the hour
dateutils.secondOfTheHour()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( __kdt_mi*60 + __kdt_s )); }
dateutils.milliSecondOfTheHour() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( (__kdt_mi*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the minute
dateutils.milliSecondOfTheMinute() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( __kdt_s*1000 + __kdt_ms )); }
# ...of the week (Monday-based; dow 1..7)
dateutils.hourOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._ret $(( (dow-1)*24 + __kdt_h ))
}
dateutils.minuteOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._ret $(( ((dow-1)*24 + __kdt_h)*60 + __kdt_mi ))
}
dateutils.secondOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._ret $(( (((dow-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s ))
}
dateutils.milliSecondOfTheWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._ret $(( ((((dow-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms ))
}
# ...of the month (D = day-of-month)
dateutils.hourOfTheMonth()        { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( (__kdt_d-1)*24 + __kdt_h )); }
dateutils.minuteOfTheMonth()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( ((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi )); }
dateutils.secondOfTheMonth()      { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( (((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s )); }
dateutils.milliSecondOfTheMonth() { local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow; dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }; dateutils._ret $(( ((((__kdt_d-1)*24 + __kdt_h)*60 + __kdt_mi)*60 + __kdt_s)*1000 + __kdt_ms )); }
# ...of the year (via day-of-year)
dateutils.hourOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys doy
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    doy=$(( __kdt_day - ys + 1 ))
    dateutils._ret $(( __kdt_h + (doy-1)*24 ))
}
dateutils.minuteOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys doy
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    doy=$(( __kdt_day - ys + 1 ))
    dateutils._ret $(( __kdt_mi + (__kdt_h + (doy-1)*24)*60 ))
}
dateutils.secondOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys doy
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    doy=$(( __kdt_day - ys + 1 ))
    dateutils._ret $(( (__kdt_mi + (__kdt_h + (doy-1)*24)*60)*60 + __kdt_s ))
}
dateutils.milliSecondOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ys doy
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1; ys=$REPLY
    doy=$(( __kdt_day - ys + 1 ))
    dateutils._ret $(( ((__kdt_mi + (__kdt_h + (doy-1)*24)*60)*60 + __kdt_s)*1000 + __kdt_ms ))
}
# nth-weekday-in-month helpers
dateutils.nthDayOfWeek() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret $(( (__kdt_d - 1) / 7 + 1 ))
}
dateutils.decodeDayOfWeekInMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dow=$__kdt_dow                               # published by _split_kdt
    dateutils._ret "$__kdt_y $__kdt_mo $(( (__kdt_d - 1) / 7 + 1 )) $dow"
}

# --- P3: start/end of year --------------------------------------------------
dateutils.startOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" 1 1
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.startOfAYear() {
    dateutils._days_from_civil "${1:-}" 1 1 || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.endOfTheYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._join_kdt "$__kdt_y" 12 31 23 59 59 999
    dateutils._ret "$REPLY"
}
dateutils.endOfAYear() {
    local y
    kk.isInt "${1:-}" y || { RESULT=""; return 1; }
    dateutils._join_kdt "$y" 12 31 23 59 59 999
    dateutils._ret "$REPLY"
}

# --- P3: start/end of month -------------------------------------------------
dateutils.startOfTheMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_from_civil_i "$__kdt_y" "$__kdt_mo" 1
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.startOfAMonth() {
    dateutils._days_from_civil "${1:-}" "${2:-}" 1 || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.endOfTheMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow dim
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    dateutils._days_in_month "$__kdt_y" "$__kdt_mo"; dim=$REPLY
    dateutils._join_kdt "$__kdt_y" "$__kdt_mo" "$dim" 23 59 59 999
    dateutils._ret "$REPLY"
}
dateutils.endOfAMonth() {
    local y mo dim
    kk.isInt "${1:-}" y  || { RESULT=""; return 1; }
    kk.isInt "${2:-}" mo || { RESULT=""; return 1; }
    dateutils._days_in_month "$y" "$mo"; dim=$REPLY
    (( dim > 0 )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$y" "$mo" "$dim" 23 59 59 999
    dateutils._ret "$REPLY"
}

# --- P3: start/end of week (Monday-based, ISO) ------------------------------
dateutils.startOfTheWeek() {
    local __du_a dow day
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; day=$REPLY
    dow=$(( ( (day + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of that day
    dateutils._ret $(( (day - dow + 1) * 86400000 ))
}
dateutils.startOfAWeek() {
    dateutils._encode_date_week "${1:-}" "${2:-}" "${3:-1}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.endOfTheWeek() {
    local __du_a dow day
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; day=$REPLY
    dow=$(( ( (day + 3) % 7 + 7 ) % 7 + 1 ))     # ISO weekday of that day
    dateutils._ret $(( (day - dow + 7) * 86400000 + 86399999 ))
}
dateutils.endOfAWeek() {
    dateutils._encode_date_week "${1:-}" "${2:-}" "${3:-7}" || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY + 86399999 ))
}

# --- P3: start/end of day (start/endOfADay overload on arg count) -----------
dateutils.startOfTheDay() {
    dateutils._floor_day "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY * 86400000 ))
}
dateutils.startOfADay() {
    if (( $# == 3 )); then
        dateutils._days_from_civil "$1" "$2" "$3" || { RESULT=""; return 1; }
        dateutils._ret $(( REPLY * 86400000 ))
    else
        dateutils._date_day "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        dateutils._ret "$REPLY"
    fi
}
dateutils.endOfTheDay() {
    dateutils._floor_day "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret $(( REPLY * 86400000 + 86399999 ))
}
dateutils.endOfADay() {
    if (( $# == 3 )); then
        dateutils._days_from_civil "$1" "$2" "$3" || { RESULT=""; return 1; }
        dateutils._ret $(( REPLY * 86400000 + 86399999 ))
    else
        dateutils._date_day "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        dateutils._ret $(( REPLY + 86399999 ))
    fi
}

# --- P3: day predicates -----------------------------------------------------
# isSameDay truncates ONLY the basis (FPC quirk): value is in [floor(basis), +1day).
dateutils.isSameDay() {
    local __du_a __du_b base
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_b"; base=$(( REPLY * 86400000 ))
    if (( __du_a >= base && __du_a < base + 86400000 )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isToday() {
    local __du_a n base
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._now_local_ms; n=$REPLY
    dateutils._floor_day_i "$n"; base=$(( REPLY * 86400000 ))
    if (( __du_a >= base && __du_a < base + 86400000 )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.isSameMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow ya ma
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    ya=$__kdt_y; ma=$__kdt_mo
    dateutils._split_kdt "${2:-}" || { RESULT=""; return 1; }
    if (( ya == __kdt_y && ma == __kdt_mo )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
# previousDayOfWeek takes an ISO weekday NUMBER (1..7) and returns the prior one.
dateutils.previousDayOfWeek() {
    local d
    if ! kk.isInt "${1:-}" d || (( d < 1 || d > 7 )); then
        dateutils._debug "invalid day-of-week ${1:-}"
        RESULT=""
        return 1
    fi
    if (( d == 1 )); then dateutils._ret 7; else dateutils._ret $(( d - 1 )); fi
}

# --- P4: increment (default step = 1; time-of-day preserved) ----------------
# G3-10: FPC's IncYear (dateutil.inc:1561-1571) and SysUtils.IncMonth both end
# in EncodeDate(Y,M,D), which raises outside year 1..9999 — a result of year
# 10000 or 0 is an error, not an answer.
dateutils.incYear() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow n y d
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    kk.isInt "${2:-1}" n || { RESULT=""; return 1; }
    y=$(( __kdt_y + n ))
    d=$__kdt_d
    if (( __kdt_mo == 2 && d == 29 )); then
        dateutils._is_leap "$y"
        (( REPLY )) || d=28
    fi
    dateutils._valid_date "$y" "$__kdt_mo" "$d"
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$y" "$__kdt_mo" "$d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
    dateutils._ret "$REPLY"
}
dateutils.incMonth() {
    local __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms __kdt_n __kdt_day __kdt_dow n total newy newm dim d
    dateutils._split_kdt "${1:-}" || { RESULT=""; return 1; }
    kk.isInt "${2:-1}" n || { RESULT=""; return 1; }
    total=$(( __kdt_y*12 + __kdt_mo - 1 + n ))
    newy=$(( total / 12 )); if (( total % 12 < 0 )); then newy=$(( newy - 1 )); fi   # floor division
    newm=$(( total - newy*12 + 1 ))
    dateutils._days_in_month "$newy" "$newm"; dim=$REPLY
    d=$__kdt_d
    if (( dim > 0 && d > dim )); then d=$dim; fi                                     # clamp to month length
    dateutils._valid_date "$newy" "$newm" "$d"
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$newy" "$newm" "$d" "$__kdt_h" "$__kdt_mi" "$__kdt_s" "$__kdt_ms"
    dateutils._ret "$REPLY"
}
dateutils.incWeek()        { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b * 604800000 )); }
dateutils.incDay()         { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b * 86400000 )); }
dateutils.incHour()        { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b * 3600000 )); }
dateutils.incMinute()      { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b * 60000 )); }
dateutils.incSecond()      { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b * 1000 )); }
dateutils.incMilliSecond() { local __du_a __du_b; dateutils._two "${1:-}" "${2:-1}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a + __du_b )); }

# --- P4: between (|now-then| / unit; exact ones use periodBetween) -----------
dateutils.milliSecondsBetween() { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); dateutils._ret $(( d < 0 ? -d : d )); }
dateutils.secondsBetween()      { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._ret $(( d / 1000 )); }
dateutils.minutesBetween()      { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._ret $(( d / 60000 )); }
dateutils.hoursBetween()        { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._ret $(( d / 3600000 )); }
dateutils.daysBetween()         { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._ret $(( d / 86400000 )); }
dateutils.weeksBetween()        { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._ret $(( d / 86400000 / 7 )); }
# yearsBetween/monthsBetween: approximate by default (365.25 / 30.4375 days);
# 3rd arg "exact"/"true"/"1" switches to the calendar-true periodBetween.
dateutils.yearsBetween() {
    local __du_a __du_b d
    if [[ "${3:-}" == exact || "${3:-}" == true || "${3:-}" == 1 ]]; then
        dateutils._period_between "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        dateutils._ret "$__kdt_pb_y"
    else
        dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        d=$(( __du_a - __du_b )); if (( d < 0 )); then d=$(( -d )); fi
        dateutils._ret $(( d / 31557600000 ))
    fi
}
dateutils.monthsBetween() {
    local __du_a __du_b d
    if [[ "${3:-}" == exact || "${3:-}" == true || "${3:-}" == 1 ]]; then
        dateutils._period_between "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        dateutils._ret $(( __kdt_pb_y*12 + __kdt_pb_m ))
    else
        dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
        d=$(( __du_a - __du_b )); if (( d < 0 )); then d=$(( -d )); fi
        dateutils._ret $(( d / 2629800000 ))
    fi
}
dateutils.periodBetween() {
    dateutils._period_between "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_pb_y $__kdt_pb_m $__kdt_pb_d"
}
dateutils.dateTimeDiff() { local __du_a __du_b; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; dateutils._ret $(( __du_a - __du_b )); }   # signed ms

# --- P4: span (fractional ratio, 6 dp) --------------------------------------
dateutils.milliSecondSpan() { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 1;           dateutils._ret "$REPLY"; }
dateutils.secondSpan()      { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 1000;        dateutils._ret "$REPLY"; }
dateutils.minuteSpan()      { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 60000;       dateutils._ret "$REPLY"; }
dateutils.hourSpan()        { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 3600000;     dateutils._ret "$REPLY"; }
dateutils.daySpan()         { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 86400000;    dateutils._ret "$REPLY"; }
dateutils.weekSpan()        { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 604800000;   dateutils._ret "$REPLY"; }
dateutils.monthSpan()       { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 2629800000;  dateutils._ret "$REPLY"; }
dateutils.yearSpan()        { local __du_a __du_b d; dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }; d=$(( __du_a - __du_b )); (( d < 0 )) && d=$(( -d )); dateutils._span_fixed "$d" 31557600000; dateutils._ret "$REPLY"; }

# --- P4: within-past (xxxBetween(now,then) <= range; approx for years/months)
dateutils._withinPast() {   # NOW THEN RANGE DIVISOR -> rc 0 = within
    local __du_a __du_b __du_c d
    dateutils._three "${1:-}" "${2:-}" "${3:-}" || return 2
    d=$(( __du_a - __du_b )); if (( d < 0 )); then d=$(( -d )); fi
    if (( d / $4 <= __du_c )); then return 0; fi
    return 1
}
dateutils.withinPastMilliSeconds() { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 1           || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastSeconds()      { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 1000        || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastMinutes()      { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 60000       || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastHours()        { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 3600000     || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastDays()         { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 86400000    || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastWeeks()        { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 604800000   || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastMonths()       { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 2629800000  || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }
dateutils.withinPastYears()        { local rc=0; dateutils._withinPast "${1:-}" "${2:-}" "${3:-}" 31557600000 || rc=$?; if (( rc == 2 )); then RESULT=""; return 1; fi; dateutils._retBool "$rc"; }

# --- P4: compare (-1/0/1) / same (true/false) -------------------------------
# Integer KDT is linear, so compare = sign(a-b); FPC's frac/trunc branches only
# exist to tame negative-TDateTime float weirdness that KDT does not have.
dateutils.compareDateTime() {
    local __du_a __du_b r=0
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( __du_a > __du_b )); then r=1; fi
    if (( __du_a < __du_b )); then r=-1; fi
    dateutils._ret "$r"
}
dateutils.compareDate() {
    local __du_a __du_b a b r=0
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; a=$REPLY
    dateutils._floor_day_i "$__du_b"; b=$REPLY
    if (( a > b )); then r=1; fi
    if (( a < b )); then r=-1; fi
    dateutils._ret "$r"
}
dateutils.compareTime() {
    local __du_a __du_b ta tb r=0
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; ta=$(( __du_a - REPLY*86400000 ))
    dateutils._floor_day_i "$__du_b"; tb=$(( __du_b - REPLY*86400000 ))
    if (( ta > tb )); then r=1; fi
    if (( ta < tb )); then r=-1; fi
    dateutils._ret "$r"
}
dateutils.sameDateTime() {
    local __du_a __du_b
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    if (( __du_a == __du_b )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.sameDate() {
    local __du_a __du_b a b
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; a=$REPLY
    dateutils._floor_day_i "$__du_b"; b=$REPLY
    if (( a == b )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}
dateutils.sameTime() {
    local __du_a __du_b d
    dateutils._two "${1:-}" "${2:-}" || { RESULT=""; return 1; }
    d=$(( __du_a - __du_b )); if (( d < 0 )); then d=$(( -d )); fi
    if (( d % 86400000 == 0 )); then dateutils._retBool 0; else dateutils._retBool 1; fi
}

# --- P4: range (inclusive by default; timeInRange handles overnight wrap) ----
dateutils.dateTimeInRange() {
    local __du_a __du_b __du_c inc="${4:-true}" res=1
    dateutils._three "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    if [[ "$inc" == true || "$inc" == 1 ]]; then
        (( __du_b <= __du_a && __du_a <= __du_c )) && res=0
    else
        (( __du_b <  __du_a && __du_a <  __du_c )) && res=0
    fi
    dateutils._retBool "$res"
}
dateutils.dateInRange() {
    local __du_a __du_b __du_c inc="${4:-true}" dd ds de res=1
    dateutils._three "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; dd=$REPLY
    dateutils._floor_day_i "$__du_b"; ds=$REPLY
    dateutils._floor_day_i "$__du_c"; de=$REPLY
    if [[ "$inc" == true || "$inc" == 1 ]]; then
        (( ds <= dd && dd <= de )) && res=0
    else
        (( ds <  dd && dd <  de )) && res=0
    fi
    dateutils._retBool "$res"
}
dateutils.timeInRange() {
    local __du_a __du_b __du_c inc="${4:-true}" lt ls le res=1
    dateutils._three "${1:-}" "${2:-}" "${3:-}" || { RESULT=""; return 1; }
    dateutils._floor_day_i "$__du_a"; lt=$(( __du_a - REPLY*86400000 ))
    dateutils._floor_day_i "$__du_b"; ls=$(( __du_b - REPLY*86400000 ))
    dateutils._floor_day_i "$__du_c"; le=$(( __du_c - REPLY*86400000 ))
    if (( le < ls )); then                         # overnight range (end before start)
        if [[ "$inc" == true || "$inc" == 1 ]]; then
            (( ls <= lt || lt <= le )) && res=0
        else
            (( ls <  lt || lt <  le )) && res=0
        fi
    else
        if [[ "$inc" == true || "$inc" == 1 ]]; then
            (( ls <= lt && lt <= le )) && res=0
        else
            (( ls <  lt && lt <  le )) && res=0
        fi
    fi
    dateutils._retBool "$res"
}

# --- P5: recode (field surgery; '-' keeps a field; recode* logs, try* silent)
dateutils.recodeDateTime()    { dateutils._recode "$@"                        || { dateutils._debug "invalid recodeDateTime";    RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.tryRecodeDateTime() { dateutils._recode "$@"                        || { RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeYear()        { dateutils._recode "${1:-}" "${2:-}" -  -  -  -  -  -     || { dateutils._debug "invalid recodeYear";        RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeMonth()       { dateutils._recode "${1:-}" -  "${2:-}" -  -  -  -  -     || { dateutils._debug "invalid recodeMonth";       RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeDay()         { dateutils._recode "${1:-}" -  -  "${2:-}" -  -  -  -     || { dateutils._debug "invalid recodeDay";         RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeHour()        { dateutils._recode "${1:-}" -  -  -  "${2:-}" -  -  -     || { dateutils._debug "invalid recodeHour";        RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeMinute()      { dateutils._recode "${1:-}" -  -  -  -  "${2:-}" -  -     || { dateutils._debug "invalid recodeMinute";      RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeSecond()      { dateutils._recode "${1:-}" -  -  -  -  -  "${2:-}" -     || { dateutils._debug "invalid recodeSecond";      RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeMilliSecond() { dateutils._recode "${1:-}" -  -  -  -  -  -  "${2:-}"    || { dateutils._debug "invalid recodeMilliSecond"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeDate()        { dateutils._recode "${1:-}" "${2:-}" "${3:-}" "${4:-}" -  -  -  -  || { dateutils._debug "invalid recodeDate"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.recodeTime()        { dateutils._recode "${1:-}" -  -  -  "${2:-}" "${3:-}" "${4:-}" "${5:-}" || { dateutils._debug "invalid recodeTime"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }

# --- P5: week-date / day-of-week-in-month encodings -------------------------
dateutils.encodeDateWeek()    { dateutils._encode_date_week "${1:-}" "${2:-}" "${3:-1}" || { dateutils._debug "invalid dateWeek ${1:-}/${2:-}"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.tryEncodeDateWeek() { dateutils._encode_date_week "${1:-}" "${2:-}" "${3:-1}" || { RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.decodeDateWeek() {
    dateutils._decode_date_week "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_wy_year $__kdt_wy_week $__kdt_wy_dow"
}
dateutils.encodeDateMonthWeek()    { dateutils._encode_date_month_week "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { dateutils._debug "invalid dateMonthWeek"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.tryEncodeDateMonthWeek() { dateutils._encode_date_month_week "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.decodeDateMonthWeek() {
    dateutils._decode_date_month_week "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$__kdt_mw_year $__kdt_mw_month $__kdt_mw_week $__kdt_mw_dow"
}
dateutils.encodeDayOfWeekInMonth()    { dateutils._encode_dow_in_month "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { dateutils._debug "invalid dayOfWeekInMonth"; RESULT=""; return 1; }; dateutils._ret "$REPLY"; }
dateutils.tryEncodeDayOfWeekInMonth() { dateutils._encode_dow_in_month "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { RESULT=""; return 1; }; dateutils._ret "$REPLY"; }

# --- P6: Unix (KDT 0 == Unix 0; conversion is a trivial ms<->s scaling) ------
# G3-05 / R7: with utc=false the offset is the one in force AT THE VALUE, not
# the one in force today.
dateutils.dateTimeToUnix() {
    local dt utc="${2:-true}" sec
    kk.isInt "${1:-}" dt || { RESULT=""; return 1; }
    if [[ "$utc" != true && "$utc" != 1 ]]; then
        dateutils._local_offset_ms $(( dt / 1000 ))                       # local -> UTC
        dt=$(( dt - REPLY ))
    fi
    sec=$(( dt / 1000 ))
    if (( dt < 0 && dt % 1000 != 0 )); then sec=$(( sec - 1 )); fi        # floor to the second
    dateutils._ret "$sec"
}
dateutils.unixToDateTime() {
    local u kdt utc="${2:-true}"
    kk.isInt "${1:-}" u || { RESULT=""; return 1; }
    kdt=$(( u * 1000 ))
    if [[ "$utc" != true && "$utc" != 1 ]]; then
        dateutils._local_offset_ms "$u"                                   # UTC -> local
        kdt=$(( kdt + REPLY ))
    fi
    dateutils._ret "$kdt"
}

# --- P6: Julian / Modified Julian (6-dp decimal strings) --------------------
dateutils.dateTimeToJulianDate() {
    local __du_a
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._span_fixed $(( 210866760000000 + __du_a )) 86400000
    dateutils._ret "$REPLY"
}
dateutils.dateTimeToModifiedJulianDate() {
    local __du_a
    dateutils._one "${1:-}" || { RESULT=""; return 1; }
    dateutils._span_fixed $(( 3506716800000 + __du_a )) 86400000
    dateutils._ret "$REPLY"
}
dateutils.tryJulianDateToDateTime() {
    dateutils._jd_to_kdt "${1:-}" 210866760000000 || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.julianDateToDateTime() {
    dateutils._jd_to_kdt "${1:-}" 210866760000000 || { dateutils._debug "invalid JD ${1:-}"; RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.tryModifiedJulianDateToDateTime() {
    dateutils._jd_to_kdt "${1:-}" 3506716800000 || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.modifiedJulianDateToDateTime() {
    dateutils._jd_to_kdt "${1:-}" 3506716800000 || { dateutils._debug "invalid MJD ${1:-}"; RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}

# --- P6: local <-> UTC (explicit offset is minutes EAST of UTC, like %(%z)T) -
dateutils.universalTimeToLocal() {
    local ut off
    kk.isInt "${1:-}" ut || { RESULT=""; return 1; }
    if (( $# >= 2 )); then
        dateutils._normalize_offset_min_east "${2:-}" || { RESULT=""; return 1; }
        off=$REPLY
    else
        dateutils._local_offset_ms $(( ut / 1000 ))
        off=$(( REPLY / 60000 ))
    fi
    dateutils._ret $(( ut + off*60000 ))
}
dateutils.localTimeToUniversal() {
    local lt off
    kk.isInt "${1:-}" lt || { RESULT=""; return 1; }
    if (( $# >= 2 )); then
        dateutils._normalize_offset_min_east "${2:-}" || { RESULT=""; return 1; }
        off=$REPLY
    else
        dateutils._local_offset_ms $(( lt / 1000 ))
        off=$(( REPLY / 60000 ))
    fi
    dateutils._ret $(( lt - off*60000 ))
}

# --- P6: time interval (a duration; hours may exceed 24) --------------------
dateutils.tryEncodeTimeInterval() {
    dateutils._time_interval "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.encodeTimeInterval() {
    dateutils._time_interval "${1:-}" "${2:-}" "${3:-}" "${4:-}" || { dateutils._debug "invalid interval"; RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}

# --- P6: timezone-offset strings (FPC sign: '+03:00' -> -180) ---------------
dateutils.tryISOTZStrToTZOffset() {
    dateutils._tz_offset_east "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret $(( -REPLY ))
}
dateutils.isoTZStrToTZOffset() {
    dateutils._tz_offset_east "${1:-}" || { dateutils._debug "invalid TZ ${1:-}"; RESULT=""; return 1; }
    dateutils._ret $(( -REPLY ))
}

# --- P6: ISO 8601 date/datetime strings -------------------------------------
# tryISOStrToDate: date-only. FPC (dateutil.inc:2740) has YYYYMMDD and
# YYYY-MM-DD; YYYY / YYYYMM / YYYY-MM are a documented port extension.
dateutils.tryISOStrToDate() {
    dateutils._iso_date "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
# tryISOStrToTime: FPC's seven forms, with the zone validated and discarded.
dateutils.tryISOStrToTime() {
    dateutils._iso_time "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
# tryISOStrToDateTime: naive datetime as written (no zone conversion), split at
# FPC's fixed positions.
dateutils.tryISOStrToDateTime() {
    dateutils._iso_datetime "${1:-}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}

# dateToISO8601: 'YYYY-MM-DDThh:mm:ss.zzz' + 'Z' (UTC) or '±hh:mm' (local).
dateutils.dateToISO8601() {
    local dt utc="${2:-true}" s off sign m
    kk.isInt "${1:-}" dt || { RESULT=""; return 1; }
    dateutils._fmt_datetime "$dt"; s=${REPLY/ /T}
    if [[ "$utc" == true || "$utc" == 1 ]]; then
        dateutils._ret "${s}Z"
        return 0
    fi
    dateutils._local_offset_ms $(( dt / 1000 ))       # the offset OF THIS DATE
    off=$REPLY
    if (( off == 0 )); then
        dateutils._ret "${s}Z"
        return 0
    fi
    sign=+
    if (( off < 0 )); then sign=-; off=$(( -off )); fi
    m=$(( off / 60000 ))
    printf -v s '%s%s%02d:%02d' "$s" "$sign" "$(( m/60 ))" "$(( m%60 ))"
    dateutils._ret "$s"
}

# _iso8601_to_kdt STR RETURNUTC -> REPLY = KDT; rc 1 if unparseable.
dateutils._iso8601_to_kdt() {
    local kdt
    dateutils._parse_iso "${1:-}" || return 1      # REPLY, __kdt_has_tz, __kdt_tzoff_min (east+)
    kdt=$REPLY
    if (( __kdt_has_tz )); then kdt=$(( kdt - __kdt_tzoff_min*60000 )); fi   # zoned wall clock -> UTC
    if [[ "${2:-true}" != true && "${2:-true}" != 1 ]]; then
        dateutils._local_offset_ms $(( kdt / 1000 ))
        kdt=$(( kdt + REPLY ))
    fi
    REPLY=$kdt
    return 0
}
dateutils.tryISO8601ToDate() {
    dateutils._iso8601_to_kdt "${1:-}" "${2:-true}" || { RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
dateutils.iso8601ToDate() {
    dateutils._iso8601_to_kdt "${1:-}" "${2:-true}" || { dateutils._debug "invalid ISO8601 ${1:-}"; RESULT=""; return 1; }
    dateutils._ret "$REPLY"
}
# FPC ISO8601ToDateDef: an unparseable string yields the caller's default, rc 0.
dateutils.iso8601ToDateDef() {
    if dateutils._iso8601_to_kdt "${1:-}" "${3:-true}"; then
        dateutils._ret "$REPLY"
    else
        dateutils._ret "${2:-}"
    fi
}

# --- P7: scanDateTime (practical subset of FPC ScanDateTime) ----------------
# Tokens (case-insensitive): yyyy/yy year, dd day, hh hour, nn minute, ss
# second, zzz millisecond, and mm — which is MONTH except directly after an hour
# token, where FPC makes it MINUTES (dateutil.inc:2505, the `lasttoken` rule).
# The time separator `:` is transparent to that rule (dateutil.inc:2615-2618),
# so `hh:mm` is minutes and `yyyy-mm-dd` is a month. A run of more than two `m`
# after an hour is Shhmmerror.
#
# Each numeric token reads up to its width in digits (greedy, like FPC
# scanfixedint). Quoted 'literals'/"literals" match verbatim; whitespace in the
# pattern is elastic (FPC matches a pattern space exactly — a deliberate
# convenience); other characters must match exactly. 2-digit years pivot at 50.
# An UNTERMINATED quote is rc 1 (FPC runs off the end of the pattern and
# returns a value; plan P6 asks for a refusal). Input left over after the
# pattern is consumed is allowed, exactly as in FPC.
# Out of scope (full FPC matcher): month/day NAMES, ampm, c/t date-format
# tokens, [] optionals.
dateutils.scanDateTime() {
    local pat="${1:-}" inp="${2:-}" plen=${#1} ilen=${#2}
    # Unset fields default to the epoch (1970-01-01 00:00), so a partial pattern
    # still yields a valid KDT; a time-only pattern gives the ms-of-day.
    local pind=0 ind=0 yy=1970 mm=1 dd=1 h=0 n=0 s=0 ms=0
    local pc upc runlen maxv val cnt c q lasttoken=' ' closed isminute
    while (( pind < plen )); do
        pc=${pat:pind:1}
        if [[ "$pc" == "'" || "$pc" == '"' ]]; then           # quoted literal
            q=$pc; pind=$(( pind + 1 )); closed=0
            while (( pind < plen )); do
                if [[ "${pat:pind:1}" == "$q" ]]; then
                    closed=1; pind=$(( pind + 1 )); break
                fi
                { (( ind < ilen )) && [[ "${inp:ind:1}" == "${pat:pind:1}" ]]; } || { RESULT=""; return 1; }
                pind=$(( pind + 1 )); ind=$(( ind + 1 ))
            done
            if (( ! closed )); then RESULT=""; return 1; fi   # G3-08
            lasttoken=$q
            continue
        fi
        upc=${pc^^}
        case "$upc" in
            Y|M|D|H|N|S|Z)
                runlen=0
                while (( pind + runlen < plen )) && [[ "${pat:pind+runlen:1}" == "$pc" ]]; do runlen=$(( runlen + 1 )); done
                isminute=0
                if [[ "$upc" == "M" && "$lasttoken" == "H" ]]; then
                    if (( runlen > 2 )); then RESULT=""; return 1; fi    # FPC Shhmmerror
                    isminute=1
                fi
                case "$upc" in
                    Y) if (( runlen <= 2 )); then maxv=2; else maxv=$runlen; fi ;;
                    Z) maxv=3 ;;
                    *) maxv=2 ;;
                esac
                val=0; cnt=0
                while (( maxv > 0 && ind < ilen )); do
                    c=${inp:ind:1}; [[ "$c" == [0-9] ]] || break
                    val=$(( val*10 + 10#$c )); ind=$(( ind + 1 )); cnt=$(( cnt + 1 )); maxv=$(( maxv - 1 ))
                done
                (( cnt > 0 )) || { RESULT=""; return 1; }
                pind=$(( pind + runlen ))
                case "$upc" in
                    Y) if (( runlen <= 2 )); then
                           if (( val < 50 )); then val=$(( 2000 + val )); else val=$(( 1900 + val )); fi
                       fi
                       yy=$val ;;
                    M) if (( isminute )); then n=$val; else mm=$val; fi ;;
                    D) dd=$val ;;  H) h=$val ;;
                    N) n=$val ;;   S) s=$val ;;   Z) ms=$val ;;
                esac
                lasttoken=$upc
                ;;
            *)
                if [[ "$pc" == " " || "$pc" == $'\t' ]]; then   # elastic whitespace
                    while (( pind < plen )) && [[ "${pat:pind:1}" == " " || "${pat:pind:1}" == $'\t' ]]; do pind=$(( pind + 1 )); done
                    while (( ind < ilen )) && [[ "${inp:ind:1}" == " " || "${inp:ind:1}" == $'\t' ]]; do ind=$(( ind + 1 )); done
                    lasttoken=' '
                else
                    { (( ind < ilen )) && [[ "${inp:ind:1}" == "$pc" ]]; } || { RESULT=""; return 1; }
                    pind=$(( pind + 1 )); ind=$(( ind + 1 ))
                    # The time separator leaves `lasttoken` alone, so the `M` of
                    # `hh:mm` still sees the `H` (dateutil.inc:2615-2618).
                    if [[ "$pc" != ":" ]]; then lasttoken=$upc; fi
                fi
                ;;
        esac
    done
    dateutils._valid_date "$yy" "$mm" "$dd" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._valid_time "$h" "$n" "$s" "$ms" || { RESULT=""; return 1; }
    (( REPLY )) || { RESULT=""; return 1; }
    dateutils._join_kdt "$__kdt_vy" "$__kdt_vmo" "$__kdt_vd" "$__kdt_vh" "$__kdt_vmi" "$__kdt_vs" "$__kdt_vms"
    dateutils._ret "$REPLY"
}

# Finalize: extract the bodies above into the `dateutils` class and generate the
# thin static dispatchers. The class is named `dateutils`, so the public API is
# `dateutils.<Method>` and kklass metadata `dateutils_class_static_methods` is
# populated. Internal dateutils._* helpers are left untouched (plain functions).
build dateutils
