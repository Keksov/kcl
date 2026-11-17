#!/usr/bin/env bash
# 008_Pty.sh - a real application on a real terminal: a pty under util-linux
# script(1) (the harness is fv.video's tests/fvv_pty.sh; SKIP with reason
# ENV where the runtime has none: Git-bash). Never the terminal the tests run
# on.
#   * TApplication.new (initVideo, initEvents, the screen at the pty's size)
#     -> Run (the first paint: the status line's 'Alt-X' and 'Exit' reach the
#     terminal) -> Alt+X typed -> cmQuit -> app.delete (doneEvents,
#     doneVideo): the terminal restored (stty, ?1049l ?25h ?7h, mouse off),
#     status 0;
#   * a resize while it runs (the child sets the pty to 120x40 and gets its
#     SIGWINCH): fv.drivers' cmResizeApp (the stty fork) handled at once by
#     the application: the desktop 120 x 39; then Alt+X, restored;
#   * Ctrl+C while it runs: the emergency exit (fv.app sets no trap; fv.video
#     restores the terminal), status 130, Done not run.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"
source "$FVA_TESTS_DIR/../../fv.video/tests/fvv_pty.sh"
FVP_ROOT=$FVW_TMP/pty
mkdir -p "$FVP_ROOT"

kt_test_section "008: an application on a pty (script(1))"

TITLES=("init -> Run -> Alt+X -> Done: status 0, the first paint reached the terminal, the steps logged"
    "init -> Run -> Alt+X -> Done: the terminal restored"
    "a resize while it runs (pty 120x40, SIGWINCH): handled at once, the desktop 120x39; status 0"
    "the resize run: the terminal restored"
    "Ctrl+C while it runs: status 130, Done not run (the emergency exit)"
    "the Ctrl+C run: the terminal restored")

skip_all() {
    local t
    for t in "${TITLES[@]}"; do kt_test_start "$t"; kt_test_pass "SKIP: $FVP_WHY"; done
}

if ! fvp_detect; then
    skip_all
else
    fvp_case run '
kk.uses fv.app || exit 92
TApplication.new app || exit 91
note "init $FV_SCREEN_W x $FV_SCREEN_H video=$FV_VIDEO_ON app=$FV_APP"
: > "$D/ready"
app.Run
note "run eof=$__FV_VW_EOF"
app.delete
note "done video=$FV_VIDEO_ON app=$FV_APP"
exit 0'
    fvp_run run ready sleep:0.5 'type:\033x'
    kt_test_start "${TITLES[0]}"
    fvp_file run rc; rc=$REPLY
    fvp_file run log; log=$REPLY
    fvp_file run child.err; err=$REPLY
    fvp_ts run; ts=$REPLY
    if [[ $rc == 0 && $log == $'init 100 x 30 video=1 app=app\nrun eof=0\ndone video=0 app=' && -z $err && $ts == *'Alt-X'*'Exit'* ]]; then kt_test_pass "ok"
    else kt_test_fail "rc=$rc log=[${log//$'\n'/|}] stderr=[$err]"; fi
    kt_test_start "${TITLES[1]}"
    if fvp_restored run; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

    fvp_case resize '
kk.uses fv.app || exit 92
class TRApp : TApplication
    public
        override proc HandleEvent
end
TRApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_CHAR" = r ]; then
        stty rows 40 cols 120 <&"$FV_TTY_FD"
        kill -WINCH $BASHPID
        fv.views.clearEvent "$this"
    elif [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_CHAR" = s ]; then
        fv.views.getBounds "$FV_DESKTOP"; note "desk $RESULT screen $FV_SCREEN_W x $FV_SCREEN_H"
        fv.views.clearEvent "$this"
    fi
}
build TRApp
TRApp.new app || exit 91
: > "$D/ready"
app.Run
app.delete
note "done"
exit 0'
    fvp_run resize ready sleep:0.5 type:r sleep:1 type:s sleep:0.3 'type:\033x'
    kt_test_start "${TITLES[2]}"
    fvp_file resize rc; rc=$REPLY
    fvp_file resize log; log=$REPLY
    fvp_file resize child.err; err=$REPLY
    if [[ $rc == 0 && $log == $'desk 0 0 120 39 screen 120 x 40\ndone' && -z $err ]]; then kt_test_pass "ok"
    else kt_test_fail "rc=$rc log=[${log//$'\n'/|}] stderr=[$err]"; fi
    kt_test_start "${TITLES[3]}"
    if fvp_restored resize; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

    fvp_case ctrlc '
kk.uses fv.app || exit 92
TApplication.new app || exit 91
: > "$D/ready"
app.Run
note "not reached"
exit 0'
    fvp_run ctrlc ready sleep:0.5 'type:\003'
    kt_test_start "${TITLES[4]}"
    fvp_file ctrlc rc; rc=$REPLY
    fvp_file ctrlc log; log=$REPLY
    if [[ $rc == 130 && -z $log ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$rc log=[${log//$'\n'/|}]"; fi
    kt_test_start "${TITLES[5]}"
    if fvp_restored ctrlc; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi
fi

kt_test_log "008_Pty.sh completed"
