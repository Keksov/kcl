#!/usr/bin/env bash
# 004_Draw.sh - the drawing context, the writers, the clip, palette indices,
# drawPart (design §1.5, §1.7; review finding 2):
#   * the writers in view-local coordinates, one fv.video call each, a palette
#     index -> the view's resolved symbol (an index outside: ErrorAttr's
#     symbol); writeLine takes resolved symbols and a repeat count; outside a
#     Draw and with bad arguments: rc 2, RESULT '' (one debug line);
#   * FV_DRAW_VIEW / _X / _Y / _PAL and FV_CLIP_X1 .. _Y2 inside a Draw; the
#     writes clipped to the owner's clip; the caller's fv.video clip and its
#     context restored after drawView;
#   * a drawView nested inside a Draw leaves the outer Draw's context and clip
#     intact (its next write lands in its own coordinates, clipped as before);
#   * TView.Draw = blanks in colour 1; a group override that calls
#     `inherited Draw` and then decorates writes with the group's clip;
#   * drawView refuses nothing it cannot draw: a hidden view, a hidden owner,
#     a root without sfExposed -> nothing drawn, rc 0, RESULT kept; V.Draw
#     called outside the painter draws nothing;
#   * drawPart: the painter function runs with V's context, its writes
#     clipped to the rows, the front views over those rows painted again, no
#     dispatch, its rc passed, RESULT kept;
#   * getColor V I; redraw sends a forced frame, drawView of an unchanged
#     scene sends nothing; a redraw while held sends its forced frame at the
#     release;
#   * review round: re-entrancy (a Draw redrawing a view behind it: once, no
#     recursion, == a full repaint, also after a move; a list redrawing
#     scroll bars beside and behind it stays on top); a Draw ending non-zero
#     under set -e; drawPart on a group refused.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "004: drawing context, writers, drawPart"

fvw_screen 40 12

# a leaf whose Draw writes with every writer and records the context
class TW : TView
    public
        override proc Draw
end
TW.Draw() {
    CTX="$FV_DRAW_VIEW $FV_DRAW_X $FV_DRAW_Y ${FV_DRAW_PAL:0:3} $FV_CLIP_X1 $FV_CLIP_Y1 $FV_CLIP_X2 $FV_CLIP_Y2"
    fv.views.fill 0 0 "$SizeX" "$SizeY" '.' 1
    fv.views.writeStr 1 0 'str' 2; WR="$?:$RESULT"
    fv.views.writeChar 0 1 '#' 3 4; WR+=" $?:$RESULT"
    fv.views.writeCStr 0 2 'a~b~c' 1 2; WR+=" $?:$RESULT"
    fv.views.writeLine 5 1 2 'LL' 'zz'; WR+=" $?:$RESULT"
    fv.views.writeStr 8 3 'far' 99; WR+=" $?:$RESULT"
}
build TW

class TPal : TGroup
    public
        override func GetPalette
end
TPal.GetPalette() { RESULT='3 4 5 6'; }
build TPal

TPal.new root 0 0 40 12
TW.new w 2 2 12 6
fv.views.insert root w
fvw_expose root

kt_test_start "the writers in local coordinates, palette index -> the view's resolved symbol"
CTX='' WR=''
fv.views.drawView root
fvw_cells 2 2 10; r0="$RESULT|$REPLY"
fvw_cells 2 3 10; r1="$RESULT|$REPLY"
fvw_cells 2 4 10; r2="$RESULT|$REPLY"
fvw_cells 2 5 10; r3="$RESULT|$REPLY"
# root's palette 3 4 5 6 -> app entries 3..6 = symbols 3 4 5 6; w maps as root
want='.str......|3444333333 ####.LL...|55553zz333 abc..LL...|34333zz333 ........fa|3333333300'
got="$r0 $r1 $r2 $r3"
if [[ $got == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$got] want [$want]"; fi

kt_test_start "the writers' answers: fv.video's RESULT and rc; an index past the palette writes in ErrorAttr's symbol (0)"
fvw_cells 10 5 2; e=$REPLY
if [[ $WR == '0:3 0:4 0:3 0:2 0:3' && $e == 00 ]]; then kt_test_pass "ok"; else kt_test_fail "[$WR] err cells [$e]"; fi

kt_test_start "the context inside the Draw: FV_DRAW_VIEW / X / Y / PAL, FV_CLIP_* (local, B exclusive)"
if [[ $CTX == 'w 2 2 345 0 0 10 4' ]]; then kt_test_pass "ok"; else kt_test_fail "[$CTX]"; fi

kt_test_start "outside a Draw: every writer rc 2, RESULT '', nothing written; the context is empty again"
out=''
for c in 'writeStr 0 0 x 1' 'writeChar 0 0 x 1' 'writeCStr 0 0 x 1 2' 'writeLine 0 0 1 x 1' 'fill 0 0 1 1 x 1'; do
    RESULT=keep; fv.views.$c; out+="$?:${RESULT-u} "
done
fvw_cells 0 0 1; z=$RESULT
if [[ $out == '2: 2: 2: 2: 2: ' && -z $FV_DRAW_VIEW && $FV_CLIP_X2 == 0 && $z == ' ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out] ctx=[$FV_DRAW_VIEW $FV_CLIP_X2] z=[$z]"; fi

kt_test_start "bad arguments inside a Draw: rc 2 each (non-integer X / Y, an index that is not a number, a wrong count)"
class TBad : TView
    public
        override proc Draw
end
TBad.Draw() {
    BAD=''
    fv.views.writeStr x 0 a 1 || BAD+="$?"
    fv.views.writeStr 0 '1+1' a 1 || BAD+="$?"
    fv.views.writeStr 0 0 a -1 || BAD+="$?"
    fv.views.writeStr 0 0 a 'a[0]' || BAD+="$?"
    fv.views.writeChar 0 0 a || BAD+="$?"
    fv.views.writeCStr 0 0 a 1 z || BAD+="$?"
    fv.views.fill 0 0 1 1 x || BAD+="$?"
    fv.views.writeLine 0 0 1 ab z || BAD+="$?"
}
build TBad
TBad.new bad 0 0 1 1
fv.views.insert root bad
BAD=''
fv.views.drawView bad
if [[ $BAD == 22222222 ]]; then kt_test_pass "ok"; else kt_test_fail "[$BAD]"; fi
fv.views.delete root bad; bad.delete

kt_test_start "clip: a view reaching past its owner is clipped to the owner's clip; the caller's fv.video clip and RESULT kept"
TGroup.new g 30 8 36 11
TW.new w2 2 0 12 6
fv.views.insert root g
fv.views.insert g w2
fv.video.setClip 1 1 39 11
RESULT=caller
fv.views.drawView w2
c=$RESULT
fv.video.getClip; cl=$RESULT
fvw_cells 30 8 10; a="$RESULT"
fvw_cells 30 11 1; b="$RESULT"
if [[ $c == caller && $cl == '1 1 39 11' && $a == '  .str    ' && $b == ' ' ]]; then kt_test_pass "ok"; else kt_test_fail "RESULT=[$c] clip=[$cl] row8=[$a] row11=[$b]"; fi
fv.video.resetClip
fv.views.delete root g

# a Draw that draws another view in the middle (a scroll bar redrawn during a
# list's Draw): the outer context and clip survive
class TOuter : TView
    public
        override proc Draw
end
TOuter.Draw() {
    fv.views.writeStr 0 0 'AAAAAA' 1
    fv.views.drawView inner
    NEST="$FV_DRAW_VIEW $FV_DRAW_X $FV_DRAW_Y $FV_CLIP_X1 $FV_CLIP_Y1 $FV_CLIP_X2 $FV_CLIP_Y2"
    fv.video.getClip; NEST+=" | $RESULT"
    fv.views.writeStr 0 1 'BBBBBBBBBB' 1
}
build TOuter
class TInner : TView
    public
        override proc Draw
end
TInner.Draw() { INNER="$FV_DRAW_VIEW $FV_DRAW_X $FV_DRAW_Y"; fv.views.fill 0 0 "$SizeX" "$SizeY" i 2; }
build TInner

kt_test_start "a drawView nested inside a Draw: the inner view drawn with its own context, the outer Draw's context and clip intact afterwards"
TGroup.new g2 20 0 30 4
TOuter.new outer -2 0 8 3
TInner.new inner 0 6 3 8
fv.views.insert root g2
fv.views.insert g2 outer
fv.views.insert root inner
NEST='' INNER=''
fv.views.drawView outer
fvw_cells 20 1 10; o1=$RESULT
fvw_cells 0 6 3; i1="$RESULT|$REPLY"
fvw_cells 20 0 5; o0=$RESULT
want_nest='outer 18 0 2 0 10 3 | 20 0 28 3'
if [[ $NEST == "$want_nest" && $INNER == 'inner 0 6' && $o1 == BBBBBBBB?? && $o0 == 'AAAA ' && $i1 == 'iii|444' ]]; then kt_test_pass "ok"
else kt_test_fail "nest=[$NEST] inner=[$INNER] o1=[$o1] o0=[$o0] i1=[$i1]"; fi
fv.views.delete root g2; fv.views.delete root inner

kt_test_start "TView.Draw: blanks in colour 1 over the whole view (one fill)"
TView.new pv 0 9 5 11
fv.views.insert root pv
fvw_writes_on; FVW_WRITES=0
fv.views.drawView pv
n=$FVW_WRITES
fvw_writes_off
fvw_cells 0 9 6; a="$RESULT|$REPLY"
fvw_cells 0 10 6; b="$RESULT|$REPLY"
if [[ $n == 1 && $a == '      |333330' && $b == '      |333330' ]]; then kt_test_pass "ok"; else kt_test_fail "writes=$n [$a] [$b]"; fi

class TDeco : TGroup
    public
        override proc Draw
end
TDeco.Draw() { inherited Draw; fv.views.writeStr 0 0 'DECO-DECO-DECO' 2; }
build TDeco

kt_test_start "a group override: inherited Draw paints the subviews, then its own write lands with the group's clip"
TDeco.new deco 10 9 16 11
TView.new dk 0 1 3 2
fv.views.insert root deco
fv.views.insert deco dk
fv.views.drawView deco
fvw_cells 10 9 8; a="$RESULT|$REPLY"
fvw_cells 10 10 4; b="$RESULT|$REPLY"
if [[ $a == 'DECO-D  |44444400' && $b == '    |3330' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi
fv.views.delete root deco; deco.delete

kt_test_start "nothing drawn for a hidden view, a view in a hidden group, a tree whose root lacks sfExposed; rc 0, RESULT kept"
fv.video.clearScreen
TGroup.new hg 0 0 10 10
TView.new hv 0 0 2 2
fv.views.insert root hg
fv.views.insert hg hv
fv.video.clearScreen   # (the insert drew hv: start from a blank screen)
out=''
hg_data[State]=$(( hg_data[State] & ~FV_SF_VISIBLE ))
RESULT=k; fv.views.drawView hv; out+="$?$RESULT "
hg_data[State]=$(( hg_data[State] | FV_SF_VISIBLE ))
hv_data[State]=$(( hv_data[State] & ~FV_SF_VISIBLE ))
RESULT=k; fv.views.drawView hv; out+="$?$RESULT "
hv_data[State]=$(( hv_data[State] | FV_SF_VISIBLE ))
root_data[State]=$(( root_data[State] & ~FV_SF_EXPOSED ))
RESULT=k; fv.views.drawView hv; out+="$?$RESULT "
fvw_expose root
fvw_cells 0 0 2; a=$REPLY
fv.views.drawView hv
fvw_cells 0 0 2; b=$REPLY
if [[ $out == '0k 0k 0k ' && $a == 00 && $b == 33 ]]; then kt_test_pass "ok"; else kt_test_fail "[$out] before [$a] after [$b]"; fi
fv.views.delete root hg; hg.delete

kt_test_start "V.Draw / _virt V Draw outside the painter draws nothing; the drawView alias draws"
fv.video.clearScreen
pv.Draw; fv.views._virt pv Draw
fvw_cells 0 9 5; a=$REPLY
pv.DrawView
fvw_cells 0 9 5; b=$REPLY
if [[ $a == 00000 && $b == 33333 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi

kt_test_start "getColor V I: the resolved symbol; ErrorAttr's (0) outside; rc 2 for a bad index"
out=''
fv.views.getColor w 1; out+="$RESULT"; fv.views.getColor w 4; out+="$RESULT"; fv.views.getColor w 5; out+="$RESULT"
fv.views.getColor w 0; out+="$RESULT"
RESULT=k; fv.views.getColor w x; out+=" $?:$RESULT"
fv.views.getColor nosuch 1; out+=" $?"
if [[ $out == '3600 2: 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

# drawPart: a painter function writes rows of a list; a view in front of the
# list overlaps one of them and must be painted again over it
paint_rows() {   # V TEXT
    PCTX="$FV_DRAW_VIEW $FV_CLIP_Y1 $FV_CLIP_Y2"
    local y
    for (( y = 0; y < 4; y++ )); do fv.views.writeStr 0 "$y" "$2$y$2$y$2" 1; done
    return 3
}
kt_test_start "drawPart: the painter's writes clipped to the rows, the front view over them painted again, no dispatch, its rc, RESULT kept"
fv.video.clearScreen
TView.new lst 0 0 10 4
TView.new front 2 1 4 3
fv.views.insert root lst
fv.views.insert root front
front_data[Options]=0
fv.views.drawView root
fvw_count_on; FVW_CALLS=0
RESULT=keep; PCTX=''
fv.views.drawPart lst paint_rows 1 3 '#'; rc=$?
n=$FVW_CALLS r=$RESULT
fvw_count_off
fvw_cells 0 0 6; a=$RESULT
fvw_cells 0 1 6; b="$RESULT|$REPLY"
fvw_cells 0 2 6; c=$RESULT
fvw_cells 0 3 6; d=$RESULT
if [[ $rc == 3 && $n == 0 && $r == keep && $PCTX == 'lst 1 3' && $a == '      ' && $b == '#1  # |333333' && $c == '#2  # ' && $d == '      ' ]]; then kt_test_pass "ok"
else kt_test_fail "rc=$rc calls=$n RESULT=$r ctx=[$PCTX] rows [$a] [$b] [$c] [$d]"; fi

kt_test_start "drawPart refusals: not a view, not a function, bad rows, a wrong count (rc 2); a hidden view: rc 0, nothing runs"
out=''
fv.views.drawPart nosuch paint_rows 0 1; out+="$?"
fv.views.drawPart lst no_such_fn 0 1; out+="$?"
fv.views.drawPart lst paint_rows 0 x; out+="$?"
fv.views.drawPart lst paint_rows 0; out+="$?"
lst_data[State]=0 PCTX=''
fv.views.drawPart lst paint_rows 0 1; out+="$?$PCTX"
lst_data[State]=$FV_SF_VISIBLE
if [[ $out == 22220 ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "redraw sends a forced frame (every cell); drawView of an unchanged scene sends nothing"
fv.views.drawView root
fvw_outsize; s0=$REPLY
fv.views.drawView root
fvw_outsize; s1=$REPLY
fv.views.redraw root
fvw_outsize; s2=$REPLY
if (( s1 == s0 && s2 - s1 > 40 * 12 )); then kt_test_pass "ok ($(( s2 - s1 )) bytes)"; else kt_test_fail "sizes $s0 $s1 $s2"; fi

root.delete   # (pv is inside root: destroyed with it)

# --- review round: re-entrancy, set -e, the deferred forced update, drawPart on a group ---
fv.video.clearScreen
TGroup.new top 0 0 40 12
TView.new tbg 0 0 40 12
fv.views.insert top tbg
fvw_expose top

# a frameless group in front of `other` whose Draw redraws `other` (behind it,
# overlapping) in the middle of its own Draw: drawView and drawPart
class TNest : TGroup
    public
        override proc Draw
end
TNest.Draw() {
    inherited Draw
    NESTN=$(( NESTN + 1 ))
    fv.views.drawView other
    fv.views.drawPart other paint_other 0 1
    fv.views.writeStr 0 0 'DECO' 1
}
build TNest
class TOther : TView
    public
        override proc Draw
end
TOther.Draw() { OTHERN=$(( OTHERN + 1 )); fv.views.fill 0 0 "$SizeX" "$SizeY" o 2; }
build TOther
paint_other() { fv.views.writeStr 0 0 'pp' 1; }

kt_test_start "re-entrancy: a Draw that redraws a view behind it (drawView + drawPart) runs once, no recursion; the screen equals a full repaint (also after moving that view)"
TOther.new other 25 2 35 6
TNest.new dg 2 2 20 8
TView.new dk 1 1 5 3
fv.views.insert dg dk
fv.views.insert top other
fv.views.insert top dg
NESTN=0 OTHERN=0
fv.views.drawView top
a="$NESTN $OTHERN $__FV_VW_DEPTH ${#__FV_VW_INDRAW[@]}"
fvw_full top; f1=$?; d1=$FVW_DIFF
NESTN=0
fv.views.moveTo other 15 1
b="$NESTN"
fvw_full top; f2=$?; d2=$FVW_DIFF
if [[ $a == '1 2 0 0' && $b == 1 && $f1 == 0 && $f2 == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "draws [$a] after move [$b]; full: $f1 $d1 / $f2 $d2"; fi
dg.delete; other.delete

# the design's case: a list whose Draw redraws a scroll bar beside it and one
# behind it (overlapping): the bar behind is not painted over the list
class TLst : TView
    public
        override proc Draw
end
TLst.Draw() {
    local y s
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do printf -v s '%-*s' "$SizeX" "line $y"; fv.views.writeStr 0 "$y" "$s" 1; done
    fv.views.drawView sbside; fv.views.drawView sbback
}
build TLst
kt_test_start "re-entrancy: the list's Draw redraws a scroll bar beside it and one behind it: the list stays on top, the screen equals a full repaint"
TOther.new sbback 10 3 13 9
TLst.new lst2 4 2 12 8
TOther.new sbside 12 2 13 8
fv.views.insert top sbback; fv.views.insert top lst2; fv.views.insert top sbside
OTHERN=0
fv.views.drawView top
fvw_cells 10 4 2; c=$RESULT   # (list cells over the bar behind: the list's padding, not the bar's o)
fvw_full top; f=$?
if [[ $f == 0 && $c == '  ' ]]; then kt_test_pass "ok (cells under the list [$c])"; else kt_test_fail "full=$f $FVW_DIFF cells [$c]"; fi
lst2.delete; sbback.delete; sbside.delete

class TFail : TView
    public
        override proc Draw
end
TFail.Draw() { fv.views.writeStr 0 0 'F' 1; [[ -n '' ]]; }
build TFail
kt_test_start "a Draw ending non-zero (FV Draw is a procedure: its rc is ignored): drawView, insert, moveTo, unlock under set -e keep going"
TFail.new fl 30 8 34 10
out=$(
    set -e
    fv.views.insert top fl; printf i
    fv.views.drawView fl; printf d
    fv.views.moveTo fl 31 8; printf m
    fv.views.lock top; fv.views.unlock top; printf u
    printf ':%s' "$__FV_VW_DEPTH"
)
if [[ $out == 'idmu:0' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi
fl.delete 2>/dev/null || :

kt_test_start "redraw while the update is held: the forced frame is sent at the release (every cell)"
fv.views.drawView top
fvw_outsize; s0=$REPLY
fv.views.lockScreenUpdate
fv.views.redraw top
fvw_outsize; s1=$REPLY
fv.views.unlockScreenUpdate
fvw_outsize; s2=$REPLY
fv.views.drawView top
fvw_outsize; s3=$REPLY
if (( s1 == s0 && s2 - s1 > 40 * 12 && s3 == s2 && __FV_VW_FORCE == 0 )); then kt_test_pass "ok ($(( s2 - s1 )) bytes)"; else kt_test_fail "sizes $s0 $s1 $s2 $s3 force=$__FV_VW_FORCE"; fi

kt_test_start "drawPart on a group: rc 2, RESULT '', nothing runs"
TGroup.new pg2 0 0 5 5; fv.views.insert top pg2
PCTX=''
RESULT=k; fv.views.drawPart pg2 paint_rows 0 1; r="$?:$RESULT:$PCTX"
if [[ $r == '2::' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi
top.delete
kt_test_log "004_Draw.sh completed"
