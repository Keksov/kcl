#!/bin/bash
# 006_G3_BooleansAndLocale.sh — findings G3-11 and G3-12 for tstopwatch.
#
# G3-12 (default R8, decision D2): `isRunning` and `isHighResolution` answered
#       with the numbers 0 and 1 while the rest of kcl answers a yes/no question
#       with the EXIT STATUS and the word true|false. That was the fifth boolean
#       convention in the corpus (REVIEW.md X-CONTRACT). Both members now answer
#       by rc and leave true|false in RESULT — a DOCUMENTED API CHANGE: a caller
#       that wrote `[[ "$RESULT" == 1 ]]` must write `if sw.isRunning; then`.
#
# G3-11: the README's cost table described a property read as a per-read fork
#       ("~17.7 ms", kklass_decl.sh generating `RESULT="$($__inst__.call …)"`).
#       kklass D1 landed: for a RESULT-returning getter the generated body is
#       `RESULT=""; $__inst__.call Getter` — no subshell. This file pins the
#       absence of the fork so the README claim cannot go stale unnoticed.
#
# Also here: the locale-comma parse, which the reviewer could only verify by
# hand. On bash 5.2 `EPOCHREALTIME` uses the locale's decimal separator, so
# under de_DE it reads `1788676658,546051` and a `${er%.*}` parse would silently
# produce a nonsense stamp.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "G3_BooleansAndLocale" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/tstopwatch.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
OUT="$TMP/stdout.txt"

# ---------------------------------------------------------------------------
# 1. G3-12 / R8 — the two boolean members
# ---------------------------------------------------------------------------
bool_member() {   # EXPECTED-WORD INSTANCE MEMBER
    local want="$1" inst="$2" member="$3"
    local wantrc=1; [[ "$want" == true ]] && wantrc=0
    kt_test_start "$inst.$member -> $want by rc $wantrc, word in RESULT [G3-12, R8]"
    RESULT="__unset__"
    local rc=0 printed
    : > "$OUT"
    "$inst.$member" > "$OUT" 2>&1 || rc=$?
    printed="$(<"$OUT")"
    if [[ -n "$printed" ]]; then
        kt_test_fail "$member printed '$printed' on a direct call"
    elif (( rc != wantrc )); then
        kt_test_fail "$member rc=$rc, expected $wantrc (RESULT='$RESULT')"
    elif [[ "$RESULT" != "$want" ]]; then
        kt_test_fail "$member RESULT='$RESULT', expected '$want'"
    else
        kt_test_pass "$member rc=$rc RESULT=$want"
    fi
}

# The PROPERTY form cannot carry the exit status: kklass generates a shim method
# for a method-backed property and appends `kk._return "$RESULT"` to every
# function body, which flattens the status to 0 before kk._prop_computed can
# propagate it (kklass.sh:319 does try). So the property answers with the WORD
# and the func form answers with the word AND the status. Recorded as
# found_in_P6 in kcl_ledger.json; pinned here so the split is deliberate.
prop_word() {   # EXPECTED-WORD INSTANCE PROPERTY
    local want="$1" inst="$2" prop="$3"
    kt_test_start "$inst.$prop (property) -> RESULT='$want', silent, rc = answer [G3-12]"
    RESULT="__unset__"
    local rc=0 printed captured want_rc=0
    [[ "$want" == false ]] && want_rc=1     # predicate property: rc IS the answer (kklass P6-F1 fixed)
    : > "$OUT"
    "$inst.$prop" > "$OUT" 2>&1 || rc=$?
    printed="$(<"$OUT")"
    captured="$("$inst.$prop")"
    if [[ -n "$printed" ]]; then
        kt_test_fail "$prop printed '$printed' on a direct call"
    elif [[ "$RESULT" != "$want" ]]; then
        kt_test_fail "$prop RESULT='$RESULT', expected '$want'"
    elif [[ "$captured" != "$want" ]]; then
        kt_test_fail "\$($inst.$prop) printed '$captured', expected '$want'"
    elif (( rc != want_rc )); then
        kt_test_fail "$prop rc=$rc, expected $want_rc (predicate property: rc IS the answer)"
    else
        kt_test_pass "$prop -> RESULT=$want rc=$rc"
    fi
}

TStopwatch.new sw
bool_member false sw GetIsRunning
prop_word   false sw isRunning
bool_member true  sw GetIsHighResolution
prop_word   true  sw isHighResolution

sw.Start
bool_member true sw GetIsRunning
prop_word   true sw isRunning

sw.Stop
bool_member false sw GetIsRunning
prop_word   false sw isRunning

sw.Restart
bool_member true sw GetIsRunning
sw.Reset
bool_member false sw GetIsRunning

kt_test_start "\$(sw.isRunning) still prints the word exactly once [R8]"
sw.Start
a="$(sw.isRunning)"
b="$(sw.GetIsRunning)"
sw.Stop
c="$(sw.isRunning)"
if [[ "$a" == "true" && "$b" == "true" && "$c" == "false" ]]; then
    kt_test_pass "running='$a'/'$b', stopped='$c'"
else
    kt_test_fail "running='$a'/'$b', stopped='$c'"
fi

kt_test_start "the boolean members are usable under set -e through if/|| [1.3, D7]"
out="$(bash -c "set -eu
source '$UNIT'
TStopwatch.new w
if w.GetIsRunning; then printf 'running'; else printf 'stopped'; fi
w.GetIsRunning || printf ' or-ok'
! w.GetIsRunning && printf ' bang-ok'
w.Start
if w.GetIsRunning; then printf ' now-running'; fi
w.delete
printf ' end'" 2>&1)"
if [[ "$out" == "stopped or-ok bang-ok now-running end" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

kt_test_start "a non-boolean getter is unaffected — still a number, still rc 0"
RESULT="__unset__"; rc=0
sw.GetElapsedMicroseconds || rc=$?
v1=$RESULT
RESULT="__unset__"
sw.GetFrequency
v2=$RESULT
if (( rc == 0 )) && [[ "$v1" =~ ^[0-9]+$ && "$v2" == "1000000" ]]; then
    kt_test_pass "elapsed=$v1 frequency=$v2"
else
    kt_test_fail "rc=$rc elapsed='$v1' frequency='$v2'"
fi
sw.delete

# ---------------------------------------------------------------------------
# 2. G3-11 — a property read does not fork
# ---------------------------------------------------------------------------
kt_test_start "the generated property body contains no command substitution [G3-11]"
TStopwatch.new p
body="$(declare -f p.elapsedMicroseconds)"
if [[ "$body" == *'$('* || "$body" == *'`'* ]]; then
    kt_test_fail "the property read still forks: $body"
else
    kt_test_pass "no \$( ) in the generated property read"
fi

kt_test_start "a property read works with an empty PATH and does not change BASHPID [G3-11, 1.8]"
before=$BASHPID
out="$(bash -c "source '$UNIT'
PATH=''
TStopwatch.new q
q.Start
q.elapsedMicroseconds
a=\$RESULT
q.isHighResolution
b=\$RESULT
q.frequency
q.delete
if [[ \"\$a\" =~ ^[0-9]+$ && \"\$b\" == true && \"\$RESULT\" == 1000000 ]]; then printf OK; else printf 'a=%s b=%s f=%s' \"\$a\" \"\$b\" \"\$RESULT\"; fi" 2>&1)"
after=$BASHPID
if [[ "$out" == "OK" && "$before" == "$after" ]]; then
    kt_test_pass "property reads run in the caller's shell with no external process"
else
    kt_test_fail "out='$out' BASHPID $before -> $after"
fi

kt_test_start "300 property reads are not 10x slower than 300 func reads [G3-11]"
n=300
t0=${EPOCHREALTIME/[.,]/}
for (( i=0; i<n; i++ )); do p.GetElapsedMicroseconds; done
t1=${EPOCHREALTIME/[.,]/}
for (( i=0; i<n; i++ )); do p.elapsedMicroseconds; done
t2=${EPOCHREALTIME/[.,]/}
func_us=$(( (t1 - t0) / n )); prop_us=$(( (t2 - t1) / n ))
if (( prop_us < func_us * 10 + 100 )); then
    kt_test_pass "func ${func_us}us/call, property ${prop_us}us/call"
else
    kt_test_fail "property ${prop_us}us/call vs func ${func_us}us/call — the fork is back"
fi
p.delete

# ---------------------------------------------------------------------------
# 3. The locale-comma parse of EPOCHREALTIME
# ---------------------------------------------------------------------------
locale_child() {   # LOCALE SNIPPET
    LC_ALL="$1" bash -c "source '$UNIT'
$2" 2>&1
}

for loc in C.UTF-8 de_DE.UTF-8 ru_RU.UTF-8; do
    kt_test_start "the clock is parsed correctly under LC_ALL=$loc"
    out="$(locale_child "$loc" '
TStopwatch.getTimeStamp
t=$RESULT
TStopwatch.new s startnew
s.GetElapsedMicroseconds
e=$RESULT
s.delete
if [[ "$t" =~ ^[0-9]{16}$ ]] && (( t > 1700000000000000 )) && [[ "$e" =~ ^[0-9]+$ ]] && (( e >= 0 && e < 10000000 )); then
    printf OK
else
    printf "t=%s e=%s" "$t" "$e"
fi')"
    if [[ "$out" == "OK" ]]; then
        kt_test_pass "getTimeStamp and elapsed are sane under $loc"
    else
        kt_test_fail "$out"
    fi
done

kt_test_start "an elapsed interval measured under de_DE is a plausible number of us"
out="$(locale_child de_DE.UTF-8 '
TStopwatch.new s
s.Start
for (( i=0; i<20000; i++ )); do :; done
s.Stop
s.GetElapsedMicroseconds
e=$RESULT
s.delete
if [[ "$e" =~ ^[0-9]+$ ]] && (( e > 0 && e < 60000000 )); then printf OK; else printf "e=%s" "$e"; fi')"
if [[ "$out" == "OK" ]]; then
    kt_test_pass "a busy loop measured under a comma locale gives a positive us count"
else
    kt_test_fail "$out"
fi

kt_test_start "the unit self-heals a bare environment to a UTF-8 locale [D6]"
out="$(env -u LC_ALL -u LC_CTYPE -u LANG bash -c "
source '$UNIT'
TStopwatch.getTimeStamp
printf '%s|%s' \"\${LC_CTYPE:-}\" \"\${RESULT:0:4}\"" 2>&1)"
if [[ "$out" == C.UTF-8\|[0-9][0-9][0-9][0-9] ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out', expected 'C.UTF-8|<4 digits>'"
fi
