#!/usr/bin/env bash
# 014_CallBudget.sh - the call budget through the application (design §3.1,
# §3.2; P2-10; fv.views' 010_CallBudget has the parts without an
# application):
#   * the design's scene: TMyApp (a TApplication whose HandleEvent, an
#     override, calls inherited), its desktop, two TWindows of 40 x 23 side by
#     side, each with a TTestList stand-in (TView's default EventMask; Draw =
#     one writeLines call for its visible rows, D21 stage E: the "# writes"
#     logs count one write per painted stand-in, before stage E one per row;
#     kbDown = two drawParts; kbPgDn = a new page + drawView), the status
#     line; the overlap scene puts the second
#     window over half of the first;
#   * every action but the repaint runs through app.Run with the scripted
#     terminal (the real TProgram.GetEvent: the status line's keys, the
#     immediate cmResizeApp, Idle; the end of input ends Run with no
#     dispatch); the count of a Run with no event (app.Run itself) is taken
#     off. Limits are §3.2's: Down 6, PgDn 8, Tab (F6 -> the status line ->
#     cmNext) side by side 8, overlapping 10, click 8, repaint 6, resize
#     80x24 -> 200x50 8, idle tick 1; the first paint is logged under the
#     repaint's limit;
#   * row and cell independence: a 21-row and a 42-row stand-in (80x24 and
#     80x45) give the same dispatch counts, action by action;
#   * the status line draws with 1 write.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

kt_test_section "014: the call budget (fv.app)"

# lapp W H side|overlap — the §3.1 application: windows 40 wide filling the
# desktop's height (the stand-in H-3 rows); not drawn yet (Run draws)
lapp() {
    local w=$1 h=$2 wh=$(( $2 - 1 ))
    fva_classes
    fvw_classes3
    FV_SCREEN_W=$w FV_SCREEN_H=$h FV_APP_HEADLESS=1
    if [[ -n ${FVW_OUTFD-} ]]; then exec {FVW_OUTFD}>&-; fi
    exec {FVW_OUTFD}>"$FVW_TMP/screen.out"
    FV_VIDEO_OUT_FD=$FVW_OUTFD
    TMyApp.new app
    fvw_mklwin w1 0 0 40 "$wh" 'Files' 1
    if [ "$3" = side ]; then fvw_mklwin w2 40 0 80 "$wh" 'Panel two' 2
    else fvw_mklwin w2 20 0 60 "$wh" 'Panel two' 2; fi
    # (the stand-ins follow their windows on a resize, as FV's lists do)
    w1l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY )) w2l_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    fv.views.insert "$FV_DESKTOP" w1
    fv.views.insert "$FV_DESKTOP" w2
    FVW_DRAWS=() FVA_GOT=''
}
# arun SPEC... — app.Run over the scripted terminal (then the end of input);
# the latch reset after
arun() {
    fva_events "$@"
    __FV_VW_EOF=0
    app.Run
    __FV_VW_EOF=0
}
declare -A CNT=() WRT=()
BASEC=0
# act ROWS LABEL LIMIT SPEC... — the budget of one action through Run: the
# dispatches and writes of the Run minus a Run with no event (BASEC)
act() {
    local rows=$1 label=$2 limit=$3 c w
    shift 3
    kt_test_start "budget $label ($rows rows): at most $limit dispatches"
    fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
    arun "$@"
    c=$(( FVW_CALLS - BASEC )) w=$FVW_WRITES
    fvw_writes_off; fvw_count_off
    CNT[$rows|$label]=$c WRT[$rows|$label]=$w
    kt_test_log "# calls $label ($rows rows) $c"
    kt_test_log "# writes $label ($rows rows) $w"
    if (( c <= limit )); then kt_test_pass "$c dispatches, $w writes"; else kt_test_fail "$c dispatches > $limit ($w writes)"; fi
}
fvr() { fv.views.redraw app; }
# actions ROWS H — every action in both scenes at height H. A window switch
# changes the command set (TWindow's commands disabled and enabled again):
# the next idle tick broadcasts cmCommandSetChanged (TMyApp's override +
# inherited: 2 dispatches, FV's Idle); an idle tick follows each switch
# before the next action, and the first one is logged
actions() {
    local r=$1 h=$2 y
    y=$(( h / 2 ))
    lapp 80 "$h" side
    act "$r" "first paint (Run)" 6
    arun nothing   # (the first tick under TMyApp: the initial cmCommandSetChanged)
    act "$r" "idle tick" 1 nothing
    act "$r" "Down" 6 'key kbDown'
    act "$r" "PgDn" 8 'key kbPgDn'
    act "$r" "Tab side by side (F6)" 8 'key kbF6'
    act "$r" "idle tick after a window switch (cmCommandSetChanged; logged, not a §3.2 action)" 2 nothing
    act "$r" "Tab side by side, back" 8 'key kbF6'
    arun nothing
    act "$r" "click on the inactive window" 8 "down 10 $y"
    arun "up 10 $y" nothing
    fvw_budgetw "repaint ($r rows)" 6 fvr
    CNT[$r|repaint]=$FVW_LASTC WRT[$r|repaint]=$FVW_LASTW
    act "$r" "resize to 200x50" 8 'resize 200 50'
    act "$r" "resize back" 8 "resize 80 $h"
    fva_unapp
    lapp 80 "$h" overlap
    arun nothing
    act "$r" "Tab overlapping (F6)" 10 'key kbF6'
    arun nothing
    act "$r" "Tab overlapping, back" 10 'key kbF6'
    arun nothing
    act "$r" "click on the covered window" 8 "down 5 $y"
    arun "up 5 $y" nothing
    fva_unapp
}

# (a Run with no event costs app.Run's own dispatch: taken off every count)
lapp 80 24 side
arun
fvw_count_on; FVW_CALLS=0; arun; BASEC=$FVW_CALLS; fvw_count_off
kt_test_log "# calls a Run with no event (taken off) $BASEC"
fva_unapp

actions 21 24

kt_test_start "the scene after the actions through Run: == a full repaint; the stand-ins and the focus as the keys left them"
lapp 80 24 side
arun 'key kbDown' 'key kbDown' 'key kbPgDn' 'key kbF6' 'key kbDown'
r="${w2l_data[Focused]}|${w2l_data[Top]}|${w1l_data[Focused]}|${app__fvdesktop_data[Current]}"
if [[ $r == '2|21|1|w1' ]] && fvw_full app; then kt_test_pass "ok"; else kt_test_fail "[$r] diff [$FVW_DIFF]"; fi
kt_test_start "the status line draws with one write, no dispatch"
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views.drawView app__fvstatus
a="$FVW_WRITES $FVW_CALLS"
fvw_writes_off; fvw_count_off
kt_test_log "# writes status line ${a% *}"
if [[ $a == '1 0' ]]; then kt_test_pass "ok"; else kt_test_fail "writes / dispatches [$a]"; fi
fva_unapp

actions 42 45

kt_test_start "row and cell independence: a 42-row stand-in costs the dispatches of a 21-row one, action by action"
bad=''
for k in "${!CNT[@]}"; do
    [[ $k == 21\|* ]] || continue
    l=${k#21|}
    [[ ${CNT[42|$l]-x} == "${CNT[$k]}" ]] || bad+=" [$l: ${CNT[$k]} vs ${CNT[42|$l]-none}]"
done
if [[ -z $bad && ${#CNT[@]} == 28 ]]; then kt_test_pass "ok (${#CNT[@]} counts)"; else kt_test_fail "$bad (${#CNT[@]} counts)"; fi

kt_test_log "014_CallBudget.sh completed"
