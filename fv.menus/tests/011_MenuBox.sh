#!/usr/bin/env bash
# 011_MenuBox.sh - TMenuBox in FV's flow (P3 §7.2, FV TMenuView.Execute,
# TMenuBox.Init / Draw, NewSubView): the box under the bar item, made by
# newSubView and executed by the bar's OWNER (the application: it sits
# beside the desktop, never inside a window) and destroyed after each drop;
# its draw (the frame, the separator, the Param right-aligned, the submenu
# mark, the current item's bar, a disabled item); the keys: Down / Up wrap
# and skip separators, Ctrl+X / Ctrl+E (CtrlToArrow), Home / End, a plain
# hot letter selects, Enter selects, Enter on a disabled item does nothing,
# Left / Right go to the neighbouring submenu of the bar, Alt+letter to
# another top item, a mapped key (F3) ends the menu with its command (FV
# TopMenu^.HotKey), **F10 inside does nothing** (FV: it falls to HotKey);
# **Esc**: in a box under the bar it closes the box and the bar (FV puts
# the Esc back to the bar), in a nested box only that box (FV clears it);
# TMenuPopup executed by a view's owner (the command, or execView's
# cmCancel; removed after); the screen == a full repaint after every close.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: the menu box"

fva_app 80 24 TMyApp
fvm_menu
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0
BX=app__fvmenubar__fvbox

ROWS='' CUR=''
rows() { fvm_cells 0 1 7 19; ROWS=$REPLY; fv.video.getRow 2; ROWS+="${REPLY:0:19}"; }
cur() { local c="${BX}_data[Current]"; CUR+="${!c-none},"; }
closed() { fvm_nobox && fvw_full app && echo 0; }
runq() { FVA_GOT=''; fva_events "$@"; app.Run; __FV_VW_EOF=0; }

runq 'key kbF10' 'key kbDown' 'run rows' 'key kbEsc'
fvw_check "the File box: under the item, FV's frame, ' NAME ', the Param ending at SizeX-3, the separator; the Default's bar" \
    " ┌───────────────┐ | │ Open...    F3 │ | │ Save       F2 │ | ├───────────────┤ | │ Exit    Alt+X │ | └───────────────┘ |2257555555555555522" "$ROWS"
fvw_check "Esc in a box under the bar closes the box AND the bar (FV: the Esc is put back to the bar); no box left; == a full repaint" \
    "-1|0" "${app__fvmenubar_data[Current]}|$(closed)"

CUR=''
runq 'key kbF10' 'key kbDown' 'run cur' 'key kbDown' 'run cur' 'key kbDown' 'run cur' 'key kbDown' 'run cur' 'key kbUp' 'run cur' \
    'key kbCtrlX' 'run cur' 'key kbCtrlE' 'run cur' 'key kbEnd' 'run cur' 'key kbHome' 'run cur' 'key kbF10' 'run cur' 'key kbEsc'
fvw_check "Down / Up wrap and skip the separator, Ctrl+X / Ctrl+E (CtrlToArrow), End / Home; F10 inside does nothing" \
    "3,4,6,3,6,3,6,6,3,3," "$CUR"
fvw_check "closed again: == a full repaint" "0" "$(closed)"

runq 'key kbF10' 'key kbDown' 'key kbChar s'
fvw_check "a plain hot letter in the box (s): Save selected, the menu closes, cmSave posted to the application" \
    "evCommand:cmSave;|0" "${FVA_GOT##*evBroadcast:cmReceivedFocus;}|$(closed)"
fvw_check "the box's Default is remembered (Save) and shown next time" "4" "${app__fvmenubar_mdef[1]}"

runq 'key kbF10' 'key kbDown' 'key kbF3'
fvw_check "F3 inside the box: TopMenu's HotKey -> cmOpen ends the menu, posted" "evCommand:cmOpen;|0" "${FVA_GOT##*evBroadcast:cmReceivedFocus;}|$(closed)"

BOXES=''
binfo() { fvm_box; local c="${REPLY}_data[Menu]"; BOXES+="${!c-};"; }
runq 'key kbF10' 'key kbDown' 'run binfo' 'key kbRight' 'run binfo' 'key kbLeft' 'run binfo' 'key kbAltW w' 'run binfo' 'key kbEsc'
fvw_check "Right / Left in a box: the neighbouring submenu of the bar; Alt+W: Window's (the event goes up to the bar)" \
    "app__fvmenubar:1;app__fvmenubar:2;app__fvmenubar:1;app__fvmenubar:3;|0" "$BOXES|$(closed)"

fv.views.disableCommands cmCut
fv.views.message app evBroadcast cmCommandSetChanged || :
DIS=''
dis() { fvm_cells 6 1 5 22; DIS=$REPLY; fvw_cells 6 3 7; DIS+=$REPLY; cur; }
CUR=''
runq 'key kbAltE e' 'key kbDown' 'run dis' 'key kbEnter' 'run cur' 'key kbChar t' 'run cur' 'key kbEsc'
fvw_check "the Edit box under its item (x 6); a disabled item (Cut): CSelDisabled when current; Enter on it and its hot letter do nothing" \
    " ┌──────────────────┐ | │ Undo             │ | │ Cut    Shift+Del │ | └──────────────────┘ |2266666|8,8,8," "$DIS|$CUR"
fvw_check "closed: no command reached the application, == a full repaint" "0|" "$(closed)|$(printf '%s' "$FVA_GOT" | grep -o 'evCommand:cm[A-Z][a-z]*;' | grep -v cmMenu)"
fv.views.enableCommands cmCut

# nested: Window > Layout; Esc in Layout closes only Layout (FV clears it), Esc in Window closes Window and the bar
BOXES=''
runq 'key kbAltW w' 'run binfo' 'key kbUp' 'key kbEnter' 'run binfo' 'key kbEsc' 'run binfo' 'key kbEsc'
fvw_check "Esc in a nested box closes only that box (Window's box shows again), Esc in Window's closes the rest" \
    "app__fvmenubar:3;app__fvmenubar:4;app__fvmenubar:3;|0" "$BOXES|$(closed)"
LAY=''
lay() { fvm_box; fv.views.getBounds "$REPLY"; LAY="$RESULT;"; fvm_cells 12 1 8 30; LAY+=$REPLY; }
runq 'key kbAltW w' 'key kbChar l' 'run lay' 'key kbChar c'
fvw_check "the nested box: from Layout's text column, under its row; the submenu mark at SizeX-4 of Window's box; c picks Cascade" \
    "14 4 28 8; ┌────────────┐ ░░░░░░░░░░░░░░| │ Next    F6 │ ─────1─────┐░░| │ Layout   ► │            │░░| └ ┌──────────┐            │░░| w │ Tile     │            │░░| w │ Cascade  │   ╔═[■]═══════| w └──────────┘   ║>row 0 of w|" "$LAY"
fvw_check "cmCascade posted after the menu, == a full repaint" "evCommand:cmCascade;|0" "${FVA_GOT##*evBroadcast:cmReceivedFocus;}|$(closed)"

# TMenuPopup: executed by a view's owner
TMenuPopup.new pop 20 5 60 20 item '~C~opy' 'Ctrl+Ins' kbCtrlIns cmCopy 0 item '~P~aste' '' '' cmPaste 0
fva_events 'key kbDown' 'key kbEnter'
__FV_MN_RES=''
fv.views.execView "$FV_DESKTOP" pop
r1=$RESULT o1=${pop_data[Owner]-}
fva_events 'key kbEsc'
fv.views.execView "$FV_DESKTOP" pop
r2="$RESULT/$__FV_MN_RES"
fva_events 'key kbChar c'
fv.views.execView "$FV_DESKTOP" pop
fvw_check "TMenuPopup run by its owner: Down Enter -> cmPaste; Esc -> execView's cmCancel (Execute answered none); c -> cmCopy; removed after" \
    "cmPaste||cmCancel/|cmCopy" "$r1|$o1|$r2|$RESULT"
fvw_check "the popup's Default follows the last choice; == a full repaint" "0|0" "${pop_mdef[0]}|$(fvw_full app && echo 0)"
pop.delete

fva_unapp
kt_test_log "011_MenuBox.sh completed"
