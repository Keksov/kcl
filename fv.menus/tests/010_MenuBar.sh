#!/usr/bin/env bash
# 010_MenuBar.sh - TMenuBar in an application (P3 §7.2, FV TMenuBar /
# TMenuView.HandleEvent / DoSelect): its draw (one write; the colours of
# FV's CMenuView, the hot letters, a disabled item, the current one), the
# pre-processed keys through the application's dispatch (a mapped key posts
# its command — FV HotKey —, a disabled one does not and the key goes on;
# Alt+letter opens that submenu; a key it does not know goes on), cmMenu
# from the status line's F10 (the bar runs modal in the application: the
# Default item highlighted, Left / Right / Ctrl+S / Ctrl+D move with
# wrapping, Esc leaves, the Default is remembered), Enter / Down on the
# bar drops the box, a command chosen is posted to the application after
# the menu, cmCommandSetChanged (redrawn only when an item it shows changed:
# 1 / 0 writes), the screen == a full repaint after every close.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: the menu bar"

fva_app 80 24 TMyApp
fvm_menu
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0
B=$FV_MENUBAR
fvw_row 0
fvw_check "the bar: ' File  Edit  Window ' in CNormal, the hot letters Hi, blanks to the width" \
    " File  Edit  Window |242222242222242222222" "${RESULT:0:20}|${REPLY:0:21}"
fvw_budgetw bar-draw 0 fv.views.drawView "$B"
fvw_check "the bar's draw: one write, no dispatch" "0 1" "$FVW_LASTC $FVW_LASTW"

# keys through the application's dispatch (the bar pre-processes them)
key() {   # KEY [CHAR]: one key event through the app's HandleEvent
    fv.drivers.clearEvent; __FV_DR_PEND=()
    FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-}
    fv.views._virt app HandleEvent
}
key kbF3
fvw_check "a mapped key (F3, Open in File): its command posted, the key handled (FV HotKey)" \
    "evNothing|evCommand cmOpen" "$FV_EV_WHAT|${__FV_DR_PEND[0]-} ${__FV_DR_PEND[3]-}"
key kbAltX x
fvw_check "Alt+X: no top item with hot letter x -> HotKey: Exit's cmQuit posted" "evNothing|cmQuit" "$FV_EV_WHAT|${__FV_DR_PEND[3]-}"
fv.views.disableCommands cmSave
key kbF2
fvw_check "a disabled command's key (F2, Save) is not taken: posts nothing" "|" "${__FV_DR_PEND[3]-}|${__FV_DR_PEND[1]-}"
fv.views.enableCommands cmSave
FVA_GOT=''
key kbF9
fvw_check "a key no item has goes on to the desktop and the application" "evKeyDown:kbF9;" "$FVA_GOT"

# F10 -> the status line posts cmMenu -> the bar runs modal
snap() { fvw_row 0; SNAP+="${REPLY:0:21},"; }
SNAP=''
fva_events 'key kbF10' 'run snap' 'key kbRight' 'run snap' 'key kbCtrlD' 'run snap' 'key kbRight' 'run snap' 'key kbCtrlS' 'run snap' 'key kbEsc' 'run snap'
FVA_GOT=''
app.Run; __FV_VW_EOF=0
fvw_check "F10: the bar highlights its Default (File); Right / Ctrl+D / Right (wraps) / Ctrl+S move; Esc leaves it plain" \
    "575555242222242222222,242222575555242222222,242222242222575555552,575555242222242222222,242222242222575555552,242222242222242222222," "$SNAP"
fvw_check "the Default is remembered (Window); the application saw F10, cmMenu and the focus broadcasts, no command" \
    "2|evKeyDown:kbF10;evCommand:cmMenu;" "${app__fvmenubar_mdef[0]}|${FVA_GOT%%evBroadcast*}"
fvw_check "after the menu: no box, the bar not current, the screen == a full repaint" "-1|0" "${app__fvmenubar_data[Current]}|$(fvm_nobox && fvw_full app && echo 0)"

# Enter on the bar's Default (Window) drops its box; Up to Layout, Enter drops Layout's; Enter -> Tile
boxinfo() { fvm_box; local o="${REPLY}_data[Owner]"; BOXES+="$REPLY>${!o-};"; }
BOXES=''
fva_events 'key kbF10' 'key kbEnter' 'run boxinfo' 'key kbUp' 'key kbEnter' 'run boxinfo' 'key kbEnter'
FVA_GOT=''
app.Run; __FV_VW_EOF=0
fvw_check "Enter on the bar drops the box (in the application, owned by it); Enter on a submenu item drops the next one there too" \
    "app__fvmenubar__fvbox>app;app__fvmenubar__fvbox__fvbox>app;" "$BOXES"
fvw_check "Enter on Tile: the menu closes and cmTile is posted to the application (FV DoSelect)" \
    "evCommand:cmTile;" "${FVA_GOT##*evBroadcast:cmReceivedFocus;}"
fvw_check "no box left, the Defaults remembered (Window, Layout, Tile), the screen == a full repaint" \
    "0|2 10 11" "$(fvm_nobox && fvw_full app && echo 0)|${app__fvmenubar_mdef[0]} ${app__fvmenubar_mdef[3]} ${app__fvmenubar_mdef[4]}"

# Alt+F: the bar's pre-process finds File (hot letter f) and DoSelect drops it at once
BOXES=''
fva_events 'key kbAltF f' 'run boxinfo' 'key kbEsc'
app.Run; __FV_VW_EOF=0
fvw_check "Alt+F opens File's box at once; Esc closes the box and the bar (FV: the box puts Esc back to the bar)" \
    "app__fvmenubar__fvbox>app;|0|0" "$BOXES|${app__fvmenubar_mdef[0]}|$(fvm_nobox && fvw_full app && echo 0)"

# cmCommandSetChanged: a bar with a top-level command item
TMenuBar.new mb2 0 0 80 1 item '~H~elp' F1 kbF1 cmHelp 0 sub '~F~ile' item 'a' '' '' cmA 0 end
fv.views.insert app mb2
fvw_row 0
fvw_check "a top-level command item draws like a submenu one" " Help  File |242222242222" "${RESULT:0:12}|${REPLY:0:12}"
fv.views.disableCommands cmHelp
fvw_budgetw cmd-changed 2 fv.views.message app evBroadcast cmCommandSetChanged
fvw_row 0
fvw_check "cmCommandSetChanged: the item greyed (CNormDisabled 2/2), redrawn: 1 write (mb2; the other bar shows nothing that changed; the 2 dispatches are TMyApp's)" \
    "1|333333242222" "$FVW_LASTW|${REPLY:0:12}"
fvw_budgetw cmd-same 2 fv.views.message app evBroadcast cmCommandSetChanged
fvw_check "cmCommandSetChanged again, nothing changed: no write" "0" "$FVW_LASTW"
fv.views.enableCommands cmHelp
fv.views.message app evBroadcast cmCommandSetChanged || :
fvw_row 0
fvw_check "enabled again: drawn plain" "242222242222" "${REPLY:0:12}"
fv.views.delete app mb2; mb2.delete
fvw_check "the screen == a full repaint" "0" "$(fvw_full app && echo 0)"

fva_unapp
fvw_check "the application's Done destroys the bar (its arrays freed)" "|" "${app__fvmenubar_mtext+set}|${__FV_MN_MV[app__fvmenubar]-}"

kt_test_log "010_MenuBar.sh completed"
