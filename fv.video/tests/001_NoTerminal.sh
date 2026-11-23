#!/usr/bin/env bash
# 001_NoTerminal.sh - initVideo without a terminal it may drive, and the calls
# that need none. Nothing here opens the terminal the tests run on:
#   * a bad mode is rc 2; a missing FV_TTY (in a missing folder, or a
#     missing file in this test's folder: never created), a regular file, /dev/null, and
#     /dev/tty in a session without a controlling terminal (setsid; SKIP
#     without util-linux setsid) are rc 1 with nothing printed or written, no
#     fd left open, FV_KEY_FD / FV_TTY_FD / the caller's traps untouched, and
#     one debug line under VERBOSE_KKLASS=debug;
#   * doneVideo while off is a silent no-op.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "001: no terminal"

# state SNAP — REPLY = everything a failed init must leave alone (the next
# free fd number included)
state() {
    local f
    exec {f}</dev/null
    exec {f}<&-
    REPLY="on=$FV_VIDEO_ON fd=[$FV_TTY_FD] key=[${FV_KEY_FD-unset}] next=$f traps=[$(trap -p EXIT INT TERM HUP WINCH)]"
}

FV_KEY_FD=0

kt_test_start "initVideo with a mode that is not noalt: rc 2, silent, RESULT=''"
RESULT=x
fv.video.initVideo alt > "$FVV_TMP/o" 2>&1; rc=$?
if [[ $rc == 2 && ! -s $FVV_TMP/o && -z $RESULT && $FV_VIDEO_ON == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc RESULT=$RESULT out=$(<"$FVV_TMP/o")"; fi

kt_test_start "a caller's nocasematch does not turn NOALT into noalt: rc 2, nocasematch still on"
shopt -s nocasematch
FV_TTY=$FVV_TMP/missing-tty fv.video.initVideo NOALT > "$FVV_TMP/o" 2>&1; rc=$?
on=$(shopt -q nocasematch && echo on)
shopt -u nocasematch
if [[ $rc == 2 && $on == on && ! -s $FVV_TMP/o ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc nocasematch=$on"; fi

: > "$FVV_TMP/plain"
for t in "$FVV_TMP/none/tty" "$FVV_TMP/missing-tty" "$FVV_TMP/plain" /dev/null; do
    for m in '' noalt; do
        kt_test_start "FV_TTY=${t##*/} initVideo ${m:-(alt)}: rc 1, nothing printed or written (a missing path never created), no fd left, state untouched"
        state; before=$REPLY
        RESULT=x
        FV_TTY=$t fv.video.initVideo $m > "$FVV_TMP/o" 2>&1; rc=$?
        state; after=$REPLY
        if [[ $rc == 1 && ! -s $FVV_TMP/o && ! -s $FVV_TMP/plain && ! -e $FVV_TMP/missing-tty && -z $RESULT && $before == "$after" ]]; then
            kt_test_pass "ok"
        else
            kt_test_fail "rc=$rc RESULT=$RESULT out=[$(<"$FVV_TMP/o")] before=$before after=$after"
        fi
    done
done

kt_test_start "the failure gives exactly one debug line under VERBOSE_KKLASS=debug, naming the terminal"
VERBOSE_KKLASS=debug FV_TTY="$FVV_TMP/plain" fv.video.initVideo > "$FVV_TMP/o" 2> "$FVV_TMP/e"; rc=$?
mapfile -t lines < "$FVV_TMP/e"
if [[ $rc == 1 && ! -s $FVV_TMP/o && ${#lines[@]} == 1 && ${lines[0]} == *"$FVV_TMP/plain"* ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc stderr=[${lines[*]}]"; fi

kt_test_start "/dev/tty in a session without a controlling terminal (setsid): rc 1, silent"
s=''
case $OSTYPE in cygwin*|msys*) s=${BASH%/*}/setsid ;; *) s=$(type -P setsid) || s='' ;; esac
if [[ -z $s || ! -x $s || "$("$s" --version 2>&1)" != *util-linux* ]]; then
    kt_test_pass "SKIP: ENV: no util-linux setsid in this runtime"
elif ! kt_need_timeout; then
    kt_test_pass "SKIP: ENV: $KT_TIMEOUT_WHY"
else
    out=$("$KT_TIMEOUT" -k 5 30 "$s" -w "$BASH" -c "
source '$FVV_TESTS_DIR/../fv.video.sh'
unset FV_TTY
fv.video.initVideo; r=\$?
printf '%s|%s|%s' \"\$r\" \"\$FV_VIDEO_ON\" \"\$FV_TTY_FD\"" < /dev/null 2>&1)
    if [[ $out == '1|0|' ]]; then kt_test_pass "ok"; else kt_test_fail "out=[$out]"; fi
fi

kt_test_start "doneVideo while off: rc 0, silent, RESULT='', state untouched"
state; before=$REPLY
RESULT=x
fv.video.doneVideo > "$FVV_TMP/o" 2>&1; rc=$?
fv.video.doneVideo >> "$FVV_TMP/o" 2>&1; rc+=$?
state; after=$REPLY
if [[ $rc == 00 && ! -s $FVV_TMP/o && -z $RESULT && $before == "$after" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc out=[$(<"$FVV_TMP/o")] $before / $after"; fi

kt_test_log "001_NoTerminal.sh completed"
