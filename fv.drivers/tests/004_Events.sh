#!/usr/bin/env bash
# 004_Events.sh - the event loop around the keys and the mouse (no terminal):
#   * putEvent snapshots every FV_EV_* field into one slot; getEvent returns
#     it first (before a resize and before waiting input), once; a second put
#     overwrites; putting evNothing empties the slot; clearEvent;
#   * the resize flag: fv.video.updateSize (querySize stubbed) -> evCommand
#     cmResizeApp, FV_EV_ID = width, FV_EV_INFO = height, before a waiting key;
#   * a timeout is evNothing with rc 0 (the default 0.05 s, FV_IDLE_TIMEOUT,
#     the TIMEOUT argument); end of input is rc 1 with FV_EV_EOF=1, every time;
#   * rc 2: a bad TIMEOUT, a bad FV_KEY_FD; a bad FV_IDLE_TIMEOUT falls back;
#   * initEvents / doneEvents: no terminal -> rc 1 / rc 0, a bad mode rc 2;
#     with FV_TTY_FD on a file they write fv.mouse's sequences.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: put, clear, resize, idle, end of input"

setall() {
    FV_EV_WHAT=$1 FV_EV_KEY=kbF9 FV_EV_CHAR='c h' FV_EV_COMMAND=cmQuit FV_EV_ID=7 FV_EV_INFO=$'two\nlines'
    FV_EV_MOUSE_X=3 FV_EV_MOUSE_Y=4 FV_EV_MOUSE_BUTTONS=5 FV_EV_MOUSE_MODS=6
    FV_EV_MOUSE_DOUBLE=1 FV_EV_MOUSE_TRIPLE=1 FV_EV_WHEEL=2 FV_EV_EOF=0
}
ALL="evCommand key=kbF9 char=c h cmd=cmQuit id=7 info=two"$'\n'"lines x=3 y=4 b=5 m=6 dbl tri wheel=2"

fv.video.querySize() { RESULT='40 120'; }

kt_test_start "putEvent keeps every field; getEvent returns it first (before a resize and waiting input), once"
fvd_feed 'k'
setall evCommand
fv.drivers.putEvent
fv.drivers.clearEvent
FV_VIDEO_RESIZED=1
fv.drivers.getEvent 0; r1=$?; fvd_ev; e1=$REPLY; res=$RESULT
fv.drivers.getEvent 0; fvd_ev; e2=$REPLY
fv.drivers.getEvent 0; fvd_ev; e3=$REPLY
if [[ $r1 == 0 && $e1 == "$ALL" && $res == evCommand && $e2 == "evCommand cmd=cmResizeApp id=120 info=40" && $e3 == "evKeyDown key=kbChar char=k" ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "[$e1] [$e2] [$e3] rc=$r1 RESULT=$res"
fi

kt_test_start "a second putEvent overwrites the first (FV: Pending := Event)"
fvd_feed ''
setall evBroadcast; fv.drivers.putEvent
fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmClose; fv.drivers.putEvent
fv.drivers.clearEvent
fv.drivers.getEvent 0; fvd_ev; e1=$REPLY
fv.drivers.getEvent 0; r2=$?; fvd_ev; e2=$REPLY
if [[ $e1 == "evCommand cmd=cmClose" && $r2 == 1 && $e2 == "evNothing eof" ]]; then kt_test_pass "ok"; else kt_test_fail "[$e1] rc=$r2 [$e2]"; fi

kt_test_start "putting evNothing empties the slot"
fvd_feed 'x'
setall evCommand; fv.drivers.putEvent
fv.drivers.clearEvent; fv.drivers.putEvent
fv.drivers.getEvent 0; fvd_ev
if [[ $REPLY == "evKeyDown key=kbChar char=x" ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY]"; fi

kt_test_start "clearEvent: every field back at its default, RESULT=''"
setall evMouseDown
RESULT=x
fv.drivers.clearEvent
fvd_ev
if [[ $REPLY == evNothing && -z $RESULT ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY] RESULT=$RESULT"; fi

kt_test_start "resize: evCommand cmResizeApp width/height, FV_SCREEN_W/H set, the flag cleared, before a waiting key"
fvd_feed 'k'
FV_VIDEO_RESIZED=1
fv.video.querySize() { RESULT='33 111'; }
fv.drivers.getEvent; r1=$?; fvd_ev; e1="$REPLY ${FV_SCREEN_W}x$FV_SCREEN_H f=$FV_VIDEO_RESIZED"
fv.drivers.getEvent; fvd_ev; e2=$REPLY
if [[ $r1 == 0 && $e1 == "evCommand cmd=cmResizeApp id=111 info=33 111x33 f=0" && $e2 == "evKeyDown key=kbChar char=k" ]]; then kt_test_pass "ok"; else kt_test_fail "[$e1] [$e2]"; fi

kt_test_start "resize with no size source: COLUMNS/LINES"
fv.video.querySize() { return 1; }
FV_VIDEO_RESIZED=1
COLUMNS=90 LINES=20 fv.drivers.getEvent 0; fvd_ev
if [[ $REPLY == "evCommand cmd=cmResizeApp id=90 info=20" ]]; then kt_test_pass "ok"; else kt_test_fail "[$REPLY]"; fi

kt_test_start "end of input: rc 1, evNothing, FV_EV_EOF=1, RESULT='' - on every call"
fvd_feed ''
r=''
for i in 1 2 3; do fv.drivers.getEvent; r+="$?:$FV_EV_WHAT:$FV_EV_EOF:[$RESULT] "; done
fv.drivers.getEvent 0; r+="$?:$FV_EV_EOF"
if [[ $r == '1:evNothing:1:[] 1:evNothing:1:[] 1:evNothing:1:[] 1:1' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

# timed: a live pipe that sends its byte after 0.9 s
timed() {   # TITLE ARGS... ; the expected bounds in ms: LO HI
    local title=$1 lo=$2 hi=$3 t0 rc ms
    shift 3
    kt_test_start "$title"
    fvd_writer '' 900000 q
    fvd_now; t0=$REPLY
    fv.drivers.getEvent "$@"; rc=$?
    fvd_now; ms=$(( (REPLY - t0) / 1000 ))
    fvd_ev
    local e=$REPLY
    fv.drivers.getEvent 5; fvd_ev
    fvd_done
    if [[ $rc == 0 && $e == evNothing && $FV_EV_EOF == 0 && $REPLY == "evKeyDown key=kbChar char=q" ]] && (( ms >= lo && ms < hi )); then
        kt_test_pass "evNothing rc 0 after $ms ms, then the key"
    else
        kt_test_fail "rc=$rc [$e] after $ms ms, then [$REPLY]"
    fi
}
timed "a timeout is evNothing with rc 0 (default FV_IDLE_TIMEOUT 0.05 s)" 20 600
FV_IDLE_TIMEOUT=0.2 timed "FV_IDLE_TIMEOUT=0.2" 150 800
FV_IDLE_TIMEOUT=0.2 timed "the TIMEOUT argument wins over FV_IDLE_TIMEOUT (0.05)" 20 600 0.05
timed "TIMEOUT 0: only what is there" 0 300 0

FV_IDLE_TIMEOUT=0 VERBOSE_KKLASS=debug timed "a bad FV_IDLE_TIMEOUT (0): 0.05 is used" 20 600 2> "$FVD_TMP/e"
kt_test_start "... with one debug line naming it"
mapfile -t lines < "$FVD_TMP/e"
if [[ ${#lines[@]} == 1 && ${lines[0]} == *FV_IDLE_TIMEOUT*\'0\'* ]]; then kt_test_pass "ok"; else kt_test_fail "[${lines[*]}]"; fi

kt_test_start "rc 2: a bad TIMEOUT (RESULT='', no read), a bad FV_KEY_FD"
fvd_feed 'q'
r=''
for t in x -1 1.2.3 0.0000001 ''; do fv.drivers.getEvent "$t"; r+="$?:[$RESULT] "; done
fv.drivers.getEvent 0; r+="$FV_EV_CHAR "
FV_KEY_FD=x fv.drivers.getEvent 0; r+="$? "
FV_KEY_FD=987 fv.drivers.getEvent 0; r+="$?"
if [[ $r == '2:[] 2:[] 2:[] 2:[] 2:[] q 2 2' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_start "initEvents without a terminal: rc 1; a bad mode rc 2; doneEvents without one: rc 0; nothing printed"
FV_TTY_FD=''
fv.drivers.initEvents > "$FVD_TMP/o" 2>&1; r=$?
fv.drivers.initEvents all >> "$FVD_TMP/o" 2>&1; r+=$?
fv.drivers.doneEvents >> "$FVD_TMP/o" 2>&1; r+=$?
if [[ $r == 120 && ! -s $FVD_TMP/o ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r out=[$(<"$FVD_TMP/o")]"; fi

kt_test_start "initEvents [any] / doneEvents write fv.mouse's sequences to FV_TTY_FD and reset the held buttons"
fvd_feed $'\e[<0;1;1M'
exec {tf}> "$FVD_TMP/tty.out"
FV_TTY_FD=$tf
fv.drivers.getEvent 0; held=$FV_EV_MOUSE_BUTTONS
fv.drivers.initEvents; r=$?
fv.drivers.initEvents any; r+=$?
fv.drivers.doneEvents; r+=$?
exec {tf}>&-
FV_TTY_FD=''
want=$'\e[?1000h\e[?1002h\e[?1006h\e[?1000h\e[?1002h\e[?1003h\e[?1006h\e[?1006l\e[?1003l\e[?1002l\e[?1000l'
if [[ $r == 000 && $held == 1 && $__FV_DR_HELD == 0 && "$(<"$FVD_TMP/tty.out")" == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r held=$held/$__FV_DR_HELD out=$(printf '%q' "$(<"$FVD_TMP/tty.out")")"; fi

kt_test_start "initEvents and doneEvents drop fv.keyboard's queue (bytes read before belong to the old mode)"
fvd_feed ''
fv.keyboard.feed 'x'
fv.drivers.doneEvents
fv.drivers.getEvent 0; r="$?:$FV_EV_WHAT "
exec {tf}> "$FVD_TMP/tty2.out"
FV_TTY_FD=$tf
fv.keyboard.feed 'y'
fv.drivers.initEvents
fv.drivers.getEvent 0; r+="$?:$FV_EV_WHAT "
fv.keyboard.feed 'z'
fv.drivers.doneEvents
fv.drivers.getEvent 0; r+="$?:$FV_EV_WHAT"
exec {tf}>&-
FV_TTY_FD=''
if [[ $r == '1:evNothing 1:evNothing 1:evNothing' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

kt_test_log "004_Events.sh completed"
