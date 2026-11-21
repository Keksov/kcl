#!/usr/bin/env bash
# 003_Button.sh - TButton (FV dialogs.inc; design P3 §2.4, §3.1, §3.2):
#   * the look: the title centred / bfLeftJust, its `~` letter in the
#     shortcut colour, the `▄` / `▀` shadow in colour 8, pressed (shifted,
#     no shadow), the colours normal / default / selected / disabled (FV's
#     GetColor words through CButton and CGrayDialog), a wide title, rows
#     past the second blank;
#   * the default button: the default look moves to a focused button
#     (cmGrabDefault) and back (cmReleaseDefault), makeDefault;
#   * hot keys: Alt + the letter in any phase, the plain letter only in the
#     owner's post-process phase, Enter / Space on the focused button;
#   * the mouse: a click presses it without focusing it (no bfGrabFocus),
#     with bfGrabFocus it is focused; the press tracking (released off the
#     button: no press; on its shadow: a press);
#   * Press: cmRecordHistory to the owner first, evCommand Command posted
#     with the button in FV_EV_INFO, bfBroadcast broadcasts it instead;
#   * disabled at Init when its command is; cmCommandSetChanged follows the
#     command set (redrawn only when the colours change, P3-12);
#   * setTitle, newButton, the constructor's refusals.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: TButton"

fvg_modeless
# dlg at (10, 4): ok 14 10 24 12 -> screen (24, 14) 10 x 2
fvg_cells 24 14 10; r0=$RESULT a0=$REPLY
fvg_cells 24 15 10; r1=$RESULT a1=$REPLY
fvw_check "default button, row 0: title centred (FV div), shadow cell" '    OK   ▄' "$r0"
fvw_check "default button, row 1: a blank and the bottom shadow" ' ▀▀▀▀▀▀▀▀▀' "$r1"
# colours: CButton 10..15 -> CGrayDialog 41..46 -> app symbols; default (not
# selected, the dialog active): text 2 (entry 11), shortcut 6 (entry 14)
fv.views.getColor ok 2; c2=$RESULT; fv.views.getColor ok 6; c6=$RESULT; fv.views.getColor ok 8; c8=$RESULT
fv.views.getColor ok 1; c1=$RESULT; fv.views.getColor ok 5; c5=$RESULT; fv.views.getColor ok 3; c3=$RESULT
fv.views.getColor ok 7; c7=$RESULT; fv.views.getColor ok 4; c4=$RESULT
fvw_check "default colours: text 2, the K in 6, shadow 8" "$c2$c2$c2$c2$c2$c6$c2$c2$c2$c8" "$a0"
fvg_cells 36 14 12
fvw_check "normal button (Cancel): text 1, shadow 8" "${c1}${c1}${c1}${c1}${c1}${c1}${c1}${c1}${c1}${c1}${c1}${c8}" "$REPLY"
fvw_check "normal button title" '   Cancel  ▄' "$RESULT"

kt_test_start "the focused button: selected colours (3 / 7); the default look leaves OK (2 -> 1)"
fv.views.focus cn
fvg_cells 36 14 12; ca=$REPLY
fvg_cells 24 14 10; cb=$REPLY
if [[ $ca == "$c3$c3$c3$c3$c3$c3$c3$c3$c3$c3$c3$c8" && ${cb:3:1} == "$c1" && ${ok_data[AmDefault]} == 0 ]]; then kt_test_pass ok
else kt_test_fail "cancel [$ca] ok [$cb] AmDefault ${ok_data[AmDefault]}"; fi
kt_test_start "focus away from the button: OK default again"
fv.views.focus opts
fvg_cells 24 14 10
if [[ ${REPLY:3:1} == "$c2" && ${ok_data[AmDefault]} == 1 && ${cn_data[AmDefault]} == 0 ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "[$REPLY] AmDefault ${ok_data[AmDefault]} / ${cn_data[AmDefault]} $FVW_DIFF"; fi

kt_test_start "makeDefault: a button without bfDefault takes and gives the default look"
fv.dialogs.makeDefault hp 1
a=${ok_data[AmDefault]}${hp_data[AmDefault]}
fv.dialogs.makeDefault hp 0
b=${ok_data[AmDefault]}${hp_data[AmDefault]}
if [[ $a$b == 0110 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a $b $FVW_DIFF"; fi

kt_test_start "pressed look: the title one cell right, no shadow"
fv.dialogs._btnState cn 1
fvg_cells 36 14 12; p0=$RESULT; fvg_cells 36 15 12; p1=$RESULT
fv.dialogs._btnState cn 0
if [[ $p0 == '    Cancel  ' && $p1 == '            ' ]]; then kt_test_pass ok; else kt_test_fail "[$p0] [$p1]"; fi

kt_test_start "disabled at Init: a command that is disabled; colours 4 / 4"
fv.views.disableCommands cmFind
TButton.new fb 2 7 12 9 '~F~ind' cmFind
st1=$(( fb_data[State] & FV_SF_DISABLED ))
fv.views.insert dlg fb
fvg_cells 12 11 10
if (( st1 )) && [[ $REPLY == "$c4$c4$c4$c4$c4$c4$c4$c4$c4$c8" ]]; then kt_test_pass ok; else kt_test_fail "state $st1 [$REPLY]"; fi
kt_test_start "cmCommandSetChanged: enabled again -> normal look (drawn once); unchanged -> not drawn"
fv.views.enableCommands cmFind
fvw_writes_on; FVW_WRITES=0
fv.views.message dlg evBroadcast cmCommandSetChanged || :
w1=$FVW_WRITES; FVW_WRITES=0
fv.views.message dlg evBroadcast cmCommandSetChanged || :
w2=$FVW_WRITES
fvw_writes_off
if (( ! (fb_data[State] & FV_SF_DISABLED) && w1 == 1 && w2 == 0 )); then kt_test_pass "writes $w1 / $w2"; else kt_test_fail "state ${fb_data[State]} writes $w1 / $w2"; fi
fv.views.delete dlg fb; fb.delete

# ---- keys ----
kt_test_section "003: hot keys, Enter / Space"
fv.views.focus opts
__FV_DR_PEND=()
kt_test_start "Alt+H presses Help: cmHelp posted with the button in FV_EV_INFO"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltH FV_EV_CHAR=h
fv.views._virt dlg HandleEvent
if [ "$FV_EV_WHAT" = evNothing ] && [ "${__FV_DR_PEND[0]-}" = evCommand ] && [ "${__FV_DR_PEND[3]-}" = cmHelp ] && [ "${__FV_DR_PEND[5]-}" = hp ]; then kt_test_pass ok
else kt_test_fail "what $FV_EV_WHAT pend ${__FV_DR_PEND[*]}"; fi
__FV_DR_PEND=()
kt_test_start "the plain letter h in the post-process phase presses Help (the focused cluster ignores it)"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=h
fv.views._virt dlg HandleEvent
if [ "${__FV_DR_PEND[3]-}" = cmHelp ]; then kt_test_pass ok; else kt_test_fail "pend ${__FV_DR_PEND[*]}"; fi
__FV_DR_PEND=()
kt_test_start "the plain letter in the pre-process phase does nothing (button called directly)"
dlg_data[Phase]=phPreProcess
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=h
fv.views._virt hp HandleEvent
if [ "$FV_EV_WHAT" = evKeyDown ] && (( ! ${#__FV_DR_PEND[@]} )); then kt_test_pass ok; else kt_test_fail "what $FV_EV_WHAT pend ${__FV_DR_PEND[*]}"; fi
kt_test_start "Enter / Space on the focused button press it"
fv.views.focus cn
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbEnter
fv.views._virt dlg HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=' '
fv.views._virt dlg HandleEvent; b=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [[ $a$b == cmCancelcmCancel ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] [$b] $FVW_DIFF"; fi
kt_test_start "Alt with a Cyrillic layout: Alt+р (base h) presses ~H~elp"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltH FV_EV_CHAR=р FV_EV_BASE=h
fv.views._virt dlg HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [ "$a" = cmHelp ]; then kt_test_pass ok; else kt_test_fail "[$a]"; fi
fv.drivers.clearEvent

kt_test_start "the modal run: Alt+K presses OK -> cmOK"
fv.views.delete desk dlg
fvg_run 'alt k'
if [ "$FVG_R" = cmOK ]; then kt_test_pass ok; else kt_test_fail "$FVG_R"; fi
kt_test_start "Enter in the dialog: the cmDefault broadcast presses the default button -> cmOK"
fv.views.select opts; fvg_run 'key kbTab' 'key kbEnter'
if [ "$FVG_R" = cmOK ]; then kt_test_pass ok; else kt_test_fail "$FVG_R"; fi
kt_test_start "Enter with Cancel focused: Cancel (default look moved) -> cmCancel"
fv.views.select opts; fvg_run 'key kbShiftTab' 'key kbShiftTab' 'key kbEnter'
if [ "$FVG_R" = cmCancel ] && [ "${dlg_data[Current]}" = cn ]; then kt_test_pass ok; else kt_test_fail "$FVG_R (current ${dlg_data[Current]})"; fi

# ---- mouse ----
kt_test_section "003: the mouse"
fv.views.insert desk dlg; fv.views.select dlg; fv.views.focus opts
kt_test_start "a click on Cancel presses it; the focus stays (no bfGrabFocus)"
fvg_events 'down 40 14' 'up 40 14'
fvw_getev; fv.views._virt app HandleEvent

pend=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fvw_noevents
if [ "$pend" = cmCancel ] && [ "${dlg_data[Current]}" = opts ] && [ "${cn_data[DownFlag]}" = 0 ] && fvw_full app; then kt_test_pass ok
else kt_test_fail "pend [$pend] current ${dlg_data[Current]} down ${cn_data[DownFlag]} $FVW_DIFF"; fi
kt_test_start "released off the button: nothing; released on its shadow: pressed"
fvg_events 'move 60 20' 'up 60 20'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=40 FV_EV_MOUSE_Y=14 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fvg_events 'up 48 16'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=40 FV_EV_MOUSE_Y=14 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; b=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fvw_noevents
if [[ -z $a && $b == cmCancel ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] [$b] $FVW_DIFF"; fi
kt_test_start "bfGrabFocus: a click focuses the button and presses it"
hp_data[Flags]=$(( hp_data[Flags] | FV_BF_GRABFOCUS ))
fvg_events 'up 52 14'
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=52 FV_EV_MOUSE_Y=14 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
fvw_noevents
if [[ $a == cmHelp && ${dlg_data[Current]} == hp ]]; then kt_test_pass ok; else kt_test_fail "[$a] current ${dlg_data[Current]}"; fi

# ---- Press ----
kt_test_section "003: Press"
class TRec : TView
    public
        override proc HandleEvent
end
TRec.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then GOT+="$FV_EV_COMMAND:$FV_EV_INFO;"; fi; }
build TRec
TRec.new rec 0 0 1 1
rec_data[EventMask]=$(( rec_data[EventMask] | FV_EM_BROADCAST ))
fv.views.insertBefore dlg rec ''
kt_test_start "cmRecordHistory reaches the owner's views before the command"
GOT=''
fv.views._virt cn Press
if [ "$GOT" = 'cmRecordHistory:;' ] && [ "${__FV_DR_PEND[3]-}" = cmCancel ]; then kt_test_pass ok; else kt_test_fail "[$GOT] ${__FV_DR_PEND[*]}"; fi
__FV_DR_PEND=()
kt_test_start "bfBroadcast: Command broadcast to the owner (INFO the button), nothing posted"
cn_data[Flags]=$FV_BF_BROADCAST; GOT=''
fv.views._virt cn Press
if [ "$GOT" = 'cmRecordHistory:;cmCancel:cn;' ] && (( ! ${#__FV_DR_PEND[@]} )); then kt_test_pass ok; else kt_test_fail "[$GOT] ${__FV_DR_PEND[*]}"; fi
cn_data[Flags]=0
fv.views.delete dlg rec; rec.delete

# ---- setters, helpers, refusals ----
kt_test_section "003: setTitle, newButton, refusals"
kt_test_start "setTitle: the new title drawn, its hot key works at once"
fv.dialogs.setTitle hp 'He~l~p me'
fvg_cells 50 14 10; t=$RESULT
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltL FV_EV_CHAR=l
fv.views._virt dlg HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [[ $t == ' Help me ▄' && $a == cmHelp ]]; then kt_test_pass ok; else kt_test_fail "[$t] [$a]"; fi
kt_test_start "a direct Title write is caught on the next key (the map's stamp)"
hp_data[Title]='~Q~uit'
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltQ FV_EV_CHAR=q
fv.views._virt dlg HandleEvent; a=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [ "$a" = cmHelp ]; then kt_test_pass ok; else kt_test_fail "[$a]"; fi
kt_test_start "newButton: a reserved name, HelpCtx, inserted, RESULT its name"
fv.dialogs.newButton dlg 2 7 10 2 '~X~yz' cmXyz 77 0; nb=$RESULT
if [[ $nb == dlg__fvbtn1 && ${dlg__fvbtn1_data[HelpCtx]} == 77 && ${dlg__fvbtn1_data[Owner]} == dlg ]]; then kt_test_pass ok; else kt_test_fail "[$nb]"; fi
kt_test_start "bfLeftJust: the title from cell 1"
dlg__fvbtn1_data[Flags]=$FV_BF_LEFTJUST; fv.views.drawView dlg__fvbtn1
fvg_cells 12 11 10
if [ "$RESULT" = ' Xyz     ▄' ]; then kt_test_pass ok; else kt_test_fail "[$RESULT]"; fi
kt_test_start "a wide title: cells counted by fv.video, cut to the room"
fv.dialogs.setTitle dlg__fvbtn1 '文件~保~存'; dlg__fvbtn1_data[Flags]=0; fv.views.drawView dlg__fvbtn1
fvg_row 11; w1=$RESULT
fv.dialogs.setTitle dlg__fvbtn1 '文件保存文件保存'; fv.views.drawView dlg__fvbtn1
fvg_row 11; w2=$RESULT
if [[ $w1 == *'║  文件保存▄ '* && $w2 == *'║ 文件保存 ▄ '* ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$w1] [$w2] $FVW_DIFF"; fi
kt_test_start "refusals: a bad command, bad flags, missing arguments (rc 2, one Error line, nothing made)"
e=$( { TButton.new zz1 0 0 5 2 'T' 'bad cmd'; echo "rc$?"; TButton.new zz2 0 0 5 2 'T' cmA x; echo "rc$?"; TButton.new zz3 0 0 5 2 'T'; echo "rc$?"; } 2>&1 )
n=$(grep -c '^Error: fv.dialogs: TButton.Create' <<< "$e")
if [[ $e == *rc2*rc2*rc2* && $n == 3 ]] && ! fv.views.isView zz1; then kt_test_pass ok; else kt_test_fail "[$e]"; fi
zz1.delete 2>/dev/null; zz2.delete 2>/dev/null; zz3.delete 2>/dev/null
kt_test_start "setTitle / makeDefault refuse a view that is no button (rc 2)"
rc1=0; fv.dialogs.setTitle opts x || rc1=$?
rc2=0; fv.dialogs.makeDefault ok 2 || rc2=$?
if [[ $rc1$rc2 == 22 ]]; then kt_test_pass ok; else kt_test_fail "$rc1 $rc2"; fi

fvg_unscene
