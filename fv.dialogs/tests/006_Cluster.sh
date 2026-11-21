#!/usr/bin/env bash
# 006_Cluster.sh - TCluster / TCheckBoxes / TRadioButtons (FV dialogs.inc
# DrawMultiBox, HandleEvent, Column / Row / FindSel; design P3 §2.4, §3.1):
#   * the look: ' [X] Item' / ' (*) Item', FV's columns (the next column at
#     the widest item + 6), the `~` letter in colour 3, Sel in 2 / 4 while
#     focused, a disabled item (EnableMask) in 5, the hardware cursor on
#     Sel's mark (Column + 2, Row);
#   * keys while focused: Up / Down wrap, Right / Left by a column (FV's
#     formulas), disabled items skipped, WordStar through CtrlToArrow, Space
#     presses Sel; hot letters: Alt in any phase, the plain letter in
#     post-process or while focused; a radio moves its mark with Sel
#     (MovedTo); each key redraws only the changed rows (rule 4, one write);
#   * the mouse: a click on an item selects and presses it, released off it:
#     only selected; a disabled item: nothing;
#   * Id: cmIdCommunicate to the top view on Press (FV_EV_ID, INFO);
#   * GetHelpCtx = HelpCtx + Sel; setItems, setButtonState (ofSelectable);
#   * a Mark override is asked per item and drawn.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: the look"
fvg_modeless
# opts at dialog (3, 4) -> screen (13, 8), 27 x 3; dir at (32, 4) -> (42, 8)
fv.views.getColor opts 1; n1=$RESULT; fv.views.getColor opts 2; s2=$RESULT
fv.views.getColor opts 3; n3=$RESULT; fv.views.getColor opts 4; s4=$RESULT; fv.views.getColor opts 5; d5=$RESULT
fvg_cells 13 8 27
fvw_check "check boxes row 0: Sel focused" " [ ] Case sensitive        |$s2$s2$s2$s2$s2$s4$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2$s2" "$RESULT|$REPLY"
fvg_cells 13 10 27
fvw_check "check boxes row 2: the hot letter g in colour 3" " [ ] Regex                 |$n1$n1$n1$n1$n1$n1$n1$n3$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1$n1" "$RESULT|$REPLY"
fvg_cells 42 8 24
fvw_check "radio buttons: item 0 marked" " (*) Forward            " "$RESULT"
fvw_check "the cursor on Sel's mark" "2 0" "${opts_data[CursorX]} ${opts_data[CursorY]}"

kt_test_section "006: keys"
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=''; fv.views._virt dlg HandleEvent; }
kt_test_start "Down / Up move Sel, wrapping; one write each; == a full repaint"
fvw_writes_on; FVW_WRITES=0; k kbDown; w1=$FVW_WRITES; FVW_WRITES=0; k kbUp; k kbUp; w2=$FVW_WRITES; fvw_writes_off
if [[ ${opts_data[Sel]} == 2 && $w1 == 1 && $w2 == 3 ]] && fvw_full app; then kt_test_pass "writes $w1 / $w2"; else kt_test_fail "sel ${opts_data[Sel]} writes $w1 / $w2 $FVW_DIFF"; fi
kt_test_start "Space toggles Sel's box (Value bit 2); the cursor follows Sel"
k kbChar ' '
if [[ ${opts_data[Value]} == 4 && ${opts_data[CursorY]} == 2 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "value ${opts_data[Value]} cy ${opts_data[CursorY]}"; fi
fvg_cells 13 10 6; fvw_check "the box shows X" " [X] R" "$RESULT"
kt_test_start "WordStar Ctrl+E (Up) through CtrlToArrow"
k kbCtrlE
if [ "${opts_data[Sel]}" = 1 ]; then kt_test_pass ok; else kt_test_fail "${opts_data[Sel]}"; fi
kt_test_start "the focused cluster takes its plain hot letters: c presses item 0"
k kbChar c
if [[ ${opts_data[Sel]} == 0 && ${opts_data[Value]} == 5 && $FV_EV_WHAT == evNothing ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "sel ${opts_data[Sel]} value ${opts_data[Value]}"; fi
kt_test_start "Alt+B from another control: dir focused, Sel and Value 1 (radio)"
fv.views.focus ok
k kbAltB b
if [[ ${dlg_data[Current]} == dir && ${dir_data[Sel]} == 1 && ${dir_data[Value]} == 1 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "cur ${dlg_data[Current]} sel ${dir_data[Sel]} value ${dir_data[Value]}"; fi
kt_test_start "a radio's Up moves the mark (MovedTo); two rows, one write"
fvw_writes_on; FVW_WRITES=0; k kbUp; w=$FVW_WRITES; fvw_writes_off
if [[ ${dir_data[Value]} == 0 && $w == 1 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "value ${dir_data[Value]} writes $w"; fi
kt_test_start "the plain letter of an unfocused cluster in post-process: w presses opts' item 1"
fv.views.focus ok
k kbChar w
if [[ ${dlg_data[Current]} == opts && ${opts_data[Sel]} == 1 && ${opts_data[Value]} == 7 ]]; then kt_test_pass ok; else kt_test_fail "cur ${dlg_data[Current]} sel ${opts_data[Sel]} value ${opts_data[Value]}"; fi
kt_test_start "EnableMask: a disabled item is skipped by the arrows and drawn in colour 5"
fv.dialogs.setButtonState opts 2 0
k kbUp; a=${opts_data[Sel]}
k kbDown; b=${opts_data[Sel]}
fvg_cells 13 9 5
if [[ $a.$b == 0.2 && $REPLY == "$d5$d5$d5$d5$d5" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a $b [$REPLY]"; fi
kt_test_start "a disabled item's hot letter: the event is not handled (FV exits)"
k kbAltW w
if [[ $FV_EV_WHAT == evKeyDown ]]; then kt_test_pass ok; else kt_test_fail "$FV_EV_WHAT"; fi
kt_test_start "setButtonState: every item off -> not selectable; back -> selectable"
fv.dialogs.setButtonState opts 7 0; a=$(( opts_data[Options] & FV_OF_SELECTABLE ))
fv.dialogs.setButtonState opts 7 1; b=$(( opts_data[Options] & FV_OF_SELECTABLE ))
if (( a == 0 && b != 0 )); then kt_test_pass ok; else kt_test_fail "$a $b"; fi

kt_test_section "006: columns"
TCheckBoxes.new cols 2 7 56 9 '~A~a' 'Bbbbbb' '~C~c' 'Dd' 'Ee'
fv.views.insert dlg cols
fv.views.focus cols
kt_test_start "FV's columns: column 1 at the widest item of column 0 + 6 (6 + 6), column 2 at 12 + 2 + 6"
fvg_cells 12 11 30; a=$RESULT; fvg_cells 12 12 30; b=$RESULT
if [[ $a == ' [ ] Aa      [ ] Cc  [ ] Ee   ' && $b == ' [ ] Bbbbbb  [ ] Dd           ' ]]; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi
kt_test_start "Right: by a column; past the last: FV's (S+1) mod H; Left back (FV's formula)"
k kbRight; a=${cols_data[Sel]}; k kbRight; b=${cols_data[Sel]}; k kbRight; c=${cols_data[Sel]}; k kbLeft; d=${cols_data[Sel]}
if [[ $a.$b.$c.$d == 2.4.1.4 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a.$b.$c.$d"; fi
kt_test_start "the cursor in column 2: (Column + 2, Row)"
if [[ ${cols_data[CursorX]} == 22 && ${cols_data[CursorY]} == 0 ]]; then kt_test_pass ok; else kt_test_fail "${cols_data[CursorX]} ${cols_data[CursorY]}"; fi

kt_test_section "006: the mouse"
kt_test_start "a click on Dd (column 1, row 1) selects and presses it"
fvg_events 'up 26 12'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=26 FV_EV_MOUSE_Y=12 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; fvw_noevents
if [[ ${cols_data[Sel]} == 3 && ${cols_data[Value]} == 8 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "sel ${cols_data[Sel]} value ${cols_data[Value]}"; fi
kt_test_start "released off the item: selected only"
fvg_events 'move 60 20' 'up 60 20'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=14 FV_EV_MOUSE_Y=11 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; fvw_noevents
if [[ ${cols_data[Sel]} == 0 && ${cols_data[Value]} == 8 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "sel ${cols_data[Sel]} value ${cols_data[Value]}"; fi
kt_test_start "a click focuses an unfocused cluster and presses (ofFirstClick)"
fv.views.focus ok
fvg_events 'up 14 11'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=14 FV_EV_MOUSE_Y=11 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; fvw_noevents
if [[ ${dlg_data[Current]} == cols && ${cols_data[Value]} == 9 ]]; then kt_test_pass ok; else kt_test_fail "cur ${dlg_data[Current]} value ${cols_data[Value]}"; fi

kt_test_section "006: Id, GetHelpCtx, setItems, Mark override"
kt_test_start "Id: Press sends cmIdCommunicate to the top view (ID, INFO = the cluster)"
class TTop : TGroup
    public
        override proc HandleEvent
end
TTop.HandleEvent() { if [ "$FV_EV_WHAT" = evCommand ]; then GOT+="$FV_EV_COMMAND:$FV_EV_ID:$FV_EV_INFO;"; fi; inherited HandleEvent "$@"; }
build TTop
GOT=''
cols_data[Id]=7
TTop.new top 0 0 1 1
__FV_VW_TOPVIEW=top
fv.views._virt cols Press 1
__FV_VW_TOPVIEW=''
top.delete
if [ "$GOT" = 'cmIdCommunicate:7:cols;' ]; then kt_test_pass ok; else kt_test_fail "[$GOT]"; fi
cols_data[Id]=0
kt_test_start "GetHelpCtx: hcNoContext, else HelpCtx + Sel"
RESULT=''; fv.views._virt cols GetHelpCtx; a=$RESULT
cols_data[HelpCtx]=100; cols_data[Sel]=2; fv.views._virt cols GetHelpCtx; b=$RESULT
if [[ $a.$b == 0.102 ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "setItems: new items drawn, Sel kept inside, their hot letters work"
fv.dialogs.setItems cols '~X~ray' '~Y~ak'
fv.views.focus ok
k kbAltY y
fvg_cells 12 11 30; a=$RESULT
if [[ ${cols_data[Sel]} == 1 && ${dlg_data[Current]} == cols && $a == ' [X] Xray                     ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "sel ${cols_data[Sel]} [$a]"; fi
kt_test_start "a Mark override is asked per drawn item and drawn"
class TOdd : TCheckBoxes
    public
        override func Mark
end
TOdd.Mark() { (( $1 % 2 == 1 )); }
build TOdd
TOdd.new odd 2 7 30 9 a b
fv.views.delete dlg cols; cols.delete
fv.views.insert dlg odd
fvg_cells 12 11 6; a=$RESULT; fvg_cells 12 12 6; b=$RESULT
if [[ $a == ' [ ] a' && $b == ' [X] b' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] [$b]"; fi
fvg_unscene
