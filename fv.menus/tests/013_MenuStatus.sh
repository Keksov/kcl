#!/usr/bin/env bash
# 013_MenuStatus.sh - the menus and the status line (D22, P3 §7.2): the hint
# table (fv.menus.setHint: the built-in Hint answers from it, '' removes an
# entry, a redraw only when the line shows that context, an override of
# Hint still wins, the table freed with the line, refusals); while a menu
# runs it is the top view, so the Idle between events (FV) makes the status
# line show the current item's hint: a move to an item with another hint
# redraws the line, the bar's own items and an item without a context walk
# up the parent menus (FV TMenuView.GetHelpCtx: Undo (0) -> Edit's 1200,
# Cascade (0) -> Layout's 1110); after the menu the line goes back.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: the hint table and the menus' help contexts"

fva_app 80 24
fvm_menu
SL=$FV_STATUSLINE
fv.menus.setHint "$SL" 1001 'Open a file'
fv.menus.setHint "$SL" 1002 'Save the file'
fv.menus.setHint "$SL" 1200 'Edit the text'
fv.menus.setHint "$SL" 1110 'Arrange the windows'
fv.menus.setHint "$SL" 1003 ''
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0

RESULT=keep
fv.views._virt "$SL" Hint 1001
a=$RESULT
fv.views._virt "$SL" Hint 1003; b=$RESULT
fv.views._virt "$SL" Hint 77; c=$RESULT
fvw_check "the built-in Hint answers from the table; '' removed an entry; an unknown context: ''" "Open a file|||4" "$a|$b|$c|${#app__fvstatus_hints[@]}"

kt_test_start "setHint while the line shows that context: redrawn (1 write); another context: no write"
app__fvstatus_data[HelpCtx]=0
fvw_writes_on; FVW_WRITES=0
fv.menus.setHint "$SL" 0 'Ready'
w1=$FVW_WRITES; FVW_WRITES=0
fv.menus.setHint "$SL" 5 'Five'
w2=$FVW_WRITES; FVW_WRITES=0
fv.menus.setHint "$SL" 0 'Ready'
w3=$FVW_WRITES
fvw_writes_off
fvw_row 23
if [[ "$w1 $w2 $w3" == "1 0 0" && $RESULT == ' Alt-X Exit │ Ready '* ]]; then kt_test_pass "ok"; else kt_test_fail "writes $w1 $w2 $w3 row [$RESULT]"; fi
fv.menus.setHint "$SL" 0 ''

kt_test_start "setHint refusals: not a status line, a bad HELPCTX, the count (rc 2); RESULT kept on success"
r=''
fv.menus.setHint nosuch 1 x; r+=$?
fv.menus.setHint "$SL" hc1 x; r+=$?
fv.menus.setHint "$SL" 1; r+=$?
RESULT=keep; fv.menus.setHint "$SL" 9 nine; r+="$?$RESULT"
if [[ $r == 2220keep ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

HL=''
hl() { fvw_row 23; HL+="${app__fvstatus_data[HelpCtx]}:${RESULT:12:22};"; }
FVA_GOT=''
fva_events 'key kbF10' 'nothing' 'run hl' 'key kbDown' 'nothing' 'run hl' 'key kbDown' 'nothing' 'run hl' 'key kbRight' 'nothing' 'run hl' \
    'key kbEsc' 'nothing' 'run hl'
app.Run; __FV_VW_EOF=0
fvw_check "F10: the bar (File: no context); Down: Open's hint; Down: Save's; Right: Edit's Undo (0) -> Edit's 1200; after: back" \
    "0:                      ;1001:│ Open a file         ;1002:│ Save the file       ;1200:│ Edit the text       ;0:                      ;" "$HL"

HL=''
fva_events 'key kbAltW w' 'nothing' 'run hl' 'key kbChar l' 'nothing' 'run hl' 'key kbDown' 'nothing' 'run hl' 'key kbEsc' 'nothing' 'run hl' 'key kbEsc' 'nothing' 'run hl'
app.Run; __FV_VW_EOF=0
fvw_check "Window > Next (1101, no hint); Layout's box: Tile (1111); Cascade (0) -> Layout's 1110 up the parents; Esc: Window's box on Layout; Esc" \
    "1101:                      ;1111:                      ;1110:│ Arrange the windows ;1110:│ Arrange the windows ;0:                      ;" "$HL"

RESULT=x
fv.views._virt "$FV_MENUBAR" GetHelpCtx
fvw_check "GetHelpCtx of the bar outside its run (no Current): hcNoContext; a func answer" "0" "$RESULT"

# an override of Hint still wins over the table
class TMyStatus : TStatusLine
    public
        override func Hint
end
TMyStatus.Hint() { RESULT="mine $1"; }
build TMyStatus
TMyStatus.new ms 0 0 80 1 'a' kbF2 cmA
fv.menus.setHint ms 3 'table'
fv.views._virt ms Hint 3
fvw_check "a Hint override wins over the table" "mine 3" "$RESULT"
ms.delete
fvw_check "the destructor frees the hint table" "" "${ms_hints+set}"
fvw_check "the screen == a full repaint" "0" "$(fvw_full app && echo 0)"

fva_unapp
kt_test_log "013_MenuStatus.sh completed"
