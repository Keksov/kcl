#!/usr/bin/env bash
# fvg_testlib.sh — what the fv.dialogs test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only). It reuses fv.views' test lib
# (fv.views/tests/fvw_testlib.sh: the headless screen, the buffer reader,
# both counters, fvw_budget / fvw_budgetw, the scripted event source
# fvw_events, fvw_root, fvw_full, the scene classes TTApp / TTLeaf and
# fvw_tscene) and adds:
#
#   fvg_init NAME "$@"    ktest init + fv.dialogs (with fv.views) + $FVW_TMP;
#                         the file's stderr is captured as in fvw_init:
#                         anything on it fails one test at exit
#   fvg_events SPEC...    fvw_events with two more specs: 'char C' (kbChar C;
#                         `_` stands for a blank) and 'alt L [BASE]' (kbAlt + the BASE or L
#                         upper-cased, FV_EV_CHAR L, FV_EV_BASE BASE: a
#                         non-Latin L with its base-layout key)
#   fvg_mkdlg [NAME [P]]  the test dialog (not inserted): TDialog NAME
#                         (default dlg; P prefixes the controls' names) 10 4 70 18 'Find' with, in this order,
#                         st (TStaticText 3 1 57 3), l1 ('~T~ext' -> opts),
#                         opts (TCheckBoxes 3 4 30 7: '~C~ase sensitive'
#                         '~W~hole words' 'Re~g~ex'), l2 ('~D~irection' ->
#                         dir), dir (TRadioButtons 32 4 56 6: '~F~orward'
#                         '~B~ackward'), ok ('O~K~' cmOK, bfDefault, 14 10 24
#                         12), cn ('Cancel' cmCancel, 26 10 38 12), hp ('~H~elp'
#                         cmHelp, 40 10 50 12); FVG_CTL = the eight names; opts made
#                         its Current (FV programs select a first control)
#   fvg_scene [W H]       a headless screen and the events scene (fvw_tscene:
#                         app > desk > bg, w1, w2) plus the test dialog, not
#                         inserted yet
#   fvg_modeless          fvg_scene + the dialog inserted into desk and
#                         selected, everything drawn
#   fvg_run SPEC...       the dialog run modally in desk (fv.views.execView)
#                         with the scripted events; FVG_R = the command
#   fvg_unscene           app.delete; dlg.delete when it is still a view
#   fvg_row Y / fvg_cells X Y W: fvw_row / fvw_cells

FVG_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVG_TESTS_DIR/../../fv.views/tests/fvw_testlib.sh"

fvg_init() {
    local name=$1
    shift
    source "$FVG_TESTS_DIR/../fv.dialogs.sh"
    kt_test_init "$name" "$FVG_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

fvg_events() { fvw_events "$@"; __FV_VW_GETEVENT=fvg_getev; }
fvg_getev() {
    local s a b c IFS=' '
    if (( ${#__FV_DR_PEND[@]} )) || (( ! ${#FVW_EVQ[@]} )); then fvw_getev; return; fi
    s=${FVW_EVQ[0]}
    read -r a b c <<< "$s"
    if [ "$a" = char ] || [ "$a" = alt ]; then
        FVW_EVQ=("${FVW_EVQ[@]:1}")
        FVW_EVN=$(( FVW_EVN + 1 ))
        fv.drivers.clearEvent
        if [ "$b" = _ ]; then b=' '; fi
        if [ "$a" = char ]; then FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=$b
        else FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAlt${c:-$b} FV_EV_CHAR=$b FV_EV_BASE=${c-}; FV_EV_KEY=${FV_EV_KEY^^}; FV_EV_KEY=kbAlt${FV_EV_KEY#KBALT}; fi
        RESULT=$FV_EV_WHAT
        return 0
    fi
    fvw_getev
}

fvg_mkdlg() {
    local d=${1:-dlg} p=${2-}
    TDialog.new "$d" 10 4 70 18 'Find'
    TStaticText.new "${p}st" 3 1 57 3 $'\x03''Search options'
    TLabel.new "${p}l1" 2 3 14 4 '~T~ext' "${p}opts"
    TCheckBoxes.new "${p}opts" 3 4 30 7 '~C~ase sensitive' '~W~hole words' 'Re~g~ex'
    TLabel.new "${p}l2" 32 3 46 4 '~D~irection' "${p}dir"
    TRadioButtons.new "${p}dir" 32 4 56 6 '~F~orward' '~B~ackward'
    TButton.new "${p}ok" 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new "${p}cn" 26 10 38 12 'Cancel' cmCancel
    TButton.new "${p}hp" 40 10 50 12 '~H~elp' cmHelp
    FVG_CTL=("${p}st" "${p}l1" "${p}opts" "${p}l2" "${p}dir" "${p}ok" "${p}cn" "${p}hp")
    local v
    for v in "${FVG_CTL[@]}"; do fv.views.insert "$d" "$v"; done
    fv.views.select "${p}opts"
}
fvg_scene() {
    fvw_tscene "${1:-80}" "${2:-24}"
    fvg_mkdlg
}
fvg_modeless() {
    fvg_scene "$@"
    fv.views.insert desk dlg
    fv.views.select dlg
    fv.views.drawView app
}
fvg_run() {
    fvg_events "$@"
    fv.views.execView desk dlg
    FVG_R=$RESULT
    fvw_noevents
}
fvg_unscene() {
    app.delete
    if fv.views.isView dlg; then dlg.delete; fi
}
fvg_row() { fvw_row "$@"; }
fvg_cells() { fvw_cells "$@"; }
