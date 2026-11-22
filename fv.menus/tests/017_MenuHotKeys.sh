#!/usr/bin/env bash
# 017_MenuHotKeys.sh - the menus' item search by behaviour (P3 §7.2, FV
# TMenuView.HotKey / FindItem; 3f critic F1 / F2 / F4 / F5): HotKey skips a
# Disabled item and finds the next one with that key (the bar's pre-process,
# and TopMenu^.HotKey inside an open box); FindItem skips a Disabled item
# with that hot letter (a plain letter in a box); HotKey's depth-first order
# (a key in File > Recent wins over the same key later in File and in Edit);
# a repeated hot letter: the first item wins; a box made by newSubView over
# a submenu and inserted by hand answers only the keys of its own subtree
# (FV walks the view's Menu); fv.menus.menuBar while a menu runs: refused
# (rc 2, one debug line, nothing changed), accepted after the menu closes.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../fv.app/tests/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "017: hot keys and hot letters by behaviour"

fva_app 80 24 TMyApp
# submenus: 0 the top, 1 File, 2 Recent, 3 Edit. Disabled at the start:
# Alpha (F9, first in the tree) and Close (hot letter c, first in File)
fv.views.disableCommands cmAlpha cmCloseIt
fv.menus.menuBar \
    sub '~F~ile' \
        item '~A~lpha' F9 kbF9 cmAlpha 0 \
        sub '~R~ecent' item '~O~ne' F12 kbF12 cmOne 0 end \
        item '~C~lose' '' '' cmCloseIt 0 \
        item '~C~opy' '' '' cmCopyIt 0 \
        item '~P~rint' '' '' cmPrint 0 \
        item '~P~review' '' '' cmPreview 0 \
        item 'F~i~nd' F12 kbF12 cmFindF 0 \
        item '~S~ave' F2 kbF2 cmSaveIt 0 \
    end \
    sub '~E~dit' \
        item '~B~eta' F9 kbF9 cmBeta 0 \
        item '~U~ndo' F12 kbF12 cmUndoE 0 \
    end
fva_paint
fva_events nothing; app.Run; __FV_VW_EOF=0
B=$FV_MENUBAR
closed() { fvm_nobox && fvw_full app && echo 0; }
cmds() { REPLY=''; local x=$FVA_GOT; while [[ $x == *evCommand:* ]]; do x=${x#*evCommand:}; REPLY+="${x%%;*},"; done; REPLY=${REPLY//cmMenu,/}; }
runq() { FVA_GOT='' __FV_DR_PEND=(); fva_events "$@"; app.Run; __FV_VW_EOF=0; cmds; }
key() {   # VIEW KEY [CHAR]: one key event through VIEW's HandleEvent
    fv.drivers.clearEvent; __FV_DR_PEND=()
    FV_EV_WHAT=evKeyDown FV_EV_KEY=$2 FV_EV_CHAR=${3-}
    fv.views._virt "$1" HandleEvent
}

# F1: the Disabled skip in HotKey and FindItem
key app kbF9
fvw_check "F9 through the bar's pre-process: Alpha (first, Disabled) skipped -> Edit's Beta posted (FV HotKey)" \
    "evNothing|evCommand cmBeta" "$FV_EV_WHAT|${__FV_DR_PEND[0]-} ${__FV_DR_PEND[3]-}"
runq 'key kbF10' 'key kbDown' 'key kbF9'
fvw_check "F9 inside File's open box: TopMenu's HotKey skips Alpha -> cmBeta ends the menu" "cmBeta,|0" "$REPLY|$(closed)"
runq 'key kbAltF f' 'key kbChar c'
fvw_check "two items with hot letter c in File's box, the first (Close) Disabled: c selects Copy (FV FindItem)" "cmCopyIt,|0" "$REPLY|$(closed)"

# F2: the order of the search
key app kbF12
fvw_check "F12 in File > Recent, later in File and in Edit: Recent's One wins (FV HotKey's depth-first order)" \
    "evCommand cmOne" "${__FV_DR_PEND[0]-} ${__FV_DR_PEND[3]-}"
runq 'key kbAltF f' 'key kbChar p'
fvw_check "a repeated hot letter (Print, Preview): p selects the first, Print" "cmPrint,|0" "$REPLY|$(closed)"
runq 'key kbAltF f' 'key kbChar P'
fvw_check "typed upper case: folded, still the first" "cmPrint," "$REPLY"

# F5: a box over Edit (submenu 3) made by newSubView and inserted by hand
fv.menus.newSubView "$B" 0 1 40 20 "$B:3" "$B"
BX=$RESULT
fv.views.insert "$FV_DESKTOP" "$BX"
key "$BX" kbF12
fvw_check "the hand-inserted box over Edit: F12 -> Edit's Undo (its own subtree, not File > Recent)" \
    "evNothing|evCommand cmUndoE" "$FV_EV_WHAT|${__FV_DR_PEND[0]-} ${__FV_DR_PEND[3]-}"
key "$BX" kbF2
fvw_check "F2 (only File's Save has it): not this box's key — nothing posted, the key goes on" \
    "evKeyDown kbF2|" "$FV_EV_WHAT $FV_EV_KEY|${__FV_DR_PEND[3]-}"
key "$BX" kbF9
fvw_check "F9: Edit's Beta (Alpha is not in the subtree)" "cmBeta" "${__FV_DR_PEND[3]-}"
key "$B" kbF2
fvw_check "the bar (submenu 0) still finds File's Save" "cmSaveIt" "${__FV_DR_PEND[3]-}"
fv.views.delete "$FV_DESKTOP" "$BX"; fv.menus._del "$BX"
__FV_DR_PEND=()
fvw_check "the box gone: no box left, == a full repaint" "0" "$(closed)"

# F4: menuBar while a menu runs
RB=''
rb() {
    local rc=0 v0=${app_views[*]}
    RESULT=keep
    VERBOSE_KKLASS=debug fv.menus.menuBar sub '~X~' item 'x' '' '' cmX 0 end 2>"$FVW_TMP/rb.txt" || rc=$?
    RB+="rc=$rc bar=$FV_MENUBAR live=${__FV_VW_LIVE[$B]-} same=$([ "$v0" = "${app_views[*]}" ] && echo 1) res=$RESULT lines=$(wc -l < "$FVW_TMP/rb.txt");"
}
runq 'key kbF10' 'run rb' 'key kbDown' 'run rb' 'key kbEsc'
fvw_check "fv.menus.menuBar while the bar runs and while its box runs: rc 2, one debug line, nothing changed (the bar, the views, RESULT)" \
    "rc=2 bar=$B live=1 same=1 res=keep lines=1;rc=2 bar=$B live=1 same=1 res=keep lines=1;" "$RB"
e=$(<"$FVW_TMP/rb.txt")
kt_test_start "the refusal's debug line names the running menu"
if [[ $e == "Error: fv.menus.menuBar: refused while the menu '"*"' runs: call it after the menu closes" ]]; then kt_test_pass "$e"; else kt_test_fail "[$e]"; fi
fvw_check "after the refused calls: the menu closed as usual, no box left, == a full repaint, nothing marked running" \
    "0|0" "$(closed)|${#__FV_MN_RUN[@]}"
rc=0; fv.menus.menuBar sub '~X~' item x '' '' cmX 0 end || rc=$?
fvw_check "after the menu closed menuBar works again (rc 0, the new bar drawn)" "0|$B| X " "$rc|$FV_MENUBAR|$(fvw_row 0; printf '%s' "${RESULT:0:3}")"

fva_unapp
kt_test_log "017_MenuHotKeys.sh completed"
