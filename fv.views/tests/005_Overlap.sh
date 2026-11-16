#!/usr/bin/env bash
# 005_Overlap.sh - the painter (design §1.7, §1.10): back to front with the
# overlap test, the covering skip, shadows, and the redraws of the hook:
#   * painter's order in the desktop-like scene (two framed windows with
#     shadows over a background), FV's look of the cells;
#   * the covering skip: a view entirely behind a framed group or a leaf is
#     not drawn; behind a frameless group, a group whose frame is hidden, or
#     only a shadow it is (shadows never cover);
#   * shadows: 2 x 1, attribute only (the characters below kept), over a
#     sibling, clipped by the owner;
#   * move, resize, a group resize, makeFirst / putInFrontOf, delete,
#     insert, hide / show: each leaves exactly the screen a full repaint of
#     the same tree gives (shadow cells included), and draws each user view
#     at most once (a group resize does not redraw per subview; a reorder
#     without overlap draws nothing);
#   * review round: a frameless group's subview hidden / shown / moved /
#     deleted; wide characters at a repaint edge; randomized wide-character
#     scenes (seeded): every redraw equals a full repaint.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "005: painter, covering, shadows, redraws"

# snap -> REPLY: every row's text and symbols
snap() {
    local y s=''
    for (( y = 0; y < FV_SCREEN_H; y++ )); do fv.video.getRow "$y"; s+="$RESULT|$REPLY"$'\n'; done
    REPLY=$s
}
# same_as_full TITLE -> one test: the screen equals a full repaint of desk
same_as_full() {
    local a b
    snap; a=$REPLY
    fv.video.clearScreen
    fv.views.drawView desk
    snap; b=$REPLY
    kt_test_start "$1: the screen equals a full repaint"
    if [[ $a == "$b" ]]; then kt_test_pass "ok"
    else
        local -a x y
        mapfile -t x <<< "$a"; mapfile -t y <<< "$b"
        local i d=''
        for i in "${!x[@]}"; do [[ ${x[i]} == "${y[i]-}" ]] || d+=" row $i: [${x[i]}] vs full [${y[i]-}]"; done
        kt_test_fail "$d"
    fi
}
draws() {   # NAME... -> REPLY = "n n ..." of FVW_DRAWS
    local n r=''
    for n; do r+="${FVW_DRAWS[$n]:-0} "; done
    REPLY=${r% }
}

fvw_scene
fvw_count_on; FVW_CALLS=0
fv.views.drawView desk
first_calls=$FVW_CALLS
fvw_count_off

kt_test_start "painter's order: w1 behind w2 (w2's left border over w1's list), FV frames and colours"
fvw_cells 0 1 40; a="$RESULT|$REPLY"
fvw_cells 28 6 6; b="$RESULT|$REPLY"
fvw_cells 30 5 40; c=$RESULT
want_a="  ┌────────────── Files ─────────1─────┐|11$(printf '8%.0s' {1..38})"
want_c='╔═[■]═════════ Panel two ════════2═[↑]═╗'
if [[ $a == "$want_a" && $b == '  ║row|889888' && $c == "$want_c" ]]; then kt_test_pass "ok"
else kt_test_fail "row1 [$a] row6 [$b] w2 top [$c]"; fi

kt_test_start "the first paint: 4 dispatches (2 list Draws, 2 TTWin palette resolutions), each list drawn once"
draws w1l w2l; dr=$REPLY
if [[ $first_calls == 4 && $REPLY == '1 1' ]]; then kt_test_pass "ok"; else kt_test_fail "calls=$first_calls draws=[$REPLY]"; fi

kt_test_start "shadows: 2 columns right from the 2nd row, 1 row below from the 3rd column, symbol V, characters kept"
fvw_cells 40 1 2; a=$REPLY
fvw_cells 40 2 2; b="$RESULT|$REPLY"
fvw_cells 2 20 4; c=$REPLY
fvw_cells 70 22 3; d=$REPLY
fvw_cells 30 22 3; e=$REPLY
if [[ $a == 11 && $b == '  |VV' && $c == 11VV && $d == VV1 && $e == 11V ]]; then kt_test_pass "ok"
else kt_test_fail "[$a] [$b] [$c] [$d] [$e]"; fi

same_as_full "first paint"

kt_test_start "a shadow over a sibling: a small shadowed window in front of w1 darkens w1's cells (characters kept)"
fvw_cells 15 4 2; before=$RESULT
fvw_mkwin w3 5 3 15 8 'w3' 0
fv.views.insert desk w3
fvw_cells 15 4 2; a="$RESULT|$REPLY"
fvw_cells 6 8 11; b=$REPLY
if [[ $a == "$before|VV" && $b == 8VVVVVVVVVV ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] (chars before [$before]) [$b]"; fi
same_as_full "after inserting w3"
w3.delete
same_as_full "after w3.delete"

kt_test_start "a shadow is clipped by its owner: a shadowed leaf near a frameless group's right edge"
TGroup.new gc 72 0 78 4
TView.new lf 2 1 6 3
lf_data[State]=$(( lf_data[State] | FV_SF_SHADOW ))
fv.views.insert gc lf
fv.views.insert desk gc
fvw_cells 76 3 4; a=$REPLY
fvw_cells 78 2 2; b=$REPLY
if [[ $a == VV11 && $b == 11 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
gc.delete
same_as_full "after gc.delete"

kt_test_start "a move (moveTo w2): one redraw of S(A) ∪ S(B), each list drawn once, 2 dispatches"
FVW_DRAWS=()
fvw_count_on; FVW_CALLS=0
fv.views.moveTo w2 35 3
n=$FVW_CALLS
fvw_count_off
draws w1l w2l; dr=$REPLY
fvw_cells 30 21 1; a="$RESULT|$REPLY"
fvw_cells 32 22 1; b=$REPLY
fvw_cells 75 4 2; c=$REPLY
if [[ $n == 2 && $dr == '1 1' && $a == ' |1' && $b == 1 && $c == VV ]]; then kt_test_pass "ok"
else kt_test_fail "calls=$n draws=[$dr] old [$a] old shadow [$b] new shadow [$c]"; fi
same_as_full "after the move"

kt_test_start "a resize (growTo w1 50 18, a group resize): each subview drawn once (no redraw per subview)"
FVW_DRAWS=()
fv.views.growTo w1 50 18
draws w1l w2l; dr=$REPLY
fv.views.getBounds w1__fvframe; g=$RESULT
if [[ $dr == '1 1' && $g == '0 0 50 18' ]]; then kt_test_pass "ok"; else kt_test_fail "draws=[$dr] frame=[$g]"; fi
same_as_full "after the resize"
fv.views.growTo w1 38 19

kt_test_start "makeFirst w1 (behind w2, overlapping): w1 redrawn whole, w2 untouched"
FVW_DRAWS=()
fv.views.makeFirst w1
draws w1l w2l; dr=$REPLY
if [[ $REPLY == '1 0' ]]; then kt_test_pass "ok"; else kt_test_fail "draws=[$REPLY]"; fi
same_as_full "after makeFirst"

kt_test_start "putInFrontOf w1 bg (behind w2 again): only the views now in front of it over S(w1)"
FVW_DRAWS=()
fv.views.putInFrontOf w1 bg
draws w1l w2l; dr=$REPLY
if [[ $REPLY == '0 1' ]]; then kt_test_pass "ok"; else kt_test_fail "draws=[$REPLY]"; fi
same_as_full "after putInFrontOf"

kt_test_start "a reorder without overlap draws nothing"
fv.views.moveTo w2 45 3
fv.views.moveTo w1 0 1
FVW_DRAWS=()
fv.views.makeFirst w1; fv.views.makeFirst w2
draws w1l w2l; dr=$REPLY
if [[ $REPLY == '0 0' ]]; then kt_test_pass "ok"; else kt_test_fail "draws=[$REPLY]"; fi
same_as_full "after the reorders"
fv.views.moveTo w2 30 5

kt_test_start "delete w2 from desk: its area (and shadow) repainted from below; insert again: drawn"
fv.views.delete desk w2
fvw_cells 70 22 2; a=$REPLY
fvw_cells 50 10 1; b="$RESULT|$REPLY"
if [[ $a == 11 && $b == ' |1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
same_as_full "after delete"
fv.views.insert desk w2
same_as_full "after insert"

kt_test_start "hide w2 / show w2: hidden, its area repainted; shown again with its shadow"
fv.views.hide w2
fvw_cells 50 10 1; a="$RESULT|$REPLY"
fv.views.show w2
fvw_cells 70 22 2; b=$REPLY
if [[ $a == ' |1' && $b == VV ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
same_as_full "after hide / show"
fvw_unscene

# the covering skip on its own
kt_test_start "the covering skip: behind a framed group or a leaf: not drawn; behind a frameless group, a hidden frame, a shadow: drawn"
fvw_classes
fvw_screen 80 6
TGroup.new desk 0 0 80 6
FVW_DRAWS=()
TTList.new L1 0 0 5 3; fvw_mkwin F1 0 0 10 5 'f' 0
TTList.new L2 20 0 25 3; TGroup.new G2 20 0 30 5
TTList.new L3 40 0 45 3; TView.new V3 40 0 50 5
TTList.new L4 60 0 65 3; fvw_mkwin F4 60 0 70 5 'f' 0
F4__fvframe_data[State]=0
TTList.new L5 70 1 72 2; TView.new S5 67 0 70 1
S5_data[State]=$(( S5_data[State] | FV_SF_SHADOW ))
for v in L1 F1 L2 G2 L3 V3 L4 F4 L5 S5; do fv.views.insert desk "$v"; done
fvw_expose desk
FVW_DRAWS=()
fv.views.drawView desk
draws L1 L2 L3 L4 L5; dr=$REPLY
fvw_cells 70 1 2; s=$REPLY
if [[ $dr == '0 1 0 1 1' && $s == VV ]]; then kt_test_pass "ok"; else kt_test_fail "draws=[$dr] shadow=[$s]"; fi
same_as_full "the covering scene"
desk.delete

# --- review round: frameless groups, wide characters at repaint edges ---
kt_test_start "a frameless group (not the root): hide / show / move / delete of its subview repaint the views behind the group"
fvw_screen 30 8
TGroup.new desk 0 0 30 8; TView.new bg 0 0 30 8; fv.views.insert desk bg
TGroup.new fg 2 1 20 7; TTList.new lf 1 1 12 4; fv.views.insert fg lf; fv.views.insert desk fg
fvw_expose desk; fv.views.drawView desk
bad=''
for op in "hide lf" "show lf" "moveTo lf 30 0" "moveTo lf 1 1" "delete fg lf"; do
    fv.views.${op%% *} ${op#* }
    fvw_full desk || bad+=" [$op]$FVW_DIFF"
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi
desk.delete; lf.delete

# a leaf that covers its rect with wide characters; ODD shifts the rows by one
# cell on odd rows (so wide characters straddle every column somewhere)
class TCJK : TView
    public
        override proc Draw
end
TCJK.Draw() {
    local y s
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        s='漢字かな漢字かな漢字かな漢字かな漢字かな漢字かな'
        if (( y % 2 )); then s="a$s"; fi
        fv.views.writeStr 0 "$y" "$s" 1
    done
}
build TCJK

kt_test_start "wide characters cut by the edge of a repaint rectangle: a view moved over and off wide text leaves what a full repaint gives"
fvw_screen 30 4
TGroup.new desk 0 0 30 4; TView.new bg 0 0 30 4; fv.views.insert desk bg
TCJK.new a 0 0 20 4; fv.views.insert desk a
TView.new b 5 1 12 3; fv.views.insert desk b
fvw_expose desk; fv.views.drawView desk
fv.views.moveTo b 20 1
fvw_full desk; f1=$?; d1=$FVW_DIFF
fv.views.moveTo b 6 1
fvw_full desk; f2=$?; d2=$FVW_DIFF
if [[ $f1 == 0 && $f2 == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "$d1 / $d2"; fi
desk.delete

# randomized: windows with wide text, a frameless group with a wide leaf, odd
# offsets; after every operation the screen must equal a full repaint
wide_run() {   # SEED STEPS -> WIDE_FAIL = '' or the first failing step
    local seed=$1 steps=$2 step v op x y t desc
    local -a kids=(ww1 ww2 ww3 wfg wlf wn)
    RANDOM=$seed
    fvw_screen 60 20
    TGroup.new wdesk 0 0 60 20; TView.new wbg 0 0 60 20; fv.views.insert wdesk wbg
    for t in 'ww1 2 1 31 14' 'ww2 19 4 50 18' 'ww3 45 9 71 25'; do
        read -r v x y a b <<< "$t"
        TTWin.new "$v" "$x" "$y" "$a" "$b"
        local -n wd=${v}_data
        wd[Flags]=15 wd[Title]="窓 $v" wd[Number]=1 wd[State]=$(( wd[State] | FV_SF_SHADOW ))
        unset -n wd
        fv.views._newReserved "$v" frame TFrame 0 0 $(( a - x )) $(( b - y ))
        fv.views.insert "$v" "$RESULT"
        TCJK.new "${v}c" 1 1 $(( a - x - 1 )) $(( b - y - 1 ))
        fv.views.insert "$v" "${v}c"
        fv.views.insert wdesk "$v"
    done
    TGroup.new wfg 9 12 26 19; TCJK.new wlf 1 1 9 5; fv.views.insert wfg wlf; fv.views.insert wdesk wfg
    TCJK.new wn 3 3 16 9; fv.views.insert ww1 wn
    fvw_expose wdesk; fv.views.drawView wdesk
    WIDE_FAIL=''
    fvw_full wdesk || { WIDE_FAIL="initial:$FVW_DIFF"; wdesk.delete; return; }
    for (( step = 0; step < steps; step++ )); do
        v=${kids[RANDOM % ${#kids[@]}]} op=$(( RANDOM % 6 ))
        case $op in
            0) x=$(( RANDOM % 66 - 6 )) y=$(( RANDOM % 22 - 2 )); desc="moveTo $v $x $y"; fv.views.moveTo "$v" "$x" "$y" ;;
            1) x=$(( RANDOM % 30 + 1 )) y=$(( RANDOM % 15 + 1 )); desc="growTo $v $x $y"; fv.views.growTo "$v" "$x" "$y" ;;
            2) desc="makeFirst $v"; fv.views.makeFirst "$v" ;;
            3) desc="putInFrontOf $v ''"; fv.views.putInFrontOf "$v" '' ;;
            4) desc="hide $v"; fv.views.hide "$v" ;;
            5) desc="show $v"; fv.views.show "$v" ;;
        esac
        if ! fvw_full wdesk; then WIDE_FAIL="seed $seed step $step ($desc):$FVW_DIFF"; break; fi
    done
    wdesk.delete
}
kt_test_start "randomized wide-character scenes (seeded, 2 x 30 operations): every incremental redraw equals a full repaint"
fvw_classes
wide_run 7 30; r1=$WIDE_FAIL
wide_run 2026 30; r2=$WIDE_FAIL
if [[ -z $r1$r2 ]]; then kt_test_pass "ok"; else kt_test_fail "${r1:0:1500} ${r2:0:1500}"; fi

kt_test_log "005_Overlap.sh completed"
