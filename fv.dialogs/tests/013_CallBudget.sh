#!/usr/bin/env bash
# 013_CallBudget.sh - the dispatch and write budgets of design P3 §8.1 for
# the dialog actions of stage 3c, in the design's scene: an application
# whose HandleEvent is an override (TMyApp-like, `inherited` first; F2 runs
# the pre-built test dialog modally in the desktop, F4 builds the 8-control
# test dialog, runs it and destroys it), the desktop with two windows side
# by side, the events through TGroup's Execute with the scripted source:
#   * Tab between two controls of the modal dialog: 0 dispatches (limit 4),
#     writes <= 8 (four focus changes' redraws: the old and the new control,
#     the default button's look given up and taken back);
#   * the dialog open + close, pre-built (F2 ... Ctrl+F4): limit 6 / 30;
#   * the 8-control dialog end to end (F4: build, open, close, destroy):
#     limit 30 / 26;
#   * the dialog's full draw (drawView): limit 2 / 24;
#   * a hot key (Alt+K) pressing OK, Space on a check box (one write), a
#     radio move (one write); each scene == a full repaint.
# The counts are logged ("# calls" / "# writes"); deltas are taken against a
# run with only the closing key, so the loop's own reads cancel out.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: dialog budgets (design §8.1)"
class TDApp : TGroup
    public
        override proc HandleEvent
end
TDApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbF2 ]; then fv.views.execView desk dlg; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF4 ]; then
            fvg_mkdlg dlg8 e_
            fv.views.execView desk dlg8
            dlg8.delete
            fv.views.clearEvent "$this"
        fi
    fi
}
build TDApp

fvw_screen 80 24
fvw_classes3
TDApp.new app 0 0 80 24
TGroup.new desk 0 0 80 23
TView.new bg 0 0 80 23
fv.views.insert desk bg
fvw_mklwin w1 0 0 40 23 'Files' 1
fvw_mklwin w2 40 0 80 23 'Panel two' 2
fv.views.insert desk w1; fv.views.insert desk w2
fv.views.insert app desk
TView.new sl 0 23 80 24; fv.views.insert app sl
fvw_root app
fvg_mkdlg dlg
fv.views.drawView app

# run SPEC... : the application's loop over the scripted events, counted;
# C / W = its dispatches / writes
run() {
    if [[ -n ${PREP-} ]]; then "$PREP"; fi
    fvg_events "$@"
    fvw_count_on; fvw_writes_on
    FVW_CALLS=0 FVW_WRITES=0
    fv.views._virt app Execute || :
    C=$FVW_CALLS W=$FVW_WRITES
    fvw_count_off; fvw_writes_off
    fvw_noevents
}
# budget LABEL LIMITC LIMITW BASE-SPECS -- SPECS : the delta of SPECS over BASE
budget() {
    local l=$1 lc=$2 lw=$3 c0 w0
    shift 3
    local -a b=()
    while (( $# )) && [ "$1" != -- ]; do b+=("$1"); shift; done
    shift
    run "${b[@]}"; c0=$C w0=$W
    run "$@"
    C=$(( C - c0 )) W=$(( W - w0 ))
    kt_test_start "budget $l: at most $lc dispatches, $lw writes"
    kt_test_log "# calls $l $C"
    kt_test_log "# writes $l $W"
    if (( C <= lc && W <= lw )); then kt_test_pass "$C dispatches, $W writes"; else kt_test_fail "$C dispatches ($lc), $W writes ($lw)"; fi
}

budget dlg.open-close 6 30 -- 'key kbF2' 'key kbCtrlF4'
kt_test_start "after open + close: == a full repaint, the dialog out of desk"
if [[ -z ${dlg_data[Owner]} ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
budget dlg.tab 4 8 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbTab' 'key kbCtrlF4'
budget dlg.tab-buttons 4 8 'key kbF2' 'key kbShiftTab' 'key kbShiftTab' 'key kbCtrlF4' -- 'key kbF2' 'key kbShiftTab' 'key kbShiftTab' 'key kbShiftTab' 'key kbCtrlF4'
fv.views.select opts
budget dlg.space 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char _' 'key kbCtrlF4'
rprep() { dir_data[Value]=0 dir_data[Sel]=0; fv.views.select dir; }
PREP=rprep budget dlg.radio-down 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbDown' 'key kbCtrlF4'
PREP=
fv.views.select opts
budget dlg.hotkey-ok 6 30 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'alt k'
budget dlg.build-run-destroy 30 26 -- 'key kbF4' 'key kbCtrlF4'
kt_test_start "after the end-to-end dialog: no view left, == a full repaint"
if ! fv.views.isView dlg8 && ! fv.views.isView e_ok && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi

fv.views.insert desk dlg; fv.views.select dlg
fvw_budgetw dlg.paint 2 fv.views.drawView dlg
kt_test_start "budget dlg.paint: at most 24 writes"
if (( FVW_LASTW <= 24 )); then kt_test_pass "$FVW_LASTW writes"; else kt_test_fail "$FVW_LASTW writes"; fi
kt_test_start "the dialog's draw == a full repaint"
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete desk dlg

# (P3 3d) typing into an input line of the modal dialog (design §8.1:
# 0 dispatches, 1 write per key; limits 2 / 2), the line made the dialog's
# Current (its text selected as the dialog opens: FV's SelectAll on focus)
TInputLine.new tin 3 8 40 9 255
fv.views.insert dlg tin
fv.views.select tin
budget dlg.type 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbCtrlF4'
budget dlg.type-cyr 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char ж' 'key kbCtrlF4'
budget dlg.type-cjk 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char 中' 'key kbCtrlF4'
budget dlg.type-back 2 2 'key kbF2' 'char a' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbBack' 'key kbCtrlF4'
fv.dialogs.setText tin "$(printf 'w%.0s' {1..70})"
budget dlg.type-scrolled 2 2 'key kbF2' 'key kbEnd' 'key kbCtrlF4' -- 'key kbF2' 'key kbEnd' 'char a' 'key kbCtrlF4'
fv.dialogs.setText tin "$(printf 'w%.0s' {1..70})"
budget dlg.shift-left 2 2 'key kbF2' 'key kbEnd' 'key kbCtrlF4' -- 'key kbF2' 'key kbEnd' 'key kbShiftLeft' 'key kbCtrlF4'
kt_test_start "after the typing: == a full repaint"
fv.views.insert desk dlg; fv.views.select dlg
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete desk dlg
app.delete; dlg.delete
