#!/usr/bin/env bash
# 003_Modal.sh - modal views inside a running application (design §2.2):
#   * a dialog executed by a handler (fv.views.execView on the desktop) reads
#     its events through the application's GetEvent: Idle runs while it runs
#     (the status line follows the dialog's HelpCtx), the put event reaches
#     it; it ends by endModal (cmOK) and by a modal cmClose (cmCancel posted);
#     the application loop then goes on with its own event record;
#   * a dialog inside a dialog; the screen == a full repaint afterwards;
#   * Run's loop resumes after each dialog and ends with Alt+X.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: modal views in a running application"

# TDlg (a TWindow acting as FV's TDialog for the commands): Enter -> endModal
# cmOK (the status line's HelpCtx logged), evCommand cmOK / cmCancel ->
# endModal with it (FV TDialog), kbF8 -> the inner dialog d2 (TDlg2: Esc ->
# endModal cmNo); kbF7 in the application opens d1 (a TDlg, HelpCtx 7)
# through execView; the answers are logged in MLOG
class TDlg2 : TWindow
    public
        override proc HandleEvent
end
TDlg2.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbEsc ]; then fv.views.endModal "$this" cmNo; fv.views.clearEvent "$this"; fi
}
build TDlg2
class TDlg : TWindow
    public
        override proc HandleEvent
end
TDlg.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbEnter ]; then
            MLOG+="hc=${app__fvstatus_data[HelpCtx]};"
            fv.views.endModal "$this" cmOK; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF8 ]; then
            TDlg2.new d2 25 7 55 13 'Inner' 0
            fv.views.execView "$FV_DESKTOP" d2
            MLOG+="d2=$RESULT;"
            d2.delete
            fv.views.clearEvent "$this"
        fi
    elif [ "$FV_EV_WHAT" = evCommand ] && { [ "$FV_EV_COMMAND" = cmOK ] || [ "$FV_EV_COMMAND" = cmCancel ]; }; then
        fv.views.endModal "$this" "$FV_EV_COMMAND"; fv.views.clearEvent "$this"
    fi
}
build TDlg
class TDlgApp : TApplication
    public
        override proc HandleEvent
end
TDlgApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbF7 ]; then
        local k=$FV_EV_KEY
        TDlg.new d1 20 5 60 15 'Dialog' 0
        d1_data[HelpCtx]=7
        fv.views.execView "$FV_DESKTOP" d1
        MLOG+="d1=$RESULT/$k/$FV_EV_KEY;"
        d1.delete
        fv.views.clearEvent "$this"
    fi
}
build TDlgApp

kt_test_start "a dialog executed by a handler reads through the application's GetEvent: Idle runs meanwhile (the status line takes its HelpCtx), Enter -> endModal cmOK; the outer handler's event record is its own afterwards"
fva_app 80 24 TDlgApp
MLOG=''
fva_events 'key kbF7' 'nothing' 'key kbEnter' 'nothing' 'key kbAltX'
app.Run
r="$MLOG|$__FV_VW_EOF|${#FVA_Q[@]}|${app__fvstatus_data[HelpCtx]}|${__FV_VW_LIVE[d1]-gone}"
if [[ $r == 'hc=7;d1=cmOK/kbF7/kbF7;|0|0|0|gone' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "a modal cmClose (the dialog's close command) posts cmCancel through the application's PutEvent: the dialog ends cmCancel"
MLOG=''
fva_events 'key kbF7' 'cmd cmClose' 'key kbAltX'
app.Run
r="$MLOG|$__FV_VW_EOF|${#FVA_Q[@]}"
if [[ $r == 'd1=cmCancel/kbF7/kbF7;|0|0' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi

kt_test_start "a dialog inside a dialog: Esc ends the inner one (cmNo), Enter the outer one (cmOK), each in its own loop; Alt+X then ends Run"
MLOG=''
fva_events 'key kbF7' 'key kbF8' 'nothing' 'key kbEsc' 'key kbEnter' 'key kbAltX'
app.Run
r="$MLOG|$__FV_VW_EOF|${#FVA_Q[@]}|${__FV_VW_TOPVIEW}"
if [[ $r == 'd2=cmNo;hc=0;d1=cmOK/kbF7/kbF7;|0|0|' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
fva_unapp

kt_test_log "003_Modal.sh completed"
