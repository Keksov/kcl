#!/usr/bin/env bash
# 026_WideEdge.sh - the wide-row edge test (P3 design 10.5, stage 3a-2):
# a repaint of a rectangle on a row with wide cells repaints that row across
# the screen only when a wide pair straddles the rectangle's left or right
# edge (or two rectangles on the row meet); after a view left cells it
# covered (drawUnder, overOnly) a side whose edge has a space beside it is
# widened by one cell first (the half the view had blanked):
#   * the rule itself on fv.views._bands: rectangles kept, banded, widened;
#     two rectangles that meet; a row without wide cells; the fallbacks (a
#     caller in the C locale, a paint nested in a Draw) band as before;
#   * a static scene of CJK rows under shadowed windows: a repaint of every
#     rectangle with its left edge at every column (widths 1, 2, 3, 5 and
#     to the right edge, all rows) leaves the screen of a full repaint, cell
#     for cell;
#   * a shadowed window and a plain leaf moved across the CJK rows one
#     column at a time (every edge position, rows of every offset): every
#     move == a full repaint;
#   * drawPart of each row of a CJK leaf with a window in front at every
#     column, and the frame border of a window over CJK rows at every
#     column: == a full repaint;
#   * the narrowing: a drawPart on a CJK row that no pair straddles does not
#     repaint a window in front elsewhere on that row (before 3a-2 it did);
#   * randomized seeded scenes (windows with CJK leaves and titles, shadows,
#     a frameless group; moves, resizes, reorders, hide / show, drawView,
#     drawPart, frame borders): every step == a full repaint;
#   * fv.video's VT model: what the terminal shows equals the buffer after a
#     sequence of moves over CJK rows.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
source "$FVW_TESTS_DIR/../../fv.video/tests/fvv_vt.sh"
fvw_init "$(basename "$0" .sh)" "$@"
FVV_TMP=$FVW_TMP

kt_test_section "026: the wide-row edge test (P3 10.5)"
unset FV_ASCII

# ---- the scene's leaf: rows of CJK text shifted by 0-4 ASCII cells ----------
WE_S='漢字かなx漢字かなyz漢字かな漢字かなq漢字かな漢字かな漢字かな漢字かな漢字かな漢字かな'
WE_P='abcde'
declare -A WE_DRAWS=()
we_row() {   # SEED Y -> REPLY = that row's text
    local k=$(( ($1 * 7 + $2 * 3) % 5 ))
    REPLY="${WE_P:0:k}$WE_S"
}
we_paint() {   # V: the rows FV_CLIP_Y1 .. FV_CLIP_Y2-1 (Draw and drawPart painter)
    local -n __we_d=${1}_data
    local y
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        we_row "${__we_d[Seed]:-0}" "$y"
        fv.views.writeStr 0 "$y" "$REPLY" 1
    done
}
class TWE : TView
    public
        var Seed
        override proc Draw
end
TWE.Draw() {
    WE_DRAWS[$this]=$(( ${WE_DRAWS[$this]:-0} + 1 ))
    we_paint "$this"
}
build TWE
we_leaf() {   # NAME AX AY BX BY SEED [GROUP]
    TWE.new "$1" "$2" "$3" "$4" "$5"
    local -n __we_d=${1}_data
    __we_d[Seed]=$6
    if [[ -n ${7-} ]]; then fv.views.insert "$7" "$1"; fi
}
we_win() {   # NAME AX AY BX BY TITLE SEED: a TWindow (frame, shadow; at least 16 x 6, FV's
             # MinWinSize) with a CJK leaf NAMEl over its interior that follows its size
             # (a frame's border-only redraw leaves an uncovered interior in the old colour:
             # a documented deviation, not what this file tests)
    TWindow.new "$1" "$2" "$3" "$4" "$5" "$6" 0
    we_leaf "${1}l" 1 1 $(( $4 - $2 - 1 )) $(( $5 - $3 - 1 )) "$7" "$1"
    local -n __we_l=${1}l_data
    __we_l[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
}
# diff A B -> REPLY = the rows that differ
we_diff() {
    local -a x y
    local i d=''
    mapfile -t x <<< "$1"; mapfile -t y <<< "$2"
    for i in "${!x[@]}"; do [[ ${x[i]} == "${y[i]-}" ]] || d+=" row $i: [${x[i]}] vs [${y[i]-}]"; done
    REPLY=$d
}

# ---- the rule on fv.views._bands ---------------------------------------------
kt_test_start "the rule: no pair at an edge keeps the rectangle; a continuation at X1 or X2 bands the row; two rectangles that meet band it; rows without wide cells stay"
fvw_screen 20 3
fv.video.writeStr 0 0 '漢字かな' 1          # pairs at 0-1 2-3 4-5 6-7
fv.video.writeStr 0 1 'plain row' 1
__FV_VW_WROW=() __FV_VW_WROW[0]=1
bands() {   # [WIDEN] RECTS... -> REPLY = the rectangles after _bands, BANDED
    local w=$1
    shift
    local -a __fvw_rs=("$@")
    if [[ -n $w ]]; then fv.views._bands "$w"; else fv.views._bands; fi
    REPLY="${__fvw_rs[*]} / $__FV_VW_BANDED"
}
r=''
bands '' 2 0 6 1; r+="[$REPLY]"
bands '' 3 0 6 1; r+="[$REPLY]"
bands '' 2 0 5 1; r+="[$REPLY]"
bands '' 0 0 2 1 2 0 4 1; r+="[$REPLY]"
bands '' 0 0 2 1 4 0 6 1; r+="[$REPLY]"
bands '' 3 1 5 2; r+="[$REPLY]"
bands '' 3 0 6 2; r+="[$REPLY]"
want='[2 0 6 1 / 0][0 0 20 1 / 1][0 0 20 1 / 1][0 0 20 1 / 1][0 0 2 1 4 0 6 1 / 0][3 1 5 2 / 0][0 0 20 1 3 1 6 2 / 1]'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $r want $want"; fi

kt_test_start "the rule, WIDEN (a view left cells): a space beside an edge widens that side by one cell, the test then runs on the new edge too; without WIDEN nothing widens"
fv.video.writeStr 0 0 '漢字 かなab    ' 1    # 漢 0-1 字 2-3 ' ' 4 か 5-6 な 7-8 a 9 b 10
fv.video.writeStr 0 2 'x漢字かな' 1        # row 2: pairs at 1-2 3-4 5-6 7-8
__FV_VW_WROW=() __FV_VW_WROW[0]=1
r=''
bands 1 5 0 9 1; r+="[$REPLY]"        # left: space at 4 -> 4; right: 'a' at 9 -> stays
bands 1 5 0 11 1; r+="[$REPLY]"       # right: space at 11 -> 12
bands '' 5 0 11 1; r+="[$REPLY]"
__FV_VW_WROW[2]=1
bands 1 5 0 9 3; r+="[$REPLY]"        # widened to 4 (row 0) and 10 (row 2): row 2 has a continuation at 4 -> banded
bands 1 0 0 2 1 4 0 9 1; r+="[$REPLY]" # 2 and 4, both may widen: they meet -> band
want='[4 0 9 1 / 1][4 0 12 1 / 1][5 0 11 1 / 0][4 0 10 2 0 2 20 3 / 2][0 0 20 1 / 1]'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $r want $want"; fi

kt_test_start "the fallbacks band every wide row as before 3a-2: a caller in the C locale (the screen read needs characters), a paint nested in a Draw"
__FV_VW_WROW=() __FV_VW_WROW[0]=1
r=''
( LC_ALL=C; bands '' 2 0 6 1; printf '%s' "[$REPLY]" ) > "$FVW_TMP/c.txt"
r+=$(< "$FVW_TMP/c.txt")
__FV_VW_INDRAW[xx]=1
bands '' 2 0 6 1; r+="[$REPLY]"
unset '__FV_VW_INDRAW[xx]'
__FV_VW_WROW=()
bands '' 3 0 6 1; r+="[$REPLY]"
want='[0 0 20 1 / 1][0 0 20 1 / 1][3 0 6 1 / 0]'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $r want $want"; fi

# ---- a static scene: every edge position --------------------------------------
we_scene() {   # the CJK desk: background, two shadowed windows, a frameless group
    fvw_screen 48 14
    TGroup.new desk 0 0 48 14
    we_leaf bg 0 0 48 14 0 desk
    we_win w1 3 1 24 9 '窓 one' 1
    fv.views.insert desk w1
    we_win w2 17 4 40 12 'two 漢' 2
    fv.views.insert desk w2
    TGroup.new fg 30 1 45 6; we_leaf fgl 1 1 9 4 3 fg; fv.views.insert desk fg
    fvw_expose desk
    fv.views.drawView desk
    WE_DRAWS=()
}
kt_test_start "static CJK scene: a repaint of every rectangle (left edge at every column, widths 1 2 3 5 and to the edge, all rows) == a full repaint"
we_scene
fvw_full desk; f0=$?
fvw_snap; oracle=$REPLY
bad=''
for (( x = 0; x < 48; x++ )); do
    for w in 1 2 3 5 99; do
        x2=$(( x + w )); (( x2 > 48 )) && x2=48
        fv.views._drawUnder desk "$x" 0 "$x2" 14
        fvw_snap
        if [[ $REPLY != "$oracle" ]]; then we_diff "$REPLY" "$oracle"; bad+=" [$x,$x2):$REPLY"; fvw_full desk; fi
        [[ ${#bad} -gt 1500 ]] && break 2
    done
done
if [[ $f0 == 0 && -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

kt_test_start "static CJK scene: drawView of the back window's leaf, of the front window and of the group's leaf == a full repaint"
bad=''
for v in w1l w2 fgl bg w1; do
    fv.views.drawView "$v"
    fvw_snap
    if [[ $REPLY != "$oracle" ]]; then we_diff "$REPLY" "$oracle"; bad+=" $v:$REPLY"; fvw_full desk; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi
desk.delete

# ---- moves across the CJK rows, one column at a time ----------------------------
kt_test_start "a shadowed window moved across CJK rows one column at a time (two heights) and back: every move == a full repaint"
we_scene
we_win mw 0 2 16 6 '' 4
fv.views.insert desk mw
bad=''
for y in 2 7; do
    for (( x = -3; x <= 48; x++ )); do
        fv.views.moveTo mw "$x" "$y"
        fvw_full desk || { bad+=" right x=$x y=$y:$FVW_DIFF"; break 2; }
    done
    for (( x = 47; x >= -3; x -= 2 )); do
        fv.views.moveTo mw "$x" "$y"
        fvw_full desk || { bad+=" left x=$x y=$y:$FVW_DIFF"; break 2; }
    done
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

kt_test_start "a plain leaf (no shadow, no frame) moved across the CJK rows inside the back window and over the desk: every move == a full repaint"
TView.new pl 0 0 3 2
fv.views.insert w1 pl
bad=''
for (( x = -2; x <= 21; x++ )); do
    fv.views.moveTo pl "$x" 3
    fvw_full desk || { bad+=" in w1 x=$x:$FVW_DIFF"; break; }
done
fv.views.delete w1 pl
fvw_full desk || bad+=" delete:$FVW_DIFF"
fv.views.insert desk pl
for (( x = 0; x <= 46; x += 1 )); do
    fv.views.moveTo pl "$x" 10
    fvw_full desk || { bad+=" desk x=$x:$FVW_DIFF"; break; }
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

kt_test_start "hide / show and makeFirst / putInFrontOf of the small window at every third column: == a full repaint"
bad=''
for (( x = -2; x <= 46; x += 3 )); do
    fv.views.moveTo mw "$x" 4
    fv.views.hide mw;   fvw_full desk || { bad+=" hide x=$x:$FVW_DIFF"; break; }
    fv.views.show mw;   fvw_full desk || { bad+=" show x=$x:$FVW_DIFF"; break; }
    fv.views.putInFrontOf mw w1; fvw_full desk || { bad+=" behind x=$x:$FVW_DIFF"; break; }
    fv.views.makeFirst mw; fvw_full desk || { bad+=" front x=$x:$FVW_DIFF"; break; }
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi
desk.delete

# ---- drawPart and the frame border with a window in front at every column ---------
kt_test_start "drawPart of each row of a CJK leaf with a window in front at every column: == a full repaint"
we_scene
we_win mw 0 2 16 6 '' 4
fv.views.insert desk mw
bad=''
for (( x = 15; x <= 42; x++ )); do
    fv.views.moveTo mw "$x" 5
    fvw_full desk
    fvw_snap; o=$REPLY
    for (( y = 0; y < 7; y++ )); do
        fv.views.drawPart w2l we_paint "$y" "$(( y + 1 ))"
    done
    fv.views.drawPart w2l we_paint 0 7
    fvw_snap
    if [[ $REPLY != "$o" ]]; then we_diff "$REPLY" "$o"; bad+=" x=$x:$REPLY"; break; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

kt_test_start "the frame border of a window over CJK rows (another window in front of it at every column): == a full repaint"
bad=''
for (( x = 15; x <= 42; x += 1 )); do
    fv.views.moveTo mw "$x" 3
    fvw_full desk
    fvw_snap; o=$REPLY
    w2__fvframe_data[State]=$(( w2__fvframe_data[State] ^ FV_SF_ACTIVE ))
    fv.views._frameBorder w2__fvframe
    fvw_full desk || { bad+=" x=$x:$FVW_DIFF"; break; }
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

kt_test_start "the narrowing: drawPart of a CJK row that no pair straddles leaves a window in front elsewhere on that row unpainted (3a-1 banded the row: the window was painted again)"
mw.delete
we_win nw 0 4 16 10 '' 4          # (in front of everything; its shadow ends left of w2's leaf, on its rows)
fv.views.insert desk nw
fvw_full desk
WE_DRAWS=()
fvw_count_on; FVW_CALLS=0
fv.views.drawPart w2l we_paint 1 2
n=$FVW_CALLS d=${WE_DRAWS[nwl]:-0}
fvw_count_off
fvw_full desk; f=$?
r="$d $n $f"
if [[ $r == '0 0 0' ]]; then kt_test_pass "ok"; else kt_test_fail "the front leaf's draws, dispatches, full: [$r] $FVW_DIFF"; fi
desk.delete

# ---- randomized scenes --------------------------------------------------------------
we_run() {   # SEED STEPS -> WE_FAIL = '' or the first failing step
    local seed=$1 steps=$2 step v op x y desc
    # (kids move, resize, reorder, hide; the windows' leaves are only drawn: a
    # window's interior stays covered, see we_win)
    local -a kids=(r1 r2 r3 rg rgl rs) leaves=(r1l r2l rgl)
    RANDOM=$seed
    fvw_screen 50 16
    TGroup.new rdesk 0 0 50 16
    we_leaf rbg 0 0 50 16 $(( seed % 5 )) rdesk
    we_win r1 2 1 24 12 '窓 r1' 1;  fv.views.insert rdesk r1
    we_win r2 15 3 41 14 'r2 漢字' 2; fv.views.insert rdesk r2
    we_win r3 33 6 52 18 'r3' 3;     fv.views.insert rdesk r3
    TGroup.new rg 8 10 22 15; we_leaf rgl 1 1 9 4 4 rg; fv.views.insert rdesk rg
    TView.new rs 5 5 8 7; fv.views.insert r1 rs
    fvw_expose rdesk; fv.views.drawView rdesk
    WE_FAIL=''
    fvw_full rdesk || { WE_FAIL="initial:$FVW_DIFF"; rdesk.delete; return; }
    for (( step = 0; step < steps; step++ )); do
        v=${kids[RANDOM % ${#kids[@]}]} op=$(( RANDOM % 10 ))
        case $op in
            0|1) x=$(( RANDOM % 56 - 6 )) y=$(( RANDOM % 18 - 2 )); desc="moveTo $v $x $y"; fv.views.moveTo "$v" "$x" "$y" ;;
            2) x=$(( RANDOM % 30 + 1 )) y=$(( RANDOM % 14 + 1 )); desc="growTo $v $x $y"; fv.views.growTo "$v" "$x" "$y" ;;
            3) desc="makeFirst $v"; fv.views.makeFirst "$v" ;;
            4) desc="putInFrontOf $v ''"; fv.views.putInFrontOf "$v" '' ;;
            5) desc="hide/show $v"; if (( RANDOM % 2 )); then fv.views.hide "$v"; else fv.views.show "$v"; fi ;;
            6) if (( RANDOM % 2 )); then v=${leaves[RANDOM % 3]}; fi; desc="drawView $v"; fv.views.drawView "$v" ;;
            7) v=${leaves[RANDOM % 3]}
               y=$(( RANDOM % 9 )); desc="drawPart $v $y"; fv.views.drawPart "$v" we_paint "$y" "$(( y + 1 + RANDOM % 3 ))" ;;
            8) v=r$(( 1 + RANDOM % 3 )); desc="frame border $v"
               local -n __we_f=${v}__fvframe_data
               __we_f[State]=$(( __we_f[State] ^ FV_SF_ACTIVE ))
               unset -n __we_f
               fv.views._frameBorder "${v}__fvframe" ;;
            9) x=$(( RANDOM % 3 - 1 )) y=$(( RANDOM % 3 - 1 )); desc="nudge $v $x $y"
               local -n __we_v=${v}_data
               fv.views.moveTo "$v" $(( ${__we_v[OriginX]:-0} + x )) $(( ${__we_v[OriginY]:-0} + y ))
               unset -n __we_v ;;
        esac
        if ! fvw_full rdesk; then WE_FAIL="seed $seed step $step ($desc):$FVW_DIFF"; break; fi
    done
    rdesk.delete
}
kt_test_start "randomized CJK scenes (seeded, 3 x 40 steps: moves, nudges, resizes, reorders, hide / show, drawView, drawPart, frame borders): every step == a full repaint"
we_run 11 40; r1=$WE_FAIL
we_run 2026 40; r2=$WE_FAIL
we_run 31337 40; r3=$WE_FAIL
if [[ -z $r1$r2$r3 ]]; then kt_test_pass "ok"; else kt_test_fail "${r1:0:1000} ${r2:0:1000} ${r3:0:1000}"; fi

# ---- drawPart's checked path ----------------------------------------------------------
kt_test_start "drawPart through its checked path (each call with a painter it has not seen: the painter cache entry dropped; rows given as 0Y) of each row of a CJK leaf with a window in front at every column (its pairs straddle the leaf's edges): == a full repaint"
we_paintx() { we_paint "$@"; }
we_scene
we_win mw 0 2 16 6 '' 4
fv.views.insert desk mw
bad=''
for (( x = 15; x <= 42; x++ )); do
    fv.views.moveTo mw "$x" 5
    fvw_full desk
    fvw_snap; o=$REPLY
    for (( y = 0; y < 7; y++ )); do
        unset '__FV_VW_PNT[we_paintx]'
        fv.views.drawPart w2l we_paintx "0$y" "0$(( y + 1 ))" || bad+=" rc $? x=$x y=$y;"
    done
    fvw_snap
    if [[ $REPLY != "$o" ]]; then we_diff "$REPLY" "$o"; bad+=" x=$x:$REPLY"; break; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi
desk.delete

# ---- the marking of a row whose only pair is hidden by half ----------------------------
# (fv.video's per-row flag __FV_VS_WNEW: a wide character written, even one
# the clip cut or a later write covered; fv.views._wideMark marks the row)
declare -A WO_TXT=()
wo_paint() {   # V: the rows' texts WO_TXT[V:y] (default WO_TXT[V])
    local y
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do
        fv.views.writeStr 0 "$y" "${WO_TXT[$1:$y]-${WO_TXT[$1]-}}" 1
    done
}
class TWO : TView
    public
        override proc Draw
end
TWO.Draw() { wo_paint "$this"; }
build TWO
wo_leaf() {   # NAME AX AY BX BY GROUP TEXT
    TWO.new "$1" "$2" "$3" "$4" "$5"
    WO_TXT[$1]=$7
    if [[ -n $6 ]]; then fv.views.insert "$6" "$1"; fi
}
kt_test_start "the marking: a row whose only pair a view in front hides by half at the first paint is marked; a move uncovering the pair, a hide, the view sent behind a CJK leaf, a move uncovering a pair cut by the view's right edge: == a full repaint"
bad=''
# (a) the pair at 2-3, the view's left edge at 3
fvw_screen 20 3; __FV_VW_WROW=()
TGroup.new desk 0 0 20 3
wo_leaf bg 0 0 20 3 desk 'ab漢cdefghijklmnopqr'
TView.new V 3 0 8 3; fv.views.insert desk V
fvw_expose desk; fv.views.drawView desk
r="[${!__FV_VW_WROW[*]}][${#__FV_VS_WNEW[@]}]"
[[ $r == '[0 1 2][0]' ]] || bad+=" marked after the first paint: $r;"
fv.views.moveTo V 4 0
fvw_full desk || bad+=" (a) moveTo:$FVW_DIFF;"
fv.views.moveTo V 3 0; fvw_full desk
fv.views.hide V
fvw_full desk || bad+=" (a) hide:$FVW_DIFF;"
desk.delete
# (a') the pair at 2-3, the view's right edge at 3 (it covers the first half)
fvw_screen 20 3; __FV_VW_WROW=()
TGroup.new desk 0 0 20 3
wo_leaf bg 0 0 20 3 desk 'ab漢cdefghijklmnopqr'
TView.new V 0 0 3 3; fv.views.insert desk V
fvw_expose desk; fv.views.drawView desk
fv.views.moveTo V -1 0
fvw_full desk || bad+=" (a') moveTo:$FVW_DIFF;"
desk.delete
# (c) a CJK leaf W behind the view, its only pair cut by the view's left edge;
# the view sent behind W
fvw_screen 20 3; __FV_VW_WROW=()
TGroup.new desk 0 0 20 3
wo_leaf bg 0 0 20 3 desk 'abcdefghijklmnopqrst'
wo_leaf W 0 0 12 2 desk 'xy漢uvwxyzab'
TView.new V 3 0 8 3; fv.views.insert desk V
fvw_expose desk; fv.views.drawView desk
fv.views.putInFrontOf V bg
fvw_full desk || bad+=" (c) putInFrontOf:$FVW_DIFF;"
desk.delete
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi

wo_row() {   # SEED Y W -> REPLY = W cells: ASCII with one pair, at WO_C
    local c=$(( ($1 * 7 + $2 * 11) % ($3 - 2) ))
    local s='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    WO_C=$c REPLY="${s:0:c}漢${s:c:$3-c-2}"
}
wo_run() {   # SEED STEPS -> WO_FAIL = '' or the first failing step
    local seed=$1 steps=$2 step v op x y w h r desc
    local -a kids=(o1 o2 o3 ow) leaves=(obg owl)
    RANDOM=$seed
    fvw_screen 40 12; __FV_VW_WROW=()
    TGroup.new odesk 0 0 40 12
    wo_leaf obg 0 0 40 12 odesk ''
    for (( y = 0; y < 12; y++ )); do wo_row "$seed" "$y" 40; WO_TXT[obg:$y]=$REPLY; done
    # (each front view starts with an edge on a pair of a row it covers: its
    # left edge on the pair's second half, or its right edge on the first)
    for v in o1 o2 o3; do
        w=$(( 2 + RANDOM % 7 )) h=$(( 1 + RANDOM % 4 )) y=$(( RANDOM % 9 ))
        wo_row "$seed" "$y" 40
        if (( RANDOM % 2 )); then x=$(( WO_C + 1 )); else x=$(( WO_C + 1 - w )); fi
        TView.new "$v" "$x" "$y" $(( x + w )) $(( y + h )); fv.views.insert odesk "$v"
    done
    y=$(( RANDOM % 6 )); wo_row "$seed" "$y" 40
    if (( RANDOM % 2 )); then x=$(( WO_C + 1 )); else x=$(( WO_C + 1 - 16 )); fi
    TWindow.new ow "$x" "$y" $(( x + 16 )) $(( y + 6 )) '' 0
    wo_leaf owl 1 1 15 5 ow ''
    owl_data[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    for (( r = 0; r < 12; r++ )); do wo_row $(( seed + 3 )) "$r" 30; WO_TXT[owl:$r]=$REPLY; done
    fv.views.insert odesk ow
    fvw_expose odesk; fv.views.drawView odesk
    WO_FAIL=''
    for (( step = 0; step < steps; step++ )); do
        v=${kids[RANDOM % ${#kids[@]}]} op=$(( RANDOM % 8 ))
        case $op in
            0|1) x=$(( RANDOM % 3 - 1 )) y=$(( RANDOM % 3 - 1 )); desc="nudge $v $x $y"
               local -n __wo_v=${v}_data
               fv.views.moveTo "$v" $(( ${__wo_v[OriginX]:-0} + x )) $(( ${__wo_v[OriginY]:-0} + y ))
               unset -n __wo_v ;;
            2) x=$(( RANDOM % 44 - 4 )) y=$(( RANDOM % 13 - 1 )); desc="moveTo $v $x $y"; fv.views.moveTo "$v" "$x" "$y" ;;
            3) desc="hide/show $v"; if (( RANDOM % 2 )); then fv.views.hide "$v"; else fv.views.show "$v"; fi ;;
            4) if (( RANDOM % 2 )); then desc="makeFirst $v"; fv.views.makeFirst "$v"; else desc="putInFrontOf $v ''"; fv.views.putInFrontOf "$v" ''; fi ;;
            5) x=$(( RANDOM % 18 + 1 )) y=$(( RANDOM % 7 + 1 )); desc="growTo $v $x $y"; fv.views.growTo "$v" "$x" "$y" ;;
            6) v=${leaves[RANDOM % 2]}; desc="drawView $v"; fv.views.drawView "$v" ;;
            7) v=${leaves[RANDOM % 2]} y=$(( RANDOM % 10 )); desc="drawPart $v $y"; fv.views.drawPart "$v" wo_paint "$y" "$(( y + 1 + RANDOM % 2 ))" ;;
        esac
        if ! fvw_full odesk; then WO_FAIL="seed $seed step $step ($desc):$FVW_DIFF"; break; fi
    done
    odesk.delete
}
kt_test_start "randomized scenes of rows with one pair each, the views in front starting on a pair's half (seeded, 4 x 30 steps: nudges, moves, hide / show, reorders, resizes, drawView, drawPart; no row marked by hand): every step == a full repaint"
r=''
for s in 5 6 7 2026; do wo_run "$s" 30; r+=${WO_FAIL:+"${WO_FAIL:0:700} "}; done
if [[ -z $r ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi

# ---- the VT model ----------------------------------------------------------------
kt_test_start "VT model: after the first paint and after each move of a window across CJK rows, the terminal shows the buffer"
for c in 漢 字 か な 窓; do VT_WD[$c]=2; done
we_scene
we_win mw 0 2 16 6 '' 4
fv.views.insert desk mw
vt_init 48 14
bad=''
vt_capture fv.video.updateScreen force; vt_feed "$VT_OUT" || bad+=" feed0:$VT_ERR"; vt_cmp || bad+=" cmp0:$VT_ERR"
for (( x = 10; x <= 30; x++ )); do
    vt_capture fv.views.moveTo mw "$x" $(( 2 + x % 3 ))
    vt_feed "$VT_OUT" || { bad+=" feed x=$x:$VT_ERR"; break; }
    vt_cmp || { bad+=" cmp x=$x:$VT_ERR"; break; }
done
fvw_full desk || bad+=" full:$FVW_DIFF"
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "${bad:0:1500}"; fi
desk.delete

kt_test_log "026_WideEdge.sh completed"
