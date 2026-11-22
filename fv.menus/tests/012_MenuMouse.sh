#!/usr/bin/env bash
# 012_MenuMouse.sh - the menus and the mouse (FV TMenuView.Execute's mouse
# cases: TrackMouse, MouseInOwner, MouseInMenus; TMenuView.HandleEvent's
# evMouseDown -> DoSelect): a press on a bar item opens its box at once
# (the press is put back for the box, which sees it on its parent's item),
# a drag into the box highlights the item under the pointer, the release on
# an item chooses it; a release on the bar item keeps the box open with its
# Default; a drag along the bar switches the box; a press outside every
# menu closes them all with no command; a release on a separator closes
# the bar too (FV: MouseActive from the press); a popup chosen by a
# press + release; the screen == a full repaint after every close.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "012: the menus and the mouse"

fva_app 80 24 TMyApp
fvm_menu
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0

closed() { fvm_nobox && fvw_full app && echo 0; }
runq() { FVA_GOT=''; fva_events "$@"; app.Run; __FV_VW_EOF=0; }
cmds() { REPLY=''; local x=$FVA_GOT; while [[ $x == *evCommand:* ]]; do x=${x#*evCommand:}; REPLY+="${x%%;*},"; done; }
ST=''
st() { fvm_box; local c="${REPLY}_data[Current]" m="${REPLY}_data[Menu]"; ST+="${!m-none}/${!c-}/${app__fvmenubar_data[Current]};"; }

runq 'down 2 0' 'run st' 'move 3 3' 'run st' 'up 3 3'
cmds
fvw_check "press on File: its box at once, nothing highlighted (the press lies on the parent's item); drag to Save; release: cmSave" \
    "app__fvmenubar:1/-1/0;app__fvmenubar:1/4/0;|cmSave,|0" "$ST|${REPLY#evKeyDown*}|$(closed)"
# (the press reaches the bar through the application's positional dispatch:
# FVA_GOT starts with the press, not cmMenu)
fvw_check "the press went to the bar by the application's positional dispatch (TMyApp saw it first)" "evMouseDown:;" "${FVA_GOT%%evBroadcast*}"

ST=''
runq 'down 2 0' 'up 2 0' 'run st' 'down 50 15' 'run st'
cmds
fvw_check "release on the bar item: the box stays with its Default (Save, remembered); a press outside closes every menu, no command" \
    "app__fvmenubar:1/4/0;none//-1;|" "$ST|${REPLY//cmMenu,/}"
fvw_check "closed: == a full repaint" "0" "$(closed)"

ST=''
runq 'down 2 0' 'move 8 0' 'run st' 'move 14 0' 'run st' 'up 14 0' 'run st' 'key kbEsc'
fvw_check "drag along the bar: Edit's box, then Window's; the release on Window keeps its box with its Default" \
    "app__fvmenubar:2/-1/1;app__fvmenubar:3/-1/2;app__fvmenubar:3/9/2;|0" "$ST|$(closed)"

ST=''
runq 'down 2 0' 'move 3 4' 'run st' 'up 3 4' 'run st'
fvw_check "release on the separator: the box returns, and the bar too (FV: MouseActive from the press on File); no command" \
    "app__fvmenubar:1/5/0;none//-1;|0" "$ST|$(closed)"

ST=''
runq 'down 2 0' 'move 3 2' 'moveup 3 3' 'run st' 'wheel 3 3' 'up 3 2'
cmds
fvw_check "a move without a button is not tracked; a wheel event changes nothing; the release on Open chooses it" \
    "app__fvmenubar:1/3/0;|cmOpen," "$ST|${REPLY//cmMenu,/}"
fvw_check "closed: == a full repaint" "0" "$(closed)"

TMenuPopup.new pop 20 5 60 20 item '~C~opy' '' '' cmCopy 0 item '~P~aste' '' '' cmPaste 0
fva_events 'down 23 8' 'up 23 8'
fv.views.execView "$FV_DESKTOP" pop
r1=$RESULT
fva_events 'down 70 20'
__FV_MN_RES=''
fv.views.execView "$FV_DESKTOP" pop
fvw_check "a popup: press + release on Paste -> cmPaste; a press outside -> none (execView's cmCancel)" "cmPaste|cmCancel/" "$r1|$RESULT/$__FV_MN_RES"
fvw_check "the popup is removed after each run: == a full repaint" "|0" "${pop_data[Owner]-}|$(fvw_full app && echo 0)"
pop.delete

fva_unapp
kt_test_log "012_MenuMouse.sh completed"
