#!/bin/bash
# 018_G3_NumericBoundary.sh — findings G3-01 and G3-04, decision D1.
#
# G3-01: a zero-padded field (`08`, `09`) is the NORMAL shape of a date field —
#        it is what `IFS=- read y m d <<< 2011-08-09` produces — and bash reads
#        it as octal inside (( )). `encodeDate 2011 08 09` died with
#        "value too great for base"; `isValidDate 2011 08 15` answered *false*.
# G3-04: an argument that reaches (( )) unvalidated is CODE: bash evaluates an
#        array subscript, so `incDay 'x[$(touch pwn)]'` ran the command; an
#        empty or non-numeric argument silently became the epoch (rc 0).
#
# P1 closed the six shared helpers and the 34 entry points the review had
# reproduced; the ledger recorded G3-04 as PARTIAL. This file closes the rest:
# EVERY public member is called with an injection-shaped argument (canary file)
# and with garbage, and the list of members that are *allowed* to answer rc 0 is
# spelled out here, so the completeness check below fails the moment a new
# member is added without a guard.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_NumericBoundary" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/dateutils.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUTF="$TMP/stdout.txt"

# Every public member, read from the class interface (never from the shell's
# function table — that is a big shell and enumerating it is slow).
mapfile -t MEMBERS < <(sed -n 's/^ *static proc \([A-Za-z0-9_]*\) *$/\1/p' "$UNIT")

# Members that legitimately answer rc 0 for ANY argument list:
#   * the wall-clock constructors and the constant getters take no arguments;
#   * iso8601ToDateDef returns its caller-supplied default when the parse fails
#     (FPC ISO8601ToDateDef), so "garbage in" is rc 0 by design;
#   * scanDateTime's arguments are a pattern and an input, not numbers — its own
#     injection cases live in 021_G3_ScanDateTime.sh.
ARG_FREE=(now nowUTC today yesterday tomorrow
          msPerSecond msPerMinute msPerHour msPerDay msPerWeek
          approxMsPerMonth approxMsPerYear approxDaysPerMonth approxDaysPerYear)
NON_NUMERIC=(iso8601ToDateDef scanDateTime)
# Shape-specific exemptions, each with the FPC rule that makes it right:
#   ''    is a VALID timezone string meaning UTC — FPC TryISOTZStrToTZOffset is
#         `Result := (TZ='Z') or (TZ='')` (dateutil.inc:2876);
#   '1.5' is a VALID Julian/Modified Julian date — those members take a decimal
#         string, not an integer.
EMPTY_OK=(isoTZStrToTZOffset tryISOTZStrToTZOffset)
FLOAT_OK=(julianDateToDateTime tryJulianDateToDateTime
          modifiedJulianDateToDateTime tryModifiedJulianDateToDateTime)

in_list() {   # NEEDLE LIST...
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
}

kt_test_start "the interface really has 185 members (the list below is complete)"
if (( ${#MEMBERS[@]} == 185 )); then
    kt_test_pass "185 static members"
else
    kt_test_fail "found ${#MEMBERS[@]} members, expected 185 — update this file"
fi

# ---------------------------------------------------------------------------
# 1. Injection: no member may EXECUTE a caller-supplied argument [G3-04]
# ---------------------------------------------------------------------------
# The canary is created by the command hidden inside the array subscript. Only
# an arithmetic evaluation of the raw string can create it.
kt_test_start "no public member evaluates an injection-shaped argument [G3-04]"
canary="$TMP/pwn_018"
rm -f "$canary"
bad="x[\$(printf x > '$canary')]"
for m in "${MEMBERS[@]}"; do
    dateutils."$m" "$bad" "$bad" "$bad" "$bad" "$bad" "$bad" "$bad" "$bad" >/dev/null 2>&1 || :
done
if [[ ! -e "$canary" ]]; then
    kt_test_pass "185 members, nothing executed"
else
    kt_test_fail "COMMAND EXECUTED — the canary $canary exists"
fi

# The same through the *second* and *third* positions only, so a member that
# validates $1 but not $2 cannot hide behind an early return.
kt_test_start "an injection in a LATER argument is not evaluated either [G3-04]"
canary2="$TMP/pwn_018b"
rm -f "$canary2"
bad2="y[\$(printf x > '$canary2')]"
for m in "${MEMBERS[@]}"; do
    dateutils."$m" 0 "$bad2" "$bad2" "$bad2" "$bad2" "$bad2" "$bad2" "$bad2" >/dev/null 2>&1 || :
    dateutils."$m" 0 1 "$bad2" "$bad2" "$bad2" "$bad2" "$bad2" "$bad2" >/dev/null 2>&1 || :
done
if [[ ! -e "$canary2" ]]; then
    kt_test_pass "nothing executed from position 2 or 3"
else
    kt_test_fail "COMMAND EXECUTED — the canary $canary2 exists"
fi

# ---------------------------------------------------------------------------
# 2. Garbage in = rc 1 and nothing printed [G3-04, kcl/README.md 1.2]
# ---------------------------------------------------------------------------
for shape_name in empty alpha meta float; do
    case "$shape_name" in
        empty) arg="" ;;
        alpha) arg="abc" ;;
        meta)  arg="x[\$(printf x > '$TMP/pwn_018c')]" ;;
        float) arg="1.5" ;;
    esac
    kt_test_start "every numeric member rejects a '$shape_name' argument with rc 1 and no output [G3-04]"
    accepted=()
    printed=()
    stale=()
    checked=0
    # A DIRECT call, not `$( )`: after D3 the member is silent anyway, and 169
    # subshells per shape cost more than the rest of this file put together.
    # Redirecting to a file also catches a stray diagnostic on STDERR, which the
    # contract forbids outside VERBOSE_KKLASS=debug (kcl/README.md 1.2).
    for m in "${MEMBERS[@]}"; do
        in_list "$m" "${ARG_FREE[@]}" && continue
        in_list "$m" "${NON_NUMERIC[@]}" && continue
        [[ "$shape_name" == empty ]] && in_list "$m" "${EMPTY_OK[@]}" && continue
        [[ "$shape_name" == float ]] && in_list "$m" "${FLOAT_OK[@]}" && continue
        checked=$(( checked + 1 ))
        RESULT="__sentinel__"
        : > "$OUTF"
        if dateutils."$m" "$arg" "$arg" "$arg" "$arg" "$arg" "$arg" "$arg" "$arg" > "$OUTF" 2>&1; then
            accepted+=("$m")
        elif [[ "$RESULT" != "" ]]; then
            # rc 1 must come with RESULT='' — a boolean member answering `false`
            # here would mean the unit treats garbage as a legitimate `no`.
            stale+=("$m=$RESULT")
        fi
        out="$(<"$OUTF")"
        [[ -n "$out" ]] && printed+=("$m=$out")
    done
    if (( ${#accepted[@]} == 0 && ${#printed[@]} == 0 && ${#stale[@]} == 0 && checked >= 165 )); then
        kt_test_pass "$checked members rejected '$shape_name' with rc 1, RESULT='' and no output"
    else
        kt_test_fail "accepted: ${accepted[*]:-none} | printed: ${printed[*]:-none} | RESULT not cleared: ${stale[*]:-none}"
    fi
done

# A KDT is a signed integer, so a NEGATIVE argument is data, not garbage: the
# guard must not turn "before 1970" into an error.
kt_test_start "a negative KDT is accepted, not rejected [D1]"
a="$(dateutils.yearOf -2208988800000)"      # 1900-01-01
b="$(dateutils.incDay -86400000 1)"
if [[ "$a" == "1900" && "$b" == "0" ]]; then
    kt_test_pass "yearOf(-2208988800000)=1900 incDay=-0"
else
    kt_test_fail "yearOf='$a' (want 1900), incDay='$b' (want 0)"
fi

# ---------------------------------------------------------------------------
# 3. Zero-padded fields are DECIMAL at every numeric boundary [G3-01]
# ---------------------------------------------------------------------------
# Each row: expected value, then the call. The expectation is the value the
# same call produces with the zeros stripped — that is the whole point.
pad_case() {   # EXPECTED MEMBER ARGS...
    local want="$1"; shift
    local title="$1"; shift
    kt_test_start "$title accepts zero-padded fields [G3-01]"
    local got rc=0
    got="$(dateutils."$title" "$@" 2>&1)" || rc=$?
    if [[ "$got" == "$want" && $rc -eq 0 ]]; then
        kt_test_pass "$title $* -> $got"
    else
        kt_test_fail "$title $* -> '$got' rc=$rc, expected '$want'"
    fi
}

pad_case 1312848000000 encodeDate 2011 08 09
pad_case 1312848000000 tryEncodeDate 2011 08 09
pad_case 32708000      encodeTime 09 05 08 000
pad_case 32708000      tryEncodeTime 09 05 08 000
pad_case 1312880708000 encodeDateTime 2011 08 09 09 05 08 000
pad_case 1312880708000 tryEncodeDateTime 2011 08 09 09 05 08 000
pad_case 1312848000000 encodeDateDay 2011 221
pad_case 1312848000000 tryEncodeDateDay 2011 221
pad_case true          isValidDate 2011 08 15
pad_case true          isValidTime 08 09 08 007
pad_case true          isValidDateTime 2011 08 15 08 09 08 007
pad_case true          isValidDateDay 2011 09
pad_case true          isValidDateWeek 2011 09 01
pad_case true          isValidDateMonthWeek 2011 08 02 03
pad_case 31            daysInAMonth 2011 08
pad_case 30            daysInAMonth 2011 09
pad_case 365           daysInAYear 2011
pad_case 52            weeksInAYear 2011
pad_case 1293840000000 startOfAYear 2011
pad_case 1325375999999 endOfAYear 2011
pad_case 1312156800000 startOfAMonth 2011 08
pad_case 1314835199999 endOfAMonth 2011 08
pad_case 1298851200000 startOfAWeek 2011 09 01
pad_case 1299455999999 endOfAWeek 2011 09 07
pad_case 1312848000000 startOfADay 2011 08 09
pad_case 1312934399999 endOfADay 2011 08 09
pad_case 6             previousDayOfWeek 07
pad_case 1298851200000 encodeDateWeek 2011 09 01
pad_case 1298851200000 tryEncodeDateWeek 2011 09 01
pad_case 1312848000000 encodeDateMonthWeek 2011 08 02 02
pad_case 1312848000000 tryEncodeDateMonthWeek 2011 08 02 02
pad_case 1312848000000 encodeDayOfWeekInMonth 2011 08 02 02
pad_case 1312848000000 tryEncodeDayOfWeekInMonth 2011 08 02 02
pad_case 32708000      encodeTimeInterval 09 05 08 000
pad_case 32708000      tryEncodeTimeInterval 09 05 08 000
pad_case 1312156800000 recodeMonth 1293840000000 08
pad_case 1293926400000 recodeDay 1293840000000 02
pad_case 1293840000000 recodeYear 1293840000000 2011
pad_case 1293872400000 recodeHour 1293840000000 09
pad_case 1312848000000 recodeDate 1293840000000 2011 08 09
pad_case 1293872708000 recodeTime 1293840000000 09 05 08 000
pad_case 1312880708000 recodeDateTime 1293840000000 2011 08 09 09 05 08 000
pad_case 1312880708000 tryRecodeDateTime 1293840000000 2011 08 09 09 05 08 000
pad_case 2011          yearOf 01312848000000
pad_case 8             monthOf 01312848000000
pad_case 1312934400000 incDay 01312848000000 01
pad_case 1315526400000 incMonth 01312848000000 01
