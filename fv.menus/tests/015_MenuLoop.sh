#!/usr/bin/env bash
# 015_MenuLoop.sh - the menus' own event loop (P3 §7.2 / §7.3, the fourth
# inner loop after execView, mouseEvent and dragView; P2 §2.2's rules): it
# reads through the application's GetEvent (__FV_VW_GETEVENT: Idle and the
# resizes run while a menu is open; a resize keeps the bar's row and the
# desktop below it), the END OF INPUT latches and closes every level with
# no command (one box, two nested boxes), a failing source is taken for the
# end of input, a SUBSHELL refuses (the BASHPID rule: execView and Execute
# rc 2, nothing drawn or posted), the event record is put back (FV's local
# E: through execView and through a direct Execute).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "015: the menu loop"

fva_app 80 24 TMyApp
fvm_menu
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0
B=$FV_MENUBAR
closed() { fvm_nobox && fvw_full app && echo 0; }
cmds() { REPLY=''; local x=$FVA_GOT; while [[ $x == *evCommand:* ]]; do x=${x#*evCommand:}; REPLY+="${x%%;*},"; done; }

FVA_GOT=''
fva_events 'key kbF10' 'key kbDown'
app.Run; rc=$?
cmds
fvw_check "the end of input inside the box: every level closes, no command, Run ends (latched)" \
    "0|1|cmMenu,|-1|0" "$rc|$__FV_VW_EOF|$REPLY|${app__fvmenubar_data[Current]}|$(closed)"
__FV_VW_EOF=0

FVA_GOT=''
fva_events 'key kbAltW w' 'key kbChar l'
app.Run
cmds
fvw_check "the end of input in a nested box (Window > Layout): both boxes and the bar close, no command" "1||0" "$__FV_VW_EOF|$REPLY|$(closed)"
__FV_VW_EOF=0

FVA_GOT=''
fva_events 'key kbF10' 'key kbDown' 'fail 3'
VERBOSE_KKLASS=quiet app.Run
fvw_check "a failing event source (rc 3) is taken for the end of input" "1|0" "$__FV_VW_EOF|$(closed)"
__FV_VW_EOF=0

kt_test_start "a subshell refuses: execView of the bar and its Execute answer rc 2, nothing posted, nothing drawn"
fva_events 'key kbDown' 'key kbEnter'
before=$(fvw_snap; printf '%s' "$REPLY")
r1=$( fv.views.execView app "$B" >/dev/null 2>&1; echo $? )
r2=$( fv.views._virt "$B" Execute >/dev/null 2>&1; echo "$?:${#__FV_DR_PEND[@]}" )
after=$(fvw_snap; printf '%s' "$REPLY")
if [[ $r1 == 2 && $r2 == 2:0 && $before == "$after" && ${#__FV_DR_PEND[@]} == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "r1 $r1 r2 $r2 same $([[ $before == "$after" ]] && echo y)"; fi

kt_test_start "the event record is put back: through execView (bar) and a direct Execute (FV's local E)"
rec() { REPLY="$FV_EV_WHAT|$FV_EV_KEY|$FV_EV_CHAR|$FV_EV_COMMAND|$FV_EV_INFO|$FV_EV_MOUSE_X|$FV_EV_MOUSE_Y|${FV_EV_BASE-}"; }
fv.drivers.clearEvent
FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF7 FV_EV_CHAR=q FV_EV_INFO=zz FV_EV_MOUSE_X=7 FV_EV_MOUSE_Y=9 FV_EV_BASE=w
rec; want=$REPLY
fva_events 'key kbRight' 'key kbEsc'
__FV_MN_RES=x
fv.views.execView app "$B"
rec; g1="$REPLY/$RESULT/$__FV_MN_RES"
fva_events 'key kbRight' 'key kbEnter' 'key kbDown' 'key kbEnter'
__FV_MN_RES=x
fv.views._virt "$B" Execute
rec; g2="$REPLY/$RESULT/$__FV_MN_RES"
if [[ $g1 == "$want/cmCancel/" && $g2 == "$want/cmCut/cmCut" ]]; then kt_test_pass "ok"; else kt_test_fail "[$g1] [$g2] want [$want]"; fi
fvw_check "after a direct Execute (no execView): == a full repaint" "0" "$(closed)"

# a resize while a box is open: handled at once by the application's GetEvent
RS=''
rs() { fva_b "$FV_MENUBAR"; RS+="$REPLY;"; fva_b "$FV_DESKTOP"; RS+="$REPLY;"; fvm_box; RS+="$REPLY;"; }
fva_events 'key kbF10' 'key kbDown' 'resize 100 30' 'run rs' 'key kbDown' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fvw_check "a resize while the box is open: the bar takes the width (gfGrowHiX), the desktop keeps row 1, the box stays" \
    "0 0 100 1;0 1 100 29;app__fvmenubar__fvbox;" "$RS"
fvw_check "closed after the resize: == a full repaint" "0" "$(closed)"

fva_unapp
kt_test_log "015_MenuLoop.sh completed"
