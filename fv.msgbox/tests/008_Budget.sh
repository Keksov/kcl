#!/usr/bin/env bash
# 008_Budget.sh - the end-to-end budget of a message box (design P3 §8.1,
# M3), in the design's scene: a headless application whose HandleEvent is
# an override (TMyApp-like: `inherited` first; F3 opens a message box, F2 an
# input box), two windows side by side in the desktop, the events through
# the application's Execute with the scripted terminal:
#   * messageBox with OK (the design's stand-in: a dialog, a text, one
#     button built, run, closed by Ctrl+F4, destroyed): at most 16
#     dispatches, 20 writes (§8.1's limit for the stand-in; measured there
#     10 / 13, here 13 / 15: the constructors' `inherited` chains);
#   * messageBox with Yes / No / Cancel (two buttons more: their
#     constructors and draws) and inputBox (a label, an input line, two
#     buttons) logged with limits of their own: 22 / 24 and 24 / 26
#     (measured 17 / 17 each);
#   * after each: no view of the box left, == a full repaint.
# The counts are logged ("# calls" / "# writes"); deltas against a run
# with no key, so the loop's own reads cancel out. Times are the CI
# bench's (`msgbox.e2e`, kbool tools/bench/fvviewcases.sh).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: the message box budget (design §8.1)"
class TBoxApp : TApplication
    public
        override proc HandleEvent
end
BOXOPT=0
TBoxApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbF3 ]; then fv.msgbox.messageBox 'File not found' "$BOXOPT"; BOXR=$RESULT; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF2 ]; then fv.msgbox.inputBox 'Save as' '~N~ame' BOXV 80; BOXR=$RESULT; fv.views.clearEvent "$this"; fi
    fi
}
build TBoxApp
fva_classes
FV_SCREEN_W=80 FV_SCREEN_H=24 FV_APP_HEADLESS=1
exec {FVW_OUTFD}>"$FVW_TMP/screen.out"
FV_VIDEO_OUT_FD=$FVW_OUTFD
TBoxApp.new app
fvw_classes3
fvw_mklwin w1 0 0 40 23 'Files' 1
fvw_mklwin w2 40 0 80 23 'Panel two' 2
fv.views.insert "$FV_DESKTOP" w1; fv.views.insert "$FV_DESKTOP" w2
fva_paint

# run SPEC... : the application's loop over the scripted events, counted
run() {
    fvx_events "$@"
    fvw_count_on; fvw_writes_on
    FVW_CALLS=0 FVW_WRITES=0
    fv.views._virt app Execute || :
    C=$FVW_CALLS W=$FVW_WRITES
    fvw_count_off; fvw_writes_off
    fva_noevents; __FV_VW_EOF=0
}
budget() {
    local l=$1 lc=$2 lw=$3 c0 w0
    shift 3
    run; c0=$C w0=$W
    BOXR=''
    run "$@"
    C=$(( C - c0 )) W=$(( W - w0 ))
    kt_test_start "budget $l: at most $lc dispatches, $lw writes"
    kt_test_log "# calls $l $C"
    kt_test_log "# writes $l $W"
    if (( C <= lc && W <= lw )); then kt_test_pass "$C dispatches, $W writes"; else kt_test_fail "$C dispatches ($lc), $W writes ($lw)"; fi
    kt_test_start "$l: the answer, no view of the box left, == a full repaint"
    fvx_live
    if [[ $BOXR == cmCancel && -z $REPLY ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "answer [$BOXR] live [$REPLY] $FVW_DIFF"; fi
}

BOXOPT=$(( FV_MF_ERROR | FV_MF_OKBUTTON ))
budget msgbox.e2e 16 20 'key kbF3' 'key kbCtrlF4'
BOXOPT=$(( FV_MF_CONFIRMATION | FV_MF_YESNOCANCEL ))
budget msgbox.e2e-yesnocancel 22 24 'key kbF3' 'key kbCtrlF4'
BOXV='untitled.txt'
budget inputbox.e2e 24 26 'key kbF2' 'key kbCtrlF4'
app.delete

kt_test_log "008_Budget.sh completed"
