#!/usr/bin/env bash
# fvdlg_testlib.sh — what the fv.dlg test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only). It reuses fv.app's test lib (and so
# fv.menus' and fv.views': the headless screen, both counters, fvw_budgetw,
# fvw_forks, the scripted terminal fva_events) and adds:
#
#   fvdl_init NAME "$@"   ktest init + fv.dlg (with fv.app, fv.dialogs) +
#                         $FVW_TMP; the file's stderr is captured as in
#                         fvw_init: anything on it fails one test at exit
#   fvdl_parse ARG...     fv.dlg's parser on ARG (its record in locals):
#                         REPLY = "rc|widget|p0|p1|...|key=value;..." (the
#                         keys sorted; rc 1: "1|the error line"; a command
#                         flag: "0|m:--help")
#   fvdl_run SPEC... -- ARG...
#                         fv.dlg.run --fv-headless ARG... with the scripted
#                         events SPEC (fva_events' specs plus 'char C', '_'
#                         a blank, and 'snap' = fvdl_snap): FVDL_RC,
#                         FVDL_RES (RESULT), FVDL_CMD (FV_DLG_CMD); the
#                         scripted source taken off again
#   fvdl_snap             FVDL_SNAP = the screen's rows as text, FVDL_SNAPA their
#                         palette symbols, '|' after
#                         each (taken while the dialog runs)
#   fvdl_row Y            REPLY = row Y of the last snap
#   fvdl_find TEXT        REPLY = "X Y" of TEXT's first cell in the last snap
#                         ('' when absent; cells = characters: narrow text)
#   fvdl_box              REPLY = the dialog's bounds in the last snap
#                         ("AX AY BX BY" of the ╔ / ╝ corners, B exclusive)
#   fvdl_live             REPLY = the live views whose name holds __fvdlg /
#                         __fvdlgapp (none after every call)

FVDL_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVDL_TESTS_DIR/../../fv.app/tests/fva_testlib.sh"

fvdl_init() {
    local name=$1
    shift
    source "$FVDL_TESTS_DIR/../fv.dlg.sh"
    kt_test_init "$name" "$FVDL_TESTS_DIR" "$@"
    FVW_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
    FVW_ERR=$FVW_TMP/stderr.txt
    exec {FVW_ERRFD}>&2 2>"$FVW_ERR"
    local t
    t=$(trap -p EXIT)
    eval "set -- $t"
    trap "fvw_errcheck; ${3-}" EXIT
}

fvdl_parse() {
    local __fvl_w='' __fvl_err='' __fvl_m='' k s
    local -a __fvl_p=()
    local -A __fvl_o=()
    if ! fv.dlg._parse "$@"; then REPLY="1|$__fvl_err"; return 0; fi
    if [[ -n $__fvl_m ]]; then REPLY="0|m:$__fvl_m"; return 0; fi
    s="0|$__fvl_w"
    for k in "${__fvl_p[@]}"; do s+="|$k"; done
    s+='||'
    local -a keys=("${!__fvl_o[@]}")
    local IFS=$'\n'
    keys=($(LC_ALL=C sort <<< "${keys[*]}"))
    for k in "${keys[@]}"; do [[ -n $k ]] && s+="$k=${__fvl_o[$k]};"; done
    REPLY=$s
}

# the scripted source: fva_src plus 'char C' (kbChar C, '_' a blank) and
# 'snap'
fvdl_src() {
    local s a b
    if (( ${#__FV_DR_PEND[@]} )) || (( ! ${#FVA_Q[@]} )); then fva_src "$@"; return; fi
    s=${FVA_Q[0]}
    a=${s%% *} b=${s#* }
    if [ "$a" = snap ] || [ "$a" = run ]; then
        FVA_Q=("${FVA_Q[@]:1}")
        if [ "$a" = snap ]; then fvdl_snap; else "$b"; fi
        fvdl_src "$@"
        return
    fi
    if [ "$a" = char ]; then
        FVA_Q=("${FVA_Q[@]:1}")
        FVA_N=$(( FVA_N + 1 ))
        fv.drivers.clearEvent
        if [ "$b" = _ ]; then b=' '; fi
        FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=$b
        RESULT=$FV_EV_WHAT
        return 0
    fi
    fva_src "$@"
}
fvdl_events() {
    fva_events "$@"
    fv.drivers.getEvent() { fvdl_src "$@"; }
}

FVDL_RC='' FVDL_RES='' FVDL_CMD='' FVDL_SNAP=''
fvdl_run() {
    local -a specs=()
    while (( $# )) && [ "$1" != -- ]; do specs+=("$1"); shift; done
    shift
    FVDL_SNAP=''
    fvdl_events "${specs[@]}"
    fv.dlg.run --fv-headless "$@"
    FVDL_RC=$? FVDL_RES=$RESULT FVDL_CMD=$FV_DLG_CMD
    fva_noevents
    __FV_VW_EOF=0
    return 0
}

fvdl_snap() {
    local y s='' a=''
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; s+="$RESULT|" a+="$REPLY|"; done
    FVDL_SNAP=$s FVDL_SNAPA=$a
}
fvdl_row() {
    local IFS='|'
    local -a r
    read -r -a r <<< "$FVDL_SNAP"
    REPLY=${r[$1]-}
}
fvdl_find() {
    local IFS='|' y
    local -a r
    read -r -a r <<< "$FVDL_SNAP"
    for (( y = 0; y < ${#r[@]}; y++ )); do
        if [[ ${r[y]} == *"$1"* ]]; then
            local pre=${r[y]%%"$1"*}
            REPLY="${#pre} $y"
            return 0
        fi
    done
    REPLY=''
}
fvdl_box() {
    local IFS='|' y ax='' ay='' bx='' by=''
    local -a r
    read -r -a r <<< "$FVDL_SNAP"
    for (( y = 0; y < ${#r[@]}; y++ )); do
        if [[ -z $ay && ${r[y]} == *'╔'* ]]; then local pre=${r[y]%%'╔'*}; ax=${#pre} ay=$y; fi
        if [[ -n $ay && ${r[y]} == *'╝'* ]]; then local pre2=${r[y]%%'╝'*}; bx=$(( ${#pre2} + 1 )) by=$(( y + 1 )); fi
    done
    REPLY="$ax $ay $bx $by"
}
fvdl_live() {
    local v s=''
    for v in "${!__FV_VW_LIVE[@]}"; do [[ $v == *__fvdlg* ]] && s+="$v "; done
    REPLY=$s
}
