#!/usr/bin/env bash
# 016_MenuBar.sh - the menu bar only on request (D23, P3 10.10): without one
# nothing changes (FV_MENUBAR '', the desktop keeps row 0, the application
# holds the desktop and the status line only); fv.menus.menuBar before Run
# makes the bar on row 0 (in front) and moves the desktop to row 1; a resize
# keeps that layout; called again it replaces the bar (the old one
# destroyed), with no items it removes the bar and the desktop gets row 0
# back; a malformed list changes nothing; no application: rc 2. FV's way,
# an InitMenuBar override that makes a TMenuBar and sets FV_MENUBAR, and
# menuBar called inside InitMenuBar both give FV's order (desktop, status
# line, bar in front). The screen == a full repaint after every change.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "016: the menu bar on request"

full() { fvw_full app && echo 0; }

fv.menus.menuBar sub '~F~ile' item 'a' '' '' cmA 0 end; rc=$?
fvw_check "menuBar without an application: rc 2" "2" "$rc"

fva_app 80 24
fva_b "$FV_DESKTOP"
fvw_check "no bar by default: FV_MENUBAR '', the desktop on row 0, the application holds the desktop and the status line" \
    "|0 0 80 23|app__fvdesktop app__fvstatus" "$FV_MENUBAR|$REPLY|${app_views[*]}"
fva_paint
fvw_row 0
fvw_check "row 0 is the desktop's (its background)" "░░░░░░░░░░" "${RESULT:0:10}"

fvm_menu
fva_b "$FV_DESKTOP"; d=$REPLY
fva_b "$FV_MENUBAR"
fvw_check "menuBar after Init: the bar APP__fvmenubar on row 0, in front; the desktop from row 1" \
    "app__fvmenubar|0 0 80 1|0 1 80 23|app__fvdesktop app__fvstatus app__fvmenubar" "$FV_MENUBAR|$REPLY|$d|${app_views[*]}"
fvw_row 0
fvw_check "drawn at once (the application is exposed); == a full repaint" " File  Edit  Window |0" "${RESULT:0:20}|$(full)"

RS=''
rs() { fva_b "$FV_MENUBAR"; RS+="$REPLY/"; fva_b "$FV_DESKTOP"; RS+="$REPLY/"; fva_b "$FV_STATUSLINE"; RS+="$REPLY;"; }
fva_events 'resize 100 30' 'run rs' 'resize 60 20' 'run rs'
app.Run; __FV_VW_EOF=0
fvw_check "a resize keeps the layout: the bar row 0 (gfGrowHiX), the desktop from row 1, the status line last" \
    "0 0 100 1/0 1 100 29/0 29 100 30;0 0 60 1/0 1 60 19/0 19 60 20;" "$RS"
fvw_check "after the resizes: == a full repaint" "0" "$(full)"

old_arrays=${#app__fvmenubar_mtext[@]}
fv.menus.menuBar sub '~H~elp' item '~A~bout' '' '' cmAbout 0 end item '~Q~uit' Alt+X kbAltX cmQuit 0
fvw_row 0; r0=$RESULT
fva_b "$FV_DESKTOP"
fvw_check "menuBar again: the bar replaced (its items new), the desktop still from row 1, one bar in the application" \
    "13|3| Help  Quit |0 1 60 19|app__fvdesktop app__fvstatus app__fvmenubar|0" \
    "$old_arrays|${#app__fvmenubar_mtext[@]}|${r0:0:12}|$REPLY|${app_views[*]}|$(full)"

VERBOSE_KKLASS=quiet fv.menus.menuBar sub 'x'; rc=$?
fvw_check "a malformed list changes nothing (rc 2)" "2|app__fvmenubar|3" "$rc|$FV_MENUBAR|${#app__fvmenubar_mtext[@]}"

fv.menus.menuBar
fvw_row 0; r0=$RESULT
fva_b "$FV_DESKTOP"
fvw_check "menuBar with no items: the bar removed and destroyed, the desktop gets row 0 back" \
    "|0 0 60 19|app__fvdesktop app__fvstatus||░░░░░░░░░░|0" "$FV_MENUBAR|$REPLY|${app_views[*]}|${app__fvmenubar_mtext+set}|${r0:0:10}|$(full)"
fvw_check "no menu view left" "0" "${#__FV_MN_MV[@]}"
fva_unapp

# FV's way: an InitMenuBar override
class TBarApp : TApplication
    public
        override proc InitMenuBar
end
TBarApp.InitMenuBar() {
    local -n d=${this}_data
    TMenuBar.new mybar 0 0 "${d[SizeX]}" 1 sub '~F~ile' item '~N~ew' '' '' cmNew 0 end
    FV_MENUBAR=mybar
}
build TBarApp
class TBarApp2 : TApplication
    public
        override proc InitMenuBar
end
TBarApp2.InitMenuBar() { fv.menus.menuBar sub '~F~ile' item '~N~ew' '' '' cmNew 0 end; }
build TBarApp2

for cls in TBarApp TBarApp2; do
    fva_app 80 24 "$cls"
    fva_b "$FV_DESKTOP"; d=$REPLY
    fva_paint
    fvw_row 0; r0=$RESULT
    fva_b "$FV_MENUBAR"
    fvw_check "$cls (InitMenuBar makes the bar): row 0, the desktop from row 1, FV's order (desktop, status line, bar)" \
        "0 0 80 1|0 1 80 23|app__fvdesktop app__fvstatus $FV_MENUBAR| File |0" "$REPLY|$d|${app_views[*]}|${r0:0:6}|$(full)"
    b=$FV_MENUBAR
    fva_unapp
    fvw_check "$cls: Done destroys the bar" "|0" "${__FV_MN_MV[$b]-}|${#__FV_MN_MV[@]}"
done

kt_test_log "016_MenuBar.sh completed"
