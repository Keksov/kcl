#!/usr/bin/env bash
# 009_InputMouse.sh - the input line and the mouse (FV dialogs.inc
# TInputLine.HandleEvent's evMouseDown, MouseDelta / MousePos / CanScroll;
# design P3 §3.3, §4.2):
#   * a click places the cursor in front of the cluster under it (wide
#     clusters: either half), past the text at its end; a click on an
#     unfocused line focuses it (TView's, ofFirstClick) and then places the
#     cursor (the selection SelectAll made collapses);
#   * a double click selects all;
#   * a drag selects from the press (moves coalesced), backwards too;
#   * a drag held past the right / left edge scrolls a cluster per
#     evMouseAuto (FV: Delta on evMouseAuto) and extends the selection;
#   * a press on the `>` / `<` cell while the text can scroll there scrolls
#     a cluster per evMouseAuto until the release (FV's first loop);
#   * a key or the end of input ends a drag (fv.views' tracking); each step
#     == a full repaint at the end.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: the input line and the mouse"

# a 20-cell line at screen (13, 6): its text cells 14 .. 31, `>` at 32
scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Edit'
    TInputLine.new il 3 2 23 3 60
    TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    fv.views.insert dlg il; fv.views.insert dlg ok
    fv.views.select il
    fv.views.insert desk dlg; fv.views.select dlg
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
# ev X Y [DOUBLE] SPECS... — a mouse-down at X Y to the application, SPECS
# read by the tracking loop after it; REPLY = "CurPos SelStart-SelEnd FirstPos"
ev() {
    local x=$1 y=$2 d=${3:-0}
    shift 3
    fvw_events "$@"
    fv.drivers.clearEvent
    FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=$x FV_EV_MOUSE_Y=$y FV_EV_MOUSE_DOUBLE=$d FV_EV_MOUSE_BUTTONS=1
    fv.views._virt app HandleEvent
    REPLY="${il_data[CurPos]} ${il_data[SelStart]}-${il_data[SelEnd]} ${il_data[FirstPos]}"
    fvw_noevents
}
Y=6

scene
fv.dialogs.setText il 'ab中cd'; fv.dialogs.selectAll il 0
kt_test_start "a click places the cursor in front of the cluster under it: cell 1 -> 0, cell 3 -> 2, both halves of 中 -> 2, past the text -> its end"
r=''
ev 14 $Y 0 'up 14 6'; r+="${REPLY%% *},"
ev 16 $Y 0 'up 16 6'; r+="${REPLY%% *},"
ev 17 $Y 0 'up 17 6'; r+="${REPLY%% *},"
ev 18 $Y 0 'up 18 6'; r+="${REPLY%% *},"
ev 19 $Y 0 'up 19 6'; r+="${REPLY%% *},"
ev 28 $Y 0 'up 28 6'; r+="${REPLY%% *}"
if [[ $r == '0,2,2,3,4,5' && $FV_EV_WHAT == evNothing ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$r $FV_EV_WHAT"; fi
kt_test_start "a click on cell 0 (no '<': nothing to scroll) is MousePos 1: the cursor at 0"
ev 13 $Y 0 'up 13 6'
if [[ $REPLY == '0 0-0 0' ]]; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
kt_test_start "a double click selects all"
ev 16 $Y 1 'up 16 6'
if [[ $REPLY == '0 0-5 0' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
kt_test_start "a drag selects from the press: cell 2 to cell 6 -> CurPos 4, selection 1-4 (moves coalesced)"
ev 15 $Y 0 'move 16 6' 'move 18 6' 'move 19 6' 'up 19 6'
if [[ $REPLY == '4 1-4 0' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
kt_test_start "a drag backwards: from cell 6 to cell 1 -> CurPos 0, selection 0-4"
ev 19 $Y 0 'move 15 6' 'move 14 6' 'up 14 6'
if [[ $REPLY == '0 0-4 0' ]]; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
kt_test_start "a key during a drag ends it (put back for the loop's owner); the selection as far as it went"
ev 14 $Y 0 'move 16 6' 'key kbDown' 'move 20 6'
if [[ $REPLY == '2 0-2 0' ]]; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
fv.drivers.clearEvent; fv.drivers.putEvent
kt_test_start "the end of input during a drag ends it"
ev 14 $Y 0 'move 15 6'
if [[ $REPLY == '1 0-1 0' ]]; then kt_test_pass ok; else kt_test_fail "$REPLY"; fi
unscene

scene
fv.dialogs.setText il 'abcdefghijklmnopqrstuvwxyz0123'; fv.dialogs.selectAll il 0
# (a 'nothing' after a move: fv.views' tracking coalesces the events already
# waiting behind a move, an evMouseAuto among them)
kt_test_start "a drag held on the right edge ('>' cell): each evMouseAuto scrolls a cluster, the cursor follows the mouse (FV MousePos)"
ev 20 $Y 0 'move 32 6' 'nothing' 'auto 32 6' 'auto 32 6' 'auto 32 6' 'up 32 6'
st=$REPLY; read -r cur sel first <<< "$st"
fvg_cells 13 $Y 2
if [[ $first == 3 && $cur == 21 && $sel == 6-21 && ${RESULT:0:1} == '<' ]] && fvw_full app; then kt_test_pass "$st"; else kt_test_fail "$st [$RESULT]"; fi
kt_test_start "dragged far past the right edge the cursor goes where FV's MousePos maps the mouse, past the shown text (FirstPos + 26 here)"
ev 20 $Y 0 'move 40 6' 'nothing' 'auto 40 6' 'up 40 6'
st=$REPLY; read -r cur sel first <<< "$st"
if [[ $first == 4 && $cur == 30 && $sel == 9-30 ]]; then kt_test_pass "$st"; else kt_test_fail "$st"; fi
kt_test_start "a drag held past the left edge scrolls back a cluster per evMouseAuto"
ev 20 $Y 0 'move 5 6' 'nothing' 'auto 5 6' 'auto 5 6' 'up 5 6'
st=$REPLY; read -r cur sel first <<< "$st"
if [[ $first == 2 && $cur == 2 && $sel == 2-10 ]] && fvw_full app; then kt_test_pass "$st"; else kt_test_fail "$st"; fi
kt_test_start "a press on '>' while text lies past it: one cluster per evMouseAuto until the release; the cursor stays"
fv.dialogs.selectAll il 0
ev 32 $Y 0 'auto 32 6' 'auto 32 6' 'move 30 6' 'auto 30 6' 'up 30 6'
st=$REPLY; read -r cur sel first <<< "$st"
if [[ $first == 4 && $cur == 0 ]] && fvw_full app; then kt_test_pass "$st"; else kt_test_fail "$st"; fi
kt_test_start "a press on '<' scrolls back the same way; at FirstPos 0 it stops ('<' gone)"
ev 13 $Y 0 'auto 13 6' 'auto 13 6' 'auto 13 6' 'auto 13 6' 'up 13 6'
fvg_cells 13 $Y 1
if [[ ${il_data[FirstPos]} == 0 && $RESULT == ' ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "first ${il_data[FirstPos]} [$RESULT]"; fi
unscene

scene
TInputLine.new il2 3 4 23 5 20
fv.views.insert dlg il2
fv.dialogs.setText il2 'hello world'
fv.views.focus il
kt_test_start "a click on an unfocused line focuses it (SelectAll on focus), then places the cursor: the selection collapses"
ev 18 8 0 'up 18 8'
if [[ ${dlg_data[Current]} == il2 && ${il2_data[CurPos]} == 4 && ${il2_data[SelStart]} == 4 && ${il2_data[SelEnd]} == 4 ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "cur ${dlg_data[Current]} ${il2_data[CurPos]} ${il2_data[SelStart]}-${il2_data[SelEnd]}"; fi
unscene

kt_test_log "009_InputMouse.sh completed"
