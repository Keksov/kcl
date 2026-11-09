#!/usr/bin/env bash
# 004_Restore.sh - the terminal is restored on every exit path (PLAN.md P0b),
# on a real pty under util-linux script(1) (SKIP with reason ENV elsewhere).
# The child sets its own EXIT/INT/TERM traps, calls initVideo and leaves by:
# doneVideo; exit without done; a `set -e` failure; an error in a function;
# Ctrl+C typed into the pty during an idle getEvent loop; SIGTERM; SIGHUP.
# Each run: `stty -g` equal before and after the child (same pty), the
# typescript holds ?1049l ?25h ?7h and the mouse-off sequence and never
# DECKPAM; the child's status (written inside the pty) is 0/3/1/1/130/143/129;
# the caller's handlers ran exactly once each; SIGTERM ends the idle loop
# within 1 s. Also: set -e with a WINCH handler ending in a false `&&` (the
# loop goes on); SIGTERM while the restore's stty runs (a slow stty function
# stands in: the nested restore still restores, status 143); input pending at
# doneVideo is drained and never reaches the shell after the child.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: restore on every exit path (script(1))"

# the child's caller traps and the idle loop
PRE='
trap "note EXIT" EXIT
trap "note INT" INT
trap "note TERM" TERM
fv.video.initVideo || exit 91
'
LOOP='
: > "$D/ready"
while fv.drivers.getEvent; do :; done
note "loop ended"
'

# path NAME TITLE WANT_RC WANT_LOG [WANT_STDERR_PATTERN] — the two checks of one run
path() {
    local name=$1 title=$2 rc=$3 log=$4 errpat=${5:-} got err
    kt_test_start "$title: stty equal before/after, ?1049l ?25h ?7h + mouse-off in the typescript, no DECKPAM"
    if fvp_restored "$name"; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi
    kt_test_start "$title: status $rc (written inside the pty), the caller's handlers once: ${log//$'\n'/ }"
    fvp_file "$name" rc; got=$REPLY
    fvp_file "$name" child.err; err=$REPLY
    fvp_file "$name" log
    # shellcheck disable=SC2053  # errpat is a pattern
    if [[ $got == "$rc" && $REPLY == "$log" && ( ( -z $errpat && -z $err ) || ( -n $errpat && $err == $errpat ) ) ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "rc=$got log=[${REPLY//$'\n'/|}] stderr=[$err]"
    fi
}

if ! fvp_detect; then
    for p in doneVideo 'exit 3' 'set -e' 'function error' SIGINT SIGTERM SIGHUP; do
        fvv_skip "$p: restored" "$p: status and handlers"
    done
    fvv_skip "SIGTERM ends an idle getEvent loop within 1 s"
    fvv_skip "set -e + a false && in the WINCH handler: restored" "set -e + a false && in the WINCH handler: status and handlers"
    fvv_skip "SIGTERM during the restore's stty: restored" "SIGTERM during the restore's stty: status and handlers"
    fvv_skip "input pending at doneVideo is drained: nothing reaches the shell after the child"
else
    fvp_case done "$PRE"'
fv.video.doneVideo
note "done rc=$?"
exit 0'
    fvp_run done
    path done doneVideo 0 $'done rc=0\nEXIT'

    fvp_case exit "$PRE"'
exit 3'
    fvp_run exit
    path exit "exit 3 without doneVideo" 3 EXIT

    fvp_case sete "set -e
$PRE"'
false
note "not reached"'
    fvp_run sete
    path sete "a set -e failure" 1 EXIT

    fvp_case func "$PRE"'
f() { : "${NOPE_UNSET:?boom}"; note "not reached"; }
f
note "not reached"'
    fvp_run func
    path func "an error in a function (\${X:?})" 1 EXIT '*boom*'

    fvp_case int "$PRE$LOOP"
    fvp_run int ready sleep:0.3 'type:\x03'
    path int "Ctrl+C typed during an idle getEvent loop" 130 $'INT\nEXIT'

    fvp_case term "$PRE$LOOP"
    fvp_run term ready sleep:0.3 sig:TERM
    path term SIGTERM 143 $'TERM\nEXIT'

    fvp_case hup "$PRE$LOOP"
    fvp_run hup ready sleep:0.3 sig:HUP
    path hup SIGHUP 129 EXIT

    kt_test_start "SIGTERM ends an idle getEvent loop within 1 s (kill -> the wrapper sees the child gone)"
    fvp_file term t_mark; t0=$REPLY
    fvp_file term t_end; t1=$REPLY
    if [[ -n $t0 && -n $t1 ]]; then
        ms=$(( (${t1//[.,]/} - ${t0//[.,]/}) / 1000 ))
        if (( ms >= 0 && ms <= 1000 )); then kt_test_pass "${ms} ms"; else kt_test_fail "${ms} ms"; fi
    else
        kt_test_fail "no times: mark=[$t0] end=[$t1]"
    fi

    fvp_case winch 'set -e
x=
trap "[[ -n \$x ]] && note redraw" WINCH
trap "note EXIT-\$?" EXIT
fv.video.initVideo || exit 91
kill -WINCH $BASHPID
note "alive after winch"
fv.drivers.getEvent 0
note "event $FV_EV_COMMAND"
fv.video.doneVideo
exit 0'
    fvp_run winch
    path winch "set -e + a false && in the WINCH handler" 0 $'alive after winch\nevent cmResizeApp\nEXIT-0'

    fvp_case midrestore '
trap "note EXIT-\$?" EXIT
fv.video.initVideo || exit 91
stty() { if [[ $1 != -* && $1 != size ]]; then : > "$D/instty"; sleep 1; fi; command stty "$@"; }
: > "$D/ready"
fv.video.doneVideo
note "not reached"'
    fvp_run midrestore ready wait:instty sig:TERM
    path midrestore "SIGTERM during the restore's stty" 143 EXIT-143

    fvp_case drain '
fv.video.initVideo || exit 91
fv.drivers.initEvents
: > "$D/ready"
for (( i = 0; i < 100; i++ )); do if read -t 0 -u "$FV_TTY_FD"; then break; fi; sleep 0.05; done
note "pending=$i"
: > "$D/wantleft"
fv.video.doneVideo
exit 0'
    fvp_run drain ready 'type:\e[<35;10;5M\e[<35;11;5M\e[<0;11;5Mabc'
    kt_test_start "input pending at doneVideo is drained: nothing reaches the shell after the child"
    fvp_file drain log; l=$REPLY
    fvp_file drain leftover; left=$REPLY
    fvp_file drain rc
    if [[ $REPLY == 0 && $l == pending=* && ${l#pending=} -lt 100 && -e $FVP_ROOT/drain/leftover && -z $left ]] && fvp_restored drain; then
        kt_test_pass "ok ($l)"
    else
        kt_test_fail "rc=$REPLY log=[$l] leftover=$(printf '%q' "$left") $REPLY"
    fi
fi

kt_test_log "004_Restore.sh completed"
