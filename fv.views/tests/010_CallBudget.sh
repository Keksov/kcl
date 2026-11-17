#!/usr/bin/env bash
# 010_CallBudget.sh - the call budget (design §3.1, §3.2; P2-10), the
# fv.views part: the actions that need no application, in the design's scene
# built from fv.views' classes (fv.app's 014_CallBudget runs the same actions
# through TMyApp, the real event source and the status line):
#   * the scene: app (TTApp: a TGroup whose HandleEvent, an override, calls
#     inherited and takes cmNext as FV's TDesktop does — the design's TMyApp
#     + desktop) > desk > bg, two TWindows of 40 x 23 side by side, each with
#     a TTestList stand-in (TView's default EventMask; Draw = one writeBuf
#     per visible row; kbDown = two drawParts; kbPgDn = a new page +
#     drawView); the overlap scene puts the second window over half of the
#     first;
#   * every action runs through TGroup's Execute (the modal loop of the
#     root) with the scripted event source: the dispatches counted with the
#     test lib's shim, the fv.video writes in the same run (both logged as
#     "# calls" / "# writes"); limits are the design's §3.2 test limits:
#     Down 6, PgDn 8, Tab side by side 8, Tab overlapping 10, click 8,
#     repaint 6;
#   * row and cell independence: the same actions with a 21-row and a
#     42-row stand-in give the same dispatch counts (and the same writes:
#     one per row only where rows are painted);
#   * the drawing shape (write counter): a full frame draw <= 3 writes, a
#     window's shadow <= 2 shade calls, a border-only frame redraw <= 4
#     writes.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "010: the call budget (fv.views)"

# lscene W H side|overlap — the §3.1 scene: windows 40 wide, H-1 high (the
# stand-in H-3 rows: 21 at 80x24, 42 at 80x45)
lscene() {
    local w=$1 h=$2 wh=$(( $2 - 1 ))
    fvw_screen "$w" "$h"
    fvw_classes3
    TTApp.new app 0 0 "$w" "$h"
    TGroup.new desk 0 0 "$w" "$h"
    TView.new bg 0 0 "$w" "$h"
    fv.views.insert desk bg
    fvw_mklwin w1 0 0 40 "$wh" 'Files' 1
    if [ "$3" = side ]; then fvw_mklwin w2 40 0 80 "$wh" 'Panel two' 2
    else fvw_mklwin w2 20 0 60 "$wh" 'Panel two' 2; fi
    fv.views.insert desk w1
    fv.views.insert desk w2
    fv.views.insert app desk
    fvw_root app
    FVW_DRAWS=()
    fv.views.drawView app
}
# run SPEC... — one Execute of the root over SPEC... (then the end of input:
# the loop ends without a dispatch); the latch reset after
run() {
    fvw_events "$@"
    __FV_VW_EOF=0
    fv.views._virt app Execute
    __FV_VW_EOF=0
    fvw_noevents
}

declare -A CNT=() WRT=()
# act ROWS LABEL LIMIT SPEC... — the budget of one action, kept per height
act() {
    local rows=$1 label=$2 limit=$3
    shift 3
    fvw_budgetw "$label ($rows rows)" "$limit" run "$@"
    CNT[$rows|$label]=$FVW_LASTC WRT[$rows|$label]=$FVW_LASTW
}
# actions ROWS H — every action in both scenes at height H
actions() {
    local r=$1 h=$2 y
    y=$(( h / 2 ))
    lscene 80 "$h" side
    act "$r" "Down" 6 'key kbDown'
    act "$r" "PgDn" 8 'key kbPgDn'
    act "$r" "Tab side by side" 8 'cmd cmNext'
    act "$r" "Tab side by side, back" 8 'cmd cmNext'
    act "$r" "click on the inactive window" 8 "down 10 $y"
    run "up 10 $y"
    act "$r" "repaint" 6 'run fvr'
    app.delete
    lscene 80 "$h" overlap
    act "$r" "Tab overlapping" 10 'cmd cmNext'
    act "$r" "Tab overlapping, back" 10 'cmd cmNext'
    act "$r" "click on the covered window" 8 "down 5 $y"
    run "up 5 $y"
    app.delete
}
fvr() { fv.views.redraw app; }

actions 21 24

kt_test_start "the scene after the actions: == a full repaint (the stand-in's rows, the frames, the shadows)"
lscene 80 24 side
run 'key kbDown' 'key kbDown' 'key kbPgDn' 'cmd cmNext' 'key kbDown'
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "diff [$FVW_DIFF]"; fi
kt_test_start "the stand-in did its work: Focused / Top kept in its fields, the focused row marked in entry 7"
r="${w2l_data[Focused]}|${w2l_data[Top]}|${w1l_data[Focused]}|${app_data[Current]}/${desk_data[Current]}"
fvw_cells 41 3 6
if [[ $r == '2|21|1|desk/w1' && $RESULT == ' item ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] [$RESULT]"; fi
app.delete

actions 42 45

kt_test_start "row and cell independence: a 42-row stand-in costs the dispatches of a 21-row one, action by action"
bad=''
for k in "${!CNT[@]}"; do
    [[ $k == 21\|* ]] || continue
    l=${k#21|}
    [[ ${CNT[42|$l]-x} == "${CNT[$k]}" ]] || bad+=" [$l: ${CNT[$k]} vs ${CNT[42|$l]-none}]"
done
if [[ -z $bad && ${#CNT[@]} == 18 ]]; then kt_test_pass "ok (${#CNT[@]} counts)"; else kt_test_fail "$bad (${#CNT[@]} counts)"; fi
kt_test_start "the writes: one per stand-in row painted, nothing else grows with the rows (42-row minus 21-row = 21 per painted stand-in; Down, Tab side by side, click on the inactive window: equal)"
bad=''
for k in "${!WRT[@]}"; do
    [[ $k == 21\|* ]] || continue
    l=${k#21|}
    d=$(( WRT[42|$l] - WRT[$k] ))
    case $l in
        Down|'Tab side by side'|'click on the inactive window') (( d == 0 )) || bad+=" [$l: ${WRT[$k]} vs ${WRT[42|$l]}]" ;;
        *) (( d > 0 && d % 21 == 0 )) || bad+=" [$l: ${WRT[$k]} vs ${WRT[42|$l]}]" ;;
    esac
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_log "the drawing shape in the §3.1 scene (write counter)"
lscene 80 24 side
FVW_SHADES=0 FRAMEW=''
shade_on() { fvw_wrap FVW_SHADES fv.video.shadeRect fv.video._shadef; }
shade_off() { fvw_unwrap fv.video.shadeRect fv.video._shadef; }
# (the writes made inside TFrame's built-in Draw, one entry per frame draw)
src=$(declare -f fv.views._frameDraw)
eval "__fvb_${src}"
frame_on() { fv.views._frameDraw() { local b=$FVW_WRITES s=0; __fvb_fv.views._frameDraw "$@" || s=$?; FRAMEW+="$(( FVW_WRITES - b )) "; return "$s"; }; }
frame_off() { eval "$src"; }
run "cmd cmNext"
kt_test_start "the front window drawn whole: its frame <= 3 writes, its shadow <= 2 shade calls, one write per stand-in row, one dispatch (the stand-in's Draw)"
frame_on; shade_on; fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0 FVW_SHADES=0 FRAMEW=''
fv.views.drawView w1
a="$FVW_WRITES $FVW_SHADES $FVW_CALLS ${FRAMEW% }"
fvw_writes_off; fvw_count_off; shade_off; frame_off
# (a function wrapped once: the shade calls are counted in FVW_SHADES only)
read -r w s c f <<< "$a"
kt_test_log "# writes full frame $f"
kt_test_log "# writes window $w + $s shade calls"
if [[ $f == [0123] ]] && (( s <= 2 && w == f + 21 && c == 1 )); then kt_test_pass "writes $w, shades $s, dispatches $c, frame $f"; else kt_test_fail "writes / shades / dispatches / frame [$a]"; fi
kt_test_start "a border-only frame redraw (sfDragging on, then off) <= 4 writes each, no dispatch"
fvw_count_on; fvw_writes_on; FVW_CALLS=0 FVW_WRITES=0
fv.views.setState w1 "$FV_SF_DRAGGING" 1
a="$FVW_WRITES $FVW_CALLS"
FVW_CALLS=0 FVW_WRITES=0
fv.views.setState w1 "$FV_SF_DRAGGING" 0
b="$FVW_WRITES $FVW_CALLS"
fvw_writes_off; fvw_count_off
kt_test_log "# writes border-only ${a% *} / ${b% *}"
if (( ${a% *} <= 4 && ${b% *} <= 4 && ${a#* } == 0 && ${b#* } == 0 )) && fvw_full app; then kt_test_pass "in [$a] out [$b]"; else kt_test_fail "in [$a] out [$b] diff [$FVW_DIFF]"; fi
app.delete

kt_test_log "010_CallBudget.sh completed"
