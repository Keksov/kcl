#!/usr/bin/env bash
# 005_Pty.sh - getEvent on a real terminal: a pty under util-linux script(1)
# (the harness is fv.video's tests/fvv_pty.sh; SKIP with reason ENV where the
# runtime has no util-linux script):
#   * Ctrl+Z, Ctrl+\ and Ctrl+V arrive as kbCtrlZ / kbCtrlBackslash / kbCtrlV
#     (susp, quit, lnext undefined): the process is neither stopped nor killed;
#     Enter arrives as kbEnter;
#   * a burst of 60 keys typed at once arrives whole and in order;
#   * initEvents / initEvents any / doneEvents write the mouse sequences to
#     the terminal; an SGR report typed into the pty is an evMouseDown at its
#     cell; the run restores the terminal.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"
source "$FVD_TESTS_DIR/../../fv.video/tests/fvv_pty.sh"
FVP_ROOT=$FVD_TMP/pty
mkdir -p "$FVP_ROOT"

kt_test_section "005: getEvent on a pty (script(1))"

TITLES=("Ctrl+Z, Ctrl+\\, Ctrl+V and Enter arrive as kbCtrlZ, kbCtrlBackslash, kbCtrlV (then x apart), kbEnter; the process goes on to q, status 0"
    "the keys run restored the terminal"
    "60 keys typed at once arrive whole and in order"
    "initEvents / initEvents any / doneEvents: their sequences reach the terminal, in order, doneEvents' mouse-off before doneVideo's restore"
    "an SGR report typed into the pty: evMouseDown at its cell, then evMouseUp"
    "the mouse run restored the terminal")

LOOP='
: > "$D/ready"
while fv.drivers.getEvent; do
    case $FV_EV_WHAT in
        evKeyDown) note "key $FV_EV_KEY $FV_EV_CHAR"; if [[ $FV_EV_CHAR == q ]]; then break; fi ;;
        evMouse*) note "mouse $FV_EV_WHAT $FV_EV_MOUSE_X $FV_EV_MOUSE_Y $FV_EV_MOUSE_BUTTONS" ;;
    esac
done
fv.video.doneVideo
exit 0'

run_all() {
    local log want burst='' i ts

    fvp_case keys "fv.video.initVideo || exit 91
$LOOP"
    fvp_run keys ready 'type:\x1a' sleep:0.3 'type:\x1c' sleep:0.3 'type:\x16' sleep:0.2 type:x sleep:0.2 'type:\r' sleep:0.2 type:q
    fvp_file keys log; log=$REPLY
    fvp_file keys rc
    want=$'key kbCtrlZ \nkey kbCtrlBackslash \nkey kbCtrlV \nkey kbChar x\nkey kbEnter \nkey kbChar q'
    kt_test_start "${TITLES[0]}"
    if [[ $REPLY == 0 && $log == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$REPLY log=[${log//$'\n'/|}]"; fi
    kt_test_start "${TITLES[1]}"
    if fvp_restored keys; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

    burst=abcdefghijklmnoprstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012345678    # 59, no q
    fvp_case burst "fv.video.initVideo || exit 91
$LOOP"
    fvp_run burst ready "type:${burst}q"
    fvp_file burst log; log=''
    while IFS= read -r i; do log+=${i#key kbChar }; done <<< "$REPLY"
    kt_test_start "${TITLES[2]}"
    if [[ $log == "${burst}q" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$log]"; fi

    fvp_case mouse "fv.video.initVideo || exit 91
fv.drivers.initEvents; a=\$?
fv.drivers.initEvents any; b=\$?
note \"init \$a\$b\"
${LOOP/fv.video.doneVideo/fv.drivers.doneEvents; note \"done-events \$?\"; fv.video.doneVideo}"
    fvp_run mouse ready 'type:\e[<0;10;5M' sleep:0.2 'type:\e[<0;10;5m' sleep:0.2 type:q
    fvp_file mouse log; log=$REPLY
    fvp_ts mouse; ts=$REPLY
    kt_test_start "${TITLES[3]}"
    # initEvents, initEvents any, then doneEvents' mouse-off BEFORE doneVideo's
    # restore (which sends its own mouse-off after ?1049l)
    if [[ $ts == *$'\e[?1000h\e[?1002h\e[?1006h\e[?1000h\e[?1002h\e[?1003h\e[?1006h'*$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l\e[0m\e[?7h\e[?25h\e[?1049l\e[?1006l\e[?1003l\e[?1002l\e[?1000l'* \
          && $log == 'init 00'* && $log == *$'\ndone-events 0' ]]; then
        kt_test_pass "ok"
    else
        kt_test_fail "log=[${log//$'\n'/|}] ts=$(printf '%q' "$ts")"
    fi
    kt_test_start "${TITLES[4]}"
    # (the auto-repeat is 009_Auto's: a loaded runner can hold the release
    # past FV_REPEAT_DELAY, so evMouseAuto lines between are left out here)
    log2=${log//$'\nmouse evMouseAuto 9 4 1'/}
    if [[ $log2 == $'init 00\nmouse evMouseDown 9 4 1\nmouse evMouseUp 9 4 0\nkey kbChar q\ndone-events 0' ]]; then kt_test_pass "ok"; else kt_test_fail "log=[${log//$'\n'/|}]"; fi
    kt_test_start "${TITLES[5]}"
    if fvp_restored mouse; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi
}

if fvp_detect; then
    run_all
else
    for t in "${TITLES[@]}"; do kt_test_start "$t"; kt_test_pass "SKIP: $FVP_WHY"; done
fi

kt_test_log "005_Pty.sh completed"
