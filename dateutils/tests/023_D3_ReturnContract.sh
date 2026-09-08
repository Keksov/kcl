#!/bin/bash
# 023_D3_ReturnContract.sh — decision D3, default R8, decision D6 for dateutils.
#
# Until P6 all 185 members ended in `printf '%s\n'`, so the only way to read one
# was `$( )` — a fork, measured by the reviewer at 15 ms per call on this box
# against 0.17 ms for the body itself. The contract is now kcl/README.md 1.1-1.3:
#
#   * a DIRECT call prints NOTHING and leaves the value in RESULT;
#   * inside `$( )` the value is printed exactly ONCE, so every existing caller
#     keeps working unchanged;
#   * a predicate answers with its exit status AND leaves true|false in RESULT
#     (R8), so `$(dateutils.isLeapYear 2000)` still prints `true`;
#   * a failure is rc 1 with RESULT='' and nothing on stdout or stderr.
#
# For a STATIC kklass class the shape is `static proc` + a unit-local `_ret`,
# not `static func`: the thin static dispatcher re-prints kk._return's value
# unconditionally (kcl/README.md 1.1, first recorded in P3 for tpath).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "D3_ReturnContract" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/dateutils.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$TMP/stdout.txt"

K=1301166930555        # 2011-03-26 19:15:30.555
K2=946684800000        # 2000-01-01 00:00:00.000

# ---------------------------------------------------------------------------
# 1. A direct call is silent and sets RESULT
# ---------------------------------------------------------------------------
silent_direct() {   # EXPECTED MEMBER ARGS...
    local want="$1"; shift
    kt_test_start "dateutils.$1 direct: silent, RESULT='$want' [D3]"
    RESULT="__unset__"
    : > "$OUT"
    dateutils."$@" > "$OUT" 2>&1 || :
    local printed; printed="$(<"$OUT")"
    if [[ -n "$printed" ]]; then
        kt_test_fail "$1: a direct call printed '$printed'"
    elif [[ "$RESULT" != "$want" ]]; then
        kt_test_fail "$1: RESULT='$RESULT', expected '$want'"
    else
        kt_test_pass "$1 -> RESULT=$want"
    fi
}

silent_direct 2011            yearOf "$K"
silent_direct 3               monthOf "$K"
silent_direct 26              dayOf "$K"
silent_direct "2011 3 26"     decodeDate "$K"
silent_direct "19 15 30 555"  decodeTime "$K"
silent_direct "2011 3 26 19 15 30 555" decodeDateTime "$K"
silent_direct 1301097600000   encodeDate 2011 3 26
silent_direct 1301253330555   incDay "$K" 1
silent_direct 4102            daysBetween "$K" "$K2"
silent_direct "4102.802436"   daySpan "$K" "$K2"
silent_direct 1               compareDateTime "$K" "$K2"
silent_direct 12              weekOfTheYear "$K"
silent_direct "2011-03-26T19:15:30.555Z" dateToISO8601 "$K"
silent_direct 86400000        msPerDay
silent_direct "30.4375"       approxDaysPerMonth
silent_direct true            isValidDate 2011 3 26
silent_direct false           isValidDate 2011 2 30
silent_direct 1301166930000   scanDateTime 'yyyy-mm-dd hh:mm:ss' '2011-03-26 19:15:30'

# ---------------------------------------------------------------------------
# 2. `$( )` prints the value exactly once
# ---------------------------------------------------------------------------
capture_once() {   # EXPECTED MEMBER ARGS...
    local want="$1"; shift
    kt_test_start "\$(dateutils.$1 ...) prints '$want' exactly once [D3]"
    local got; got="$(dateutils."$@" 2>&1)" || :
    if [[ "$got" == "$want" ]]; then
        kt_test_pass "$1 -> $got"
    else
        kt_test_fail "$1 printed '$got', expected '$want'"
    fi
}

capture_once 2011           yearOf "$K"
capture_once "2011 3 26"    decodeDate "$K"
capture_once 1301097600000  encodeDate 2011 3 26
capture_once true           isValidDate 2011 3 26
capture_once false          isValidDate 2011 2 30
capture_once true           isInLeapYear "$K2"
capture_once "4102.802436"  daySpan "$K" "$K2"
capture_once -1             compareDateTime "$K2" "$K"

# ---------------------------------------------------------------------------
# 3. Every boolean member answers by rc AND leaves the word in RESULT [R8]
# ---------------------------------------------------------------------------
BOOLS=(isValidDate isValidTime isValidDateTime isValidDateDay isValidDateWeek
       isValidDateMonthWeek isInLeapYear isAM isPM isToday isSameDay isSameMonth
       sameDateTime sameDate sameTime dateInRange timeInRange dateTimeInRange
       withinPastYears withinPastMonths withinPastWeeks withinPastDays
       withinPastHours withinPastMinutes withinPastSeconds withinPastMilliSeconds)

kt_test_start "the boolean list below still covers every true/false member [R8]"
# Read the member bodies out of the SOURCE, not out of the shell: enumerating a
# big shell's function table costs seconds. A member is boolean exactly when its
# body answers through the shared `_retBool` helper.
mapfile -t found < <(awk '
    /^dateutils\.[A-Za-z0-9_]+\(\)/ { name = $0; sub(/^dateutils\./, "", name); sub(/\(\).*/, "", name) }
    /_retBool/ && name != "" && name !~ /^_/ { print name; name = "" }
' "$UNIT" | sort -u)
missing=()
for m in "${found[@]}"; do
    printf '%s\n' "${BOOLS[@]}" | grep -qx "$m" || missing+=("$m")
done
extra=()
for m in "${BOOLS[@]}"; do
    printf '%s\n' "${found[@]}" | grep -qx "$m" || extra+=("$m")
done
if (( ${#missing[@]} == 0 && ${#extra[@]} == 0 && ${#found[@]} == ${#BOOLS[@]} )); then
    kt_test_pass "${#BOOLS[@]} boolean members, list and source agree"
else
    kt_test_fail "in source but not listed: ${missing[*]:-none}; listed but not boolean: ${extra[*]:-none}"
fi

bool_rc() {   # EXPECTED-WORD MEMBER ARGS...
    local want="$1"; shift
    local wantrc=1; [[ "$want" == true ]] && wantrc=0
    kt_test_start "dateutils.$1 -> $want by rc $wantrc and in RESULT [R8]"
    RESULT="__unset__"
    local rc=0 printed
    : > "$OUT"
    dateutils."$@" > "$OUT" 2>&1 || rc=$?
    printed="$(<"$OUT")"
    if [[ -n "$printed" ]]; then
        kt_test_fail "$1 printed '$printed' on a direct call"
    elif (( rc != wantrc )); then
        kt_test_fail "$1 rc=$rc, expected $wantrc (RESULT='$RESULT')"
    elif [[ "$RESULT" != "$want" ]]; then
        kt_test_fail "$1 RESULT='$RESULT', expected '$want'"
    else
        kt_test_pass "$1 rc=$rc RESULT=$want"
    fi
}

bool_rc true  isValidDate 2011 3 26
bool_rc false isValidDate 2011 2 30
bool_rc true  isValidTime 19 15 30 555
bool_rc false isValidTime 19 60 30 555
bool_rc true  isValidDateTime 2011 3 26 19 15 30 555
bool_rc false isValidDateTime 2011 2 30 19 15 30 555
bool_rc true  isValidDateDay 2011 365
bool_rc false isValidDateDay 2011 366
bool_rc true  isValidDateWeek 2011 52 7
bool_rc false isValidDateWeek 2011 53 7
bool_rc true  isValidDateMonthWeek 2011 3 5 7
bool_rc false isValidDateMonthWeek 2011 3 6 7
bool_rc true  isInLeapYear "$K2"
bool_rc false isInLeapYear "$K"
bool_rc false isAM "$K"
bool_rc true  isPM "$K"
bool_rc false isToday "$K"
bool_rc true  isSameDay "$K" 1301097600000
bool_rc false isSameDay "$K" "$K2"
bool_rc true  isSameMonth "$K" 1301097600000
bool_rc false isSameMonth "$K" "$K2"
bool_rc true  sameDateTime "$K" "$K"
bool_rc false sameDateTime "$K" "$K2"
bool_rc true  sameDate "$K" 1301097600000
bool_rc false sameDate "$K" "$K2"
bool_rc true  sameTime "$K" "$K"
bool_rc false sameTime "$K" "$K2"
bool_rc true  dateTimeInRange "$K" "$K2" 1400000000000
bool_rc false dateTimeInRange "$K2" "$K" 1400000000000
bool_rc true  dateInRange "$K" "$K2" 1400000000000
bool_rc false dateInRange "$K2" "$K" 1400000000000
bool_rc true  timeInRange 69330555 0 86399999
bool_rc false timeInRange 69330555 69330556 86399999
bool_rc true  withinPastDays "$K" "$K" 0
bool_rc false withinPastDays "$K" "$K2" 0
bool_rc true  withinPastYears "$K" "$K2" 100
bool_rc false withinPastYears "$K" "$K2" 1
bool_rc true  withinPastMonths "$K" "$K2" 1000
bool_rc false withinPastMonths "$K" "$K2" 1
bool_rc true  withinPastWeeks "$K" "$K2" 1000
bool_rc false withinPastWeeks "$K" "$K2" 1
bool_rc true  withinPastHours "$K" "$K2" 1000000
bool_rc false withinPastHours "$K" "$K2" 1
bool_rc true  withinPastMinutes "$K" "$K2" 100000000
bool_rc false withinPastMinutes "$K" "$K2" 1
bool_rc true  withinPastSeconds "$K" "$K2" 1000000000
bool_rc false withinPastSeconds "$K" "$K2" 1
bool_rc true  withinPastMilliSeconds "$K" "$K2" 999999999999
bool_rc false withinPastMilliSeconds "$K" "$K2" 1

# ---------------------------------------------------------------------------
# 4. A failure is rc 1 + RESULT='' + silence [kcl/README.md 1.2]
# ---------------------------------------------------------------------------
kt_test_start "a failing member clears RESULT rather than leaving the previous value [1.2]"
dateutils.yearOf "$K"                       # RESULT = 2011
rc=0
: > "$OUT"
dateutils.encodeDate 2011 2 30 > "$OUT" 2>&1 || rc=$?
printed="$(<"$OUT")"
if (( rc == 1 )) && [[ -z "$RESULT" && -z "$printed" ]]; then
    kt_test_pass "rc 1, RESULT empty, silent"
else
    kt_test_fail "rc=$rc RESULT='$RESULT' printed='$printed'"
fi

kt_test_start "the debug channel stays quiet unless VERBOSE_KKLASS=debug [1.2]"
quiet="$(dateutils.encodeDate 2011 2 30 2>&1)"; rc_q=$?
loud="$(VERBOSE_KKLASS=debug dateutils.encodeDate 2011 2 30 2>&1)"; rc_l=$?
if [[ -z "$quiet" && $rc_q -eq 1 && "$loud" == *"invalid date"* && $rc_l -eq 1 ]]; then
    kt_test_pass "silent by default, diagnostic under debug"
else
    kt_test_fail "quiet='$quiet'($rc_q) loud='$loud'($rc_l)"
fi

# ---------------------------------------------------------------------------
# 5. The direct call really is fork-free [1.8]
# ---------------------------------------------------------------------------
kt_test_start "a direct call does not fork: BASHPID is unchanged and RESULT survives [1.8]"
before=$BASHPID
dateutils.yearOf "$K"; v1=$RESULT
dateutils.incMonth "$K" 1; v2=$RESULT
after=$BASHPID
if [[ "$before" == "$after" && "$v1" == 2011 && "$v2" == 1303845330555 ]]; then
    kt_test_pass "same shell ($before), RESULT=$v1/$v2"
else
    kt_test_fail "BASHPID $before -> $after, v1='$v1' v2='$v2'"
fi

kt_test_start "the whole hot path runs with an empty PATH [1.8]"
got="$(bash -c "source '$UNIT'
PATH=''
dateutils.yearOf $K; y=\$RESULT
dateutils.weekOfTheYear $K; w=\$RESULT
dateutils.incMonth $K 1; m=\$RESULT
dateutils.dateToISO8601 $K
printf '%s %s %s %s' \"\$y\" \"\$w\" \"\$m\" \"\$RESULT\"" 2>&1)"
if [[ "$got" == "2011 12 1303845330555 2011-03-26T19:15:30.555Z" ]]; then
    kt_test_pass "$got"
else
    kt_test_fail "got '$got'"
fi

kt_test_start "200 direct calls are faster than 200 through \$( ) [1.8, D3]"
n=200
t0=${EPOCHREALTIME/[.,]/}
for (( i=0; i<n; i++ )); do dateutils.yearOf "$K"; done
t1=${EPOCHREALTIME/[.,]/}
for (( i=0; i<n; i++ )); do v="$(dateutils.yearOf "$K")"; done
t2=${EPOCHREALTIME/[.,]/}
direct=$(( t1 - t0 )); forked=$(( t2 - t1 ))
if (( direct < forked )); then
    kt_test_pass "direct ${direct}us < \$( ) ${forked}us for $n calls"
else
    kt_test_fail "direct ${direct}us is not faster than \$( ) ${forked}us"
fi

# ---------------------------------------------------------------------------
# 6. Values are data (X-ECHO) — no member may use `echo`
# ---------------------------------------------------------------------------
kt_test_start "no member body calls echo [X-ECHO, G1-13]"
if bad="$(grep -n '^[^#]*\becho\b' "$UNIT")"; then
    kt_test_fail "echo found: ${bad//$'\n'/ | }"
else
    kt_test_pass "none"
fi

kt_test_start "an answer that looks like an echo option round-trips [X-ECHO]"
# approxDaysPerYear is a plain string constant; the KDT members are numeric, so
# the round-trip risk lives in the string-valued members.
a="$(dateutils.dateToISO8601 "$K")"
dateutils.dateToISO8601 "$K"; b=$RESULT
if [[ "$a" == "2011-03-26T19:15:30.555Z" && "$b" == "$a" ]]; then
    kt_test_pass "$a"
else
    kt_test_fail "\$( )='$a' direct='$b'"
fi

# ---------------------------------------------------------------------------
# 7. Locale self-heal [D6]
# ---------------------------------------------------------------------------
kt_test_start "the unit exports a UTF-8 LC_CTYPE into a bare environment [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\$(dateutils.dateToISO8601 $K)\"" 2>&1)"
if [[ "$out" == "C.UTF-8|2011-03-26T19:15:30.555Z" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "the self-heal does not override an explicit locale [D6]"
out="$(env -u LC_CTYPE -u LANG LC_ALL=C.UTF-8 bash -c "
source '$UNIT'
printf '%s' \"\${LC_CTYPE:-unset}\"" 2>&1)"
if [[ "$out" == "unset" ]]; then
    kt_test_pass "LC_CTYPE left alone when LC_ALL is set"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "a decimal-comma locale does not corrupt the wall clock [D6]"
out="$(LC_ALL=de_DE.UTF-8 bash -c "
source '$UNIT'
dateutils.nowUTC
n=\$RESULT
if [[ \"\$n\" =~ ^[0-9]{13}$ ]] && (( n > 1700000000000 )); then printf OK; else printf 'n=%s' \"\$n\"; fi" 2>&1)"
if [[ "$out" == "OK" ]]; then
    kt_test_pass "nowUTC is a 13-digit ms value under de_DE"
else
    kt_test_fail "$out"
fi

# ---------------------------------------------------------------------------
# 8. Predicates under set -e (kcl/README.md 1.3)
# ---------------------------------------------------------------------------
kt_test_start "a false predicate under set -e reaches the caller through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
if dateutils.isValidDate 2011 2 30; then printf 'valid'; else printf 'invalid'; fi
dateutils.isValidDate 2011 2 30 || printf ' or-ok'
! dateutils.isValidDate 2011 2 30 && printf ' bang-ok'
printf ' end'" 2>&1)"
if [[ "$out" == "invalid or-ok bang-ok end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi
