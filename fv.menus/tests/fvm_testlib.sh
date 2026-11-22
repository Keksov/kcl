#!/usr/bin/env bash
# fvm_testlib.sh — what the fv.menus test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only). It reuses fv.views' test lib
# (fv.views/tests/fvw_testlib.sh: the headless screen, the buffer reader,
# both counters, fvw_budget, the scripted event source fvw_events, fvw_root,
# the scene classes TTApp / TTLeaf and fvw_mktwin) and adds:
#
#   fvm_init NAME "$@"    ktest init + fv.menus (with fv.views) + $FVW_TMP;
#                         the file's stderr is captured as in fvw_init:
#                         anything on it fails one test at exit
#   fvm_mkst NAME AX AY BX BY
#                         the test status line: def 0..99 with
#                         '~Alt+X~ Exit' kbAltX cmQuit, '~F10~ Menu' kbF10
#                         cmMenu, a key-only kbF6 cmNext, '~F5~ Zoom' kbF5
#                         cmZoom (disabled at the start: FV's default set);
#                         def 100..199 with '~F1~ Help' kbF1 cmHelp,
#                         '~Esc~ Cancel' kbEsc cmCancel
#   fvm_scene [W H]       a headless screen and the application-like scene:
#                         app (TTApp, fvw_root) > desk (TGroup, rows 0..H-2)
#                         > bg, w1 (2 1 40 20) and w2 in front (30 5 70 22),
#                         TWindows with a TTLeaf each; the status line st
#                         (fvm_mkst) on the last row in front of desk, as
#                         FV's TProgram.Init inserts it. Not drawn yet
#   fvm_unscene           app.delete
#   fvm_draw              the whole scene drawn (fv.views.drawView app)
#   fvm_st                RESULT / REPLY = the status line's row (text /
#                         symbols)

FVM_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVM_TESTS_DIR/../../fv.views/tests/fvw_testlib.sh"

fvm_init() {
    local name=$1
    shift
    source "$FVM_TESTS_DIR/../fv.menus.sh"
    kt_test_init "$name" "$FVM_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

fvm_mkst() {
    TStatusLine.new "$1" "$2" "$3" "$4" "$5" \
        def 0 99 '~Alt+X~ Exit' kbAltX cmQuit '~F10~ Menu' kbF10 cmMenu '' kbF6 cmNext '~F5~ Zoom' kbF5 cmZoom \
        def 100 199 '~F1~ Help' kbF1 cmHelp '~Esc~ Cancel' kbEsc cmCancel
}

fvm_scene() {
    local w=${1:-80} h=${2:-24}
    fvw_screen "$w" "$h"
    fvw_classes2
    TTApp.new app 0 0 "$w" "$h"
    TGroup.new desk 0 0 "$w" $(( h - 1 ))
    TView.new bg 0 0 "$w" $(( h - 1 ))
    fv.views.insert desk bg
    fvw_mktwin w1 2 1 40 20 'Files' 1
    fvw_mktwin w2 30 5 70 22 'Panel two' 2
    fv.views.insert desk w1
    fv.views.insert desk w2
    fvm_mkst st 0 $(( h - 1 )) "$w" "$h"
    fv.views.insert app desk
    fv.views.insert app st
    fvw_root app
    FVW_DRAWS=() FVW_GOT='' FVW_ROW=()
}
fvm_unscene() { app.delete; }
fvm_draw() { fv.views.drawView app; }
fvm_st() { fv.video.getRow $(( FV_SCREEN_H - 1 )); }

# P3 stage 3f (the menus). The menu test files run in an application: they
# source fv.app's test lib (fva_testlib.sh, which sources this one) and call
# fva_init / fva_app; then:
#   fvm_menu              the test menu bar through fv.menus.menuBar (items:
#                         0 File 1 Edit 2 Window | 3 Open (F3, 1001) 4 Save
#                         (F2, 1002) 5 line 6 Exit (Alt+X, 1003) | 7 Undo
#                         (Alt+Backspace, help 0) 8 Cut (Shift+Del, 1202) |
#                         9 Next (F6, 1101) 10 Layout (1110) | 11 Tile
#                         (1111) 12 Cascade (help 0); Edit 1200, Window 1100)
#   fvm_box               REPLY = the menu box in the application now (its
#                         front-most TMenuBox, '' none)
#   fvm_rows Y1 Y2        REPLY = rows Y1 .. Y2-1 as text, joined by '|'
#   fvm_nobox             rc 0 when no box instance is left (no
#                         *__fvbox*_data variable, no box in __FV_MN_MV)
fvm_menu() {
    fv.menus.menuBar \
        sub '~F~ile' \
            item '~O~pen...' F3 kbF3 cmOpen 1001 \
            item '~S~ave' F2 kbF2 cmSave 1002 \
            line \
            item 'E~x~it' Alt+X kbAltX cmQuit 1003 \
        end \
        sub '~E~dit' 1200 \
            item '~U~ndo' '' kbAltBack cmUndo 0 \
            item 'Cu~t~' Shift+Del kbShiftDel cmCut 1202 \
        end \
        sub '~W~indow' 1100 \
            item '~N~ext' F6 kbF6 cmNext 1101 \
            sub '~L~ayout' 1110 \
                item '~T~ile' '' '' cmTile 1111 \
                item '~C~ascade' '' '' cmCascade 0 \
            end \
        end
}
fvm_box() {
    local -n l=app_views
    local v
    REPLY=''
    for v in "${l[@]}"; do if [ "${__FV_MN_MV[$v]-}" = box ]; then REPLY=$v; fi; done
}
fvm_rows() {
    local y r=''
    for (( y = $1; y < $2; y++ )); do fv.video.getRow "$y"; r+="$RESULT|"; done
    REPLY=$r
}
fvm_nobox() {
    local v
    for v in "${!__FV_MN_MV[@]}"; do if [[ $v == *__fvbox* ]]; then return 1; fi; done
    [[ -z $(compgen -v | grep -F __fvbox) ]]
}
#   fvm_cells X Y1 Y2 W   REPLY = W cells from column X of rows Y1 .. Y2-1,
#                         joined by '|' (narrow text)
fvm_cells() {
    local y r=''
    for (( y = $2; y < $3; y++ )); do fvw_cells "$1" "$y" "$4"; r+="$RESULT|"; done
    REPLY=$r
}
