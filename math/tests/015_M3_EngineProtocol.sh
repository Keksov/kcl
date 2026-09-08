#!/bin/bash
# P7 / R11 — the request/answer protocol and the engine's process lifecycle.
#
# Findings closed here:
#   M3  a newline in any argument wrote TWO request lines, so every later answer
#       was one behind, forever.
#   M6  the awk program file `/tmp/.math_fe_$$.awk` was left behind by every
#       process that ever made a Tier-B call (no EXIT trap).
#   M9  respawning the engine printed bash's `execute_coproc: coproc [pid:
#       MATH_FE] still exists` warning on stderr.
#   M10 with no awk on PATH a public Tier-B method echoed an empty line and
#       returned 0; README promised non-zero.
#   M15 awk was not pinned to LC_ALL=C, so a locale whose decimal separator is
#       a comma (with POSIXLY_CORRECT or --use-lc-numeric) made it print `2,5`.
#
# Every check that needs a fresh process runs a CHILD bash, because the point of
# most of them is what the process leaves behind when it exits.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_mathtest.sh"

kt_test_init "M3EngineProtocol" "$SCRIPT_DIR" "$@"

MATH_DIR="$SCRIPT_DIR/.."
UNIT="$MATH_DIR/math.sh"
source "$UNIT"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"

# ---------------------------------------------------------------------------
# 1. M3 — a newline (or any other separator) in an argument must never
#    desynchronise the pipe. The assertion that matters is on the NEXT call:
#    a desync is invisible in the call that caused it.
# ---------------------------------------------------------------------------
kt_test_start "a newline argument does not desynchronise the pipe [M3]"
math.feStart
ok=true; why=""
math.sin "$(printf '0\n2')" && { ok=false; why+=" [sin '0\\n2' rc 0]"; }
math.cos 0 || { ok=false; why+=" [cos 0 rc!=0]"; }
[[ "$RESULT" == 1 ]] || { ok=false; why+=" [cos 0 -> '$RESULT' want 1]"; }
math.sin 0 || { ok=false; why+=" [sin 0 rc!=0]"; }
[[ "$RESULT" == 0 ]] || { ok=false; why+=" [sin 0 -> '$RESULT' want 0]"; }
math.sqrt 4 || { ok=false; why+=" [sqrt 4 rc!=0]"; }
[[ "$RESULT" == 2 ]] || { ok=false; why+=" [sqrt 4 -> '$RESULT' want 2]"; }
$ok && kt_test_pass "the next three answers are still the right ones" || kt_test_fail "$why"

kt_test_start "a space, a tab and an empty argument do not desynchronise [M3/M14]"
ok=true; why=""
for bad in "1 2" "$(printf '1\t2')" "" "  " "1 2 3"; do
    math.sin "$bad" && { ok=false; why+=" [sin '$bad' accepted]"; }
    math.cos 0 || { ok=false; why+=" [cos 0 failed after '$bad']"; }
    [[ "$RESULT" == 1 ]] || { ok=false; why+=" [after '$bad' cos 0 -> '$RESULT']"; }
done
$ok && kt_test_pass "each rejection leaves the pipe in step" || kt_test_fail "$why"

kt_test_start "a rejected stats element does not eat the next answer [M3]"
ok=true; why=""
math.mean 1 "$(printf 'x\ny')" 3 && { ok=false; why+=" [mean accepted a newline element]"; }
math.mean 2 4 4 4 5 5 7 9 || { ok=false; why+=" [mean rc!=0]"; }
[[ "$RESULT" == 5 ]] || { ok=false; why+=" [mean -> '$RESULT' want 5]"; }
$ok && kt_test_pass "mean still 5" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 2. M6 — a process that used the engine leaves NOTHING behind. Counted
#    before/after around a child shell, so a stale file from another run
#    cannot mask a leak.
# ---------------------------------------------------------------------------
_count_progfiles() {
    local n=0 d f
    for d in "${TMPDIR:-/tmp}" "$MATH_DIR" /tmp; do
        [[ -d "$d" ]] || continue
        for f in "$d"/.math_fe_*.awk; do
            [[ -e "$f" ]] && (( n += 1 ))
        done
    done
    printf '%s' "$n"
}

kt_test_start "a plain shell exit leaves no engine temp file behind [M6]"
before="$(_count_progfiles)"
bash -c "source '$UNIT'; math.sin 1 >/dev/null; math.roundTo 2.5 0 >/dev/null" >/dev/null 2>&1
after="$(_count_progfiles)"
if [[ "$before" == "$after" ]]; then
    kt_test_pass "count unchanged ($before)"
else
    kt_test_fail "temp files leaked: $before -> $after"
fi

kt_test_start "the same holds for a shell that exits through its own EXIT trap [M6]"
before="$(_count_progfiles)"
bash -c "source '$UNIT'
trap 'printf caller-trap-ran > \"$TMP/trapmark\"' EXIT
math.sin 1 >/dev/null" >/dev/null 2>&1
after="$(_count_progfiles)"
mark="$(cat "$TMP/trapmark" 2>/dev/null)"
if [[ "$before" == "$after" && "$mark" == "caller-trap-ran" ]]; then
    kt_test_pass "no leak, and the caller's own EXIT trap still ran"
else
    kt_test_fail "count $before -> $after, caller trap mark='$mark'"
fi

kt_test_start "a shell that never touches Tier B starts no engine at all [M6]"
before="$(_count_progfiles)"
out="$(bash -c "source '$UNIT'; math.min 3 7 >/dev/null; math.divMod 7 2 >/dev/null; printf '%s' \"\$__MATH_FE_UP\"" 2>&1)"
after="$(_count_progfiles)"
if [[ "$before" == "$after" && -z "$out" ]]; then
    kt_test_pass "engine still lazy, nothing on disk"
else
    kt_test_fail "count $before -> $after, __MATH_FE_UP='$out'"
fi

# ---------------------------------------------------------------------------
# 3. M9 — restarting the engine is silent. `feStop` then a Tier-B call is the
#    documented way to restart it; the co-process slot must be free by then.
# ---------------------------------------------------------------------------
kt_test_start "restarting the engine prints no coproc warning [M9]"
errf="$TMP/respawn.err"
out="$(bash -c "source '$UNIT'
for i in 1 2 3 4 5; do
    math.sin 1 >/dev/null
    math.feStop
done
math.sin 0 >/dev/null
printf '%s' \"\$RESULT\"" 2>"$errf")"
err="$(<"$errf")"
if [[ -z "$err" && "$out" == "0" ]]; then
    kt_test_pass "5 restarts, empty stderr"
else
    kt_test_fail "stderr='$err' out='$out'"
fi

kt_test_start "an engine killed from outside is replaced silently and correctly [M9/R11]"
errf="$TMP/killed.err"
out="$(bash -c "source '$UNIT'
math.sin 1 >/dev/null
kill \"\$__MATH_FE_PID\" 2>/dev/null
wait \"\$__MATH_FE_PID\" 2>/dev/null
math.cos 0 >/dev/null; printf '%s|' \"\$RESULT\"
math.sqrt 9 >/dev/null; printf '%s' \"\$RESULT\"" 2>"$errf")"
err="$(<"$errf")"
if [[ -z "$err" && "$out" == "1|3" ]]; then
    kt_test_pass "answers 1|3 with empty stderr"
else
    kt_test_fail "stderr='$err' out='$out'"
fi

# ---------------------------------------------------------------------------
# 4. M10 — with no awk, a public Tier-B method is rc 1 + RESULT='' + no output;
#    the Tier-A core is unaffected. `PATH=` in a child so the probe is real.
# ---------------------------------------------------------------------------
kt_test_start "with no awk on PATH every Tier-B member is rc 1 and empty [M10]"
out="$(bash -c "source '$UNIT'
PATH=
bad=
for m in sin cos sqrt exp ln log10 power hypot frexp roundTo simpleRoundTo fmod \
         mean sum variance stdDev norm futureValue degToRad tanh arcSin ldexp; do
    r=\"\$(math.\$m 1 1 2>&1)\"; rc=\$?
    if (( rc == 0 )); then bad+=\"\$m:rc0 \"; fi
    if [[ -n \"\$r\" ]]; then bad+=\"\$m:printed(\$r) \"; fi
    math.\$m 1 1 >/dev/null 2>&1
    if [[ -n \"\$RESULT\" ]]; then bad+=\"\$m:RESULT(\$RESULT) \"; fi
done
math.feStart && bad+='feStart:rc0 '
math.feActive && bad+='feActive:rc0 '
printf '%s' \"\$bad\"" 2>&1)"
if [[ -z "$out" ]]; then
    kt_test_pass "all 22 members rc 1, silent, RESULT empty"
else
    kt_test_fail "$out"
fi

kt_test_start "with no awk the Tier-A core still answers exactly [M10]"
out="$(bash -c "source '$UNIT'
PATH=
math.min 3 7 >/dev/null; printf '%s|' \"\$RESULT\"
math.max -2.5 -2.4 >/dev/null; printf '%s|' \"\$RESULT\"
math.sign -5 >/dev/null; printf '%s|' \"\$RESULT\"
math.divMod 17 5 >/dev/null; printf '%s|' \"\$RESULT\"
math.sumInt 1 2 3 >/dev/null; printf '%s|' \"\$RESULT\"
math.ceil 2.1 >/dev/null; printf '%s|' \"\$RESULT\"
math.intPower 2 10 >/dev/null; printf '%s' \"\$RESULT\"" 2>&1)"
if [[ "$out" == "3|-2.4|-1|3 2|6|3|1024" ]]; then
    kt_test_pass "$out"
else
    kt_test_fail "got '$out'"
fi

# ---------------------------------------------------------------------------
# 5. M15 — the engine's decimal separator is C, whatever the caller's locale.
#    The three shapes that make gawk honour LC_NUMERIC are all covered.
# ---------------------------------------------------------------------------
# PRE runs before `source`, POST after it. POSIXLY_CORRECT has to be set AFTER
# the source: assigning it puts bash itself into posix mode, where a function
# name containing a dot is a syntax error and no kcl unit can be loaded at all.
# gawk reads it from the environment when the co-process starts, which is what
# the row is about.
_locale_row() {   # TITLE  PRE  POST
    kt_test_start "engine output is C-decimal under $1 [M15]"
    local out
    out="$(bash -c "$2
source '$UNIT'
$3
math.sin 1 >/dev/null;        printf '%s|' \"\$RESULT\"
math.mean 1.5 2.5 >/dev/null; printf '%s|' \"\$RESULT\"
math.roundTo 2.5 0 >/dev/null; printf '%s' \"\$RESULT\"" 2>&1)"
    if [[ "$out" == "0.8414709848078965|2|2" ]]; then
        kt_test_pass "$out"
    else
        kt_test_fail "got '$out'"
    fi
}
_locale_row "LC_ALL=de_DE.UTF-8"                 "export LC_ALL=de_DE.UTF-8" ":"
_locale_row "LC_ALL=de_DE.UTF-8 POSIXLY_CORRECT" "export LC_ALL=de_DE.UTF-8" "export POSIXLY_CORRECT=1"
_locale_row "LC_NUMERIC=de_DE.UTF-8"             "export LC_NUMERIC=de_DE.UTF-8" ":"
_locale_row "an empty environment"               "unset LC_ALL LC_CTYPE LC_NUMERIC LANG" ":"

kt_test_start "a comma-decimal argument is rejected, not silently truncated [M14/M15]"
ok=true; why=""
math.sin "1,5" && { ok=false; why+=" [sin 1,5 accepted]"; }
[[ -z "$RESULT" ]] || { ok=false; why+=" [RESULT='$RESULT']"; }
math.min "1,5" 2 && { ok=false; why+=" [min 1,5 accepted]"; }
$ok && kt_test_pass "rejected" || kt_test_fail "$why"

# ---------------------------------------------------------------------------
# 6. The engine is ONE process, shared, and survives a $( ) subshell.
# ---------------------------------------------------------------------------
kt_test_start "one co-process serves 200 calls and every \$( ) subshell [R11]"
math.feStart
p="$__MATH_FE_PID"
ok=true; why=""
for (( i = 0; i < 200; i++ )); do
    math.sin "$i" || { ok=false; why+=" [call $i failed]"; break; }
done
[[ "$__MATH_FE_PID" == "$p" ]] || { ok=false; why+=" [pid $p -> $__MATH_FE_PID]"; }
v="$(math.sqrt 16)"
[[ "$v" == 4 ]] || { ok=false; why+=" [\$() -> '$v']"; }
[[ "$__MATH_FE_PID" == "$p" ]] || { ok=false; why+=" [\$() replaced the engine]"; }
math.feActive || { ok=false; why+=" [not active at the end]"; }
$ok && kt_test_pass "pid $p throughout" || kt_test_fail "$why"
