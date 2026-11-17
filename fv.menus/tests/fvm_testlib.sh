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
