#!/usr/bin/env bash
# 020_Caches.sh - the D21 structure caches and drawPart's fast path (fv
# README "Cost"; the state block of fv.views.sh):
#   * DEX (fv.views._drawable as one arithmetic test): dropped at insert and
#     delete (an Owner changed) and at destruction; a view moved out of a
#     drawn tree draws nothing, moved back into one draws; the State bits
#     (hide / show, a State written through the friend contract, the root's
#     sfExposed) and a lock are read live: no invalidation needed;
#   * FRL (the views in front, fv.views._over): dropped at insert, delete and
#     putInFrontOf / makeFirst; a bounds change, hide / show and a State
#     written by hand are read live;
#   * PNT (drawPart's painter cache): the fast path keeps the painter's rc
#     and RESULT, rows with leading zeros are the same rows, a redefined
#     painter runs its new body; a painter unset after its first use fails
#     with bash's "command not found" (rc 127: the documented cost of the
#     cache);
#   * D3: a subview the views in front cover together (two windows side by
#     side over the background) is not drawn, a shadow under them not
#     shaded; a gap, a hidden window or a frameless group in front: drawn;
#     each case equals a full repaint;
#   * B1: drawView and the order redraw's shadow strips are cut to the
#     owner's clip (a window's shadow row outside the desktop does not
#     repaint the status line in front there);
#   * OEX (the pre / post scan's test): dropped at insert; ofPreProcess /
#     ofPostProcess written through the friend contract are read live.
# Each drop and each cut is pinned by a test that fails when it is removed
# (the destruction drop is defensive: insert drops too); the skips by tests
# that fail on the code before D21.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "020: D21 structure caches, drawPart fast path"

# pp V — the drawPart painter: 'P' over every row the paint may change
PPS=PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP
pp() {
    local y
    for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do fv.views.writeStr 0 "$y" "$PPS" 1; done
}
# cell X Y -> REPLY = the character at (X, Y)
cell() { fv.video.getRow "$2"; REPLY=${RESULT:$1:1}; }
# fresh: a new desktop-like scene, painted, with w1l's caches built by one
# drawPart (the scene: w1 2 1 40 20 behind w2 30 5 70 22; w1l over w1's
# interior, columns 3..38, rows 2..18; w2 covers w1l's columns 30..38 from
# row 5)
fresh() {
    if fv.views.isView desk; then fvw_unscene; fi
    fvw_scene
    fv.views.drawView desk
    fv.views.drawPart w1l pp 0 17
}

# ---- FRL: the views in front --------------------------------------------------
fresh
cell 32 6; under=$REPLY
cell 10 6; mine=$REPLY
kt_test_start "FRL: a paint behind a front window leaves its cells to it (w2 over w1l)"
if [[ $under != P && $mine == P ]]; then kt_test_pass "ok"; else kt_test_fail "under w2 [$under] w1l's own [$mine]"; fi

fv.views.makeFirst w1
fv.views.drawPart w1l pp 0 17
cell 32 6
kt_test_start "FRL dropped at putInFrontOf (makeFirst w1): w1l now in front paints the cells w2 held"
if [[ $REPLY == P ]]; then kt_test_pass "ok"; else kt_test_fail "cell (32,6) [$REPLY]"; fi

fresh
fvw_mkwin w3 5 3 15 8 'w3' 3
fv.views.insert desk w3
cell 6 4; before=$REPLY
fv.views.drawPart w1l pp 0 17
cell 6 4
kt_test_start "FRL dropped at insert: a window inserted in front keeps its cells over a later paint"
if [[ $REPLY == "$before" && $REPLY != P ]]; then kt_test_pass "ok"; else kt_test_fail "cell (6,4) [$REPLY] was [$before]"; fi

fresh
fv.views.delete desk w2
fv.views.drawPart w1l pp 0 17
cell 32 6
kt_test_start "FRL dropped at delete: the window taken out no longer covers a paint"
if [[ $REPLY == P ]]; then kt_test_pass "ok"; else kt_test_fail "cell (32,6) [$REPLY]"; fi
w2.delete

fresh
fv.views.moveTo w2 50 5
fv.views.drawPart w1l pp 0 17
cell 32 6; a=$REPLY
fv.views.moveTo w2 30 5
fv.views.drawPart w1l pp 0 17
cell 32 6; b=$REPLY
kt_test_start "FRL read live: a bounds change of a front window (moveTo away and back) is seen"
if [[ $a == P && $b == "$under" ]]; then kt_test_pass "ok"; else kt_test_fail "moved away [$a] back [$b] want [P] [$under]"; fi

fv.views.hide w2
fv.views.drawPart w1l pp 0 17
cell 32 6; a=$REPLY
fv.views.show w2
fv.views.drawPart w1l pp 0 17
cell 32 6; b=$REPLY
kt_test_start "FRL read live: hide / show of a front window is seen"
if [[ $a == P && $b == "$under" ]]; then kt_test_pass "ok"; else kt_test_fail "hidden [$a] shown [$b]"; fi

w2_data[State]=$(( w2_data[State] & ~FV_SF_VISIBLE ))
fv.views.drawPart w1l pp 0 17
cell 32 6; a=$REPLY
w2_data[State]=$(( w2_data[State] | FV_SF_VISIBLE ))
fv.views.drawPart w1l pp 0 17
cell 32 6; b=$REPLY
kt_test_start "FRL read live: a front window's State written through the friend contract is seen"
if [[ $a == P && $b == "$under" ]]; then kt_test_pass "ok"; else kt_test_fail "bit off [$a] bit on [$b]"; fi

# ---- DEX: the drawable test ---------------------------------------------------
fresh
fv.views.delete w1 w1l
cell 10 6; before=$REPLY
fv.views.drawPart w1l pp 0 17
cell 10 6
kt_test_start "DEX dropped at delete: a leaf taken out of the drawn tree (no exposed root) draws nothing"
if [[ $REPLY == "$before" && $REPLY != P ]]; then kt_test_pass "ok"; else kt_test_fail "cell (10,6) [$REPLY] was [$before]"; fi

fv.views.insert w1 w1l
fv.views.drawPart w1l pp 0 17
cell 10 6
kt_test_start "DEX dropped at insert: the same leaf inserted back (its cache built while it was a root) draws"
if [[ $REPLY == P ]]; then kt_test_pass "ok"; else kt_test_fail "cell (10,6) [$REPLY]"; fi

fresh
w1l.delete
fvw_classes
TTList.new w1l 1 1 37 18
fv.views.insert w2 w1l
fv.views.drawPart w1l pp 0 17
cell 40 7; a=$REPLY
cell 10 6; b=$REPLY
kt_test_start "DEX/FRL after destruction: the name re-created in another window paints there only"
if [[ $a == P && $b != P ]]; then kt_test_pass "ok"; else kt_test_fail "in w2 [$a] old place [$b]"; fi

fresh
fv.views.hide w1
cell 10 6; before=$REPLY
fv.views.drawPart w1l pp 0 17
cell 10 6; a=$REPLY
fv.views.show w1
fv.views.drawPart w1l pp 0 17
cell 10 6; b=$REPLY
kt_test_start "DEX read live: an owner hidden draws nothing, shown again draws"
if [[ $a == "$before" && $a != P && $b == P ]]; then kt_test_pass "ok"; else kt_test_fail "hidden [$a] (was [$before]) shown [$b]"; fi

fresh
fv.views.drawView w1
cell 10 6; before=$REPLY
w1_data[State]=$(( w1_data[State] & ~FV_SF_VISIBLE ))
fv.views.drawPart w1l pp 0 17
cell 10 6; a=$REPLY
w1_data[State]=$(( w1_data[State] | FV_SF_VISIBLE ))
desk_data[State]=$(( desk_data[State] & ~FV_SF_EXPOSED ))
fv.views.drawPart w1l pp 0 17
cell 10 6; b=$REPLY
desk_data[State]=$(( desk_data[State] | FV_SF_EXPOSED ))
fv.views.drawPart w1l pp 0 17
cell 10 6; c=$REPLY
kt_test_start "DEX read live: an owner's State and the root's sfExposed written through the friend contract are seen"
if [[ $a == "$before" && $b == "$before" && $before != P && $c == P ]]; then kt_test_pass "ok"; else kt_test_fail "owner hidden [$a] root unexposed [$b] (was [$before]) back [$c]"; fi

fresh
fv.views.drawView w1
cell 10 6; before=$REPLY
fv.views.lock w1
fv.views.drawPart w1l pp 0 17
cell 10 6; a=$REPLY
fv.views.unlock w1
fv.views.drawPart w1l pp 0 17
cell 10 6; b=$REPLY
kt_test_start "DEX: a locked owner (the lock path) draws nothing, unlocked draws"
if [[ $a == "$before" && $a != P && $b == P ]]; then kt_test_pass "ok"; else kt_test_fail "locked [$a] (was [$before]) unlocked [$b]"; fi

# ---- PNT: the painter cache, the fast path ------------------------------------
fresh
prc() { RESULT=painter; pp "$@"; return 3; }
RESULT=keep; fv.views.drawPart w1l prc 0 1; r1="$?:$RESULT"
RESULT=keep; fv.views.drawPart w1l prc 0 1; r2="$?:$RESULT"
fvw_check "fast path: the painter's rc passed, RESULT kept (first call and cached call alike)" "3:keep 3:keep" "$r1 $r2"

fresh
fv.views.drawPart w1l pp 007 008; cell 10 9; a=$REPLY
fv.views.drawPart w1l pp 0 7; cell 10 9; b=$REPLY
fv.views.drawPart w1l pp 0010 11; cell 10 12; c=$REPLY
fvw_check "fast path: rows with leading zeros are decimal rows (007..008 = row 7; 0010 = row 10)" "P P P" "$a $b $c"

fresh
pnew() { local y; for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do fv.views.writeStr 0 "$y" AAAA 1; done; }
fv.views.drawPart w1l pnew 0 1
pnew() { local y; for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do fv.views.writeStr 0 "$y" BBBB 1; done; }
fv.views.drawPart w1l pnew 0 1
cell 3 2
fvw_check "PNT holds the name, not the body: a redefined painter runs its new body" "B" "$REPLY"

unset -f pnew
RESULT=keep; fv.views.drawPart w1l pnew 0 1 2>"$FVW_TMP/p127.err"; r="$?:$RESULT"
kt_test_start "PNT: a painter unset after its first use fails as bash does (rc 127, 'command not found'), RESULT kept"
if [[ $r == 127:keep ]] && grep -q 'not found' "$FVW_TMP/p127.err"; then kt_test_pass "ok"
else kt_test_fail "[$r] stderr [$(head -c 200 "$FVW_TMP/p127.err")]"; fi
RESULT=keep; fv.views.drawPart w1l nevermadefn 0 1; r="$?:$RESULT"
fvw_check "a painter never seen that is no function: still rc 2, RESULT ''" "2:" "$r"

fvw_unscene

# ---- D3: a subview or a shadow the views in front cover TOGETHER ---------------
# side: desk 80 x 24 > bgl (a counting TTList over the whole desk), w1 (0 0
# 40 24) and w2 (40 0 80 24) in front: no single window covers bgl, the two
# together do; w1's shadow (columns 40-41) lies under w2
SH=0
side() {
    fvw_screen 80 24
    TGroup.new desk 0 0 80 24
    fvw_classes
    TTList.new bgl 0 0 80 24
    fv.views.insert desk bgl
    fvw_mkwin w1 0 0 40 24 'Left' 1
    fvw_mkwin w2 40 0 80 24 'Right' 2
    fv.views.insert desk w1
    fv.views.insert desk w2
    fvw_expose desk
    FVW_DRAWS=()
}
# shades CMD... -> REPLY = the fv.video shade calls CMD made
shades() {
    fvw_wrap SH fv.video._shadef fv.video.shadeRect
    SH=0
    "$@"
    REPLY=$SH
    fvw_unwrap fv.video._shadef fv.video.shadeRect
}
side
shades fv.views.drawView desk; sh=$REPLY
kt_test_start "union cover: two windows side by side hold the background together: it is not drawn, w1's shadow under w2 not shaded"
if [[ ${FVW_DRAWS[bgl]:-0} == 0 && $sh == 0 ]]; then kt_test_pass "ok"; else kt_test_fail "bgl draws [${FVW_DRAWS[bgl]:-0}] shades [$sh]"; fi
fvw_full desk; fvw_check "union cover: the screen equals a full repaint from garbage (nothing left uncovered)" "" "$FVW_DIFF"

FVW_DRAWS=()
fv.views.moveTo w2 41 0
kt_test_start "a one-column gap between the windows: the background is drawn again (the move), w1's shadow shows there"
fvw_cells 40 2 1
if (( ${FVW_DRAWS[bgl]:-0} >= 1 )) && [[ $REPLY == V ]]; then kt_test_pass "ok"; else kt_test_fail "bgl draws [${FVW_DRAWS[bgl]:-0}] cell (40,2) symbol [$REPLY]"; fi
fvw_full desk; fvw_check "the gap: the screen equals a full repaint" "" "$FVW_DIFF"
fvw_unscene

side
fv.views.hide w1
FVW_DRAWS=()
fv.views.drawView desk
kt_test_start "a hidden window in front holds nothing: the background is drawn"
if [[ ${FVW_DRAWS[bgl]:-0} == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "bgl draws [${FVW_DRAWS[bgl]:-0}]"; fi
fvw_full desk; fvw_check "the hidden window: the screen equals a full repaint" "" "$FVW_DIFF"
fvw_unscene

side
w1.delete
TGroup.new g1 0 0 40 24
fv.views.insertBefore desk g1 w2
FVW_DRAWS=()
fv.views.drawView desk
kt_test_start "a frameless group in front (no covering view: FV covers only by a framed group or a leaf) holds the top-left cell but not the background: it is drawn"
if [[ ${FVW_DRAWS[bgl]:-0} == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "bgl draws [${FVW_DRAWS[bgl]:-0}]"; fi
fvw_full desk; fvw_check "the frameless group: the screen equals a full repaint" "" "$FVW_DIFF"
fvw_unscene


# ---- B1: a window's paint and its shadow strips cut to the owner's clip -------
# status: app (root) > desk (0 0 80 23) > bg, w1 (0 10 40 23, its shadow
# row 23 outside the desk); sl (0 23 80 24, a counting TTList) in front of
# the desk, as the status line is
status() {
    fvw_screen 80 24
    fvw_classes
    TGroup.new app 0 0 80 24
    TGroup.new desk 0 0 80 23
    TView.new bg 0 0 80 23
    fv.views.insert desk bg
    fvw_mkwin w1 0 10 40 23 'Low' 1
    fv.views.insert desk w1
    fv.views.insert app desk
    TTList.new sl 0 23 80 24
    fv.views.insert app sl
    fvw_expose app
    fv.views.drawView app
    FVW_DRAWS=()
}
status
fv.views.drawView w1
kt_test_start "drawView of a window whose shadow row lies outside its owner: the view in front out there (the status line) is not repainted"
if [[ ${FVW_DRAWS[sl]:-0} == 0 && ${FVW_DRAWS[w1l]:-0} == 1 ]]; then kt_test_pass "ok"; else kt_test_fail "sl draws [${FVW_DRAWS[sl]:-0}] w1l draws [${FVW_DRAWS[w1l]:-0}]"; fi
fvw_full app; fvw_check "B1 drawView: the screen equals a full repaint" "" "$FVW_DIFF"

fvw_mkwin w2 40 5 60 23 'Side' 2
fv.views.insert desk w2
FVW_DRAWS=()
fv.views.makeFirst w1
fvw_cells 40 11 2
kt_test_start "the order redraw of shadow strips only (w1 to the front, its shadow over w2): cut to the desk, the status line not repainted"
if [[ ${FVW_DRAWS[sl]:-0} == 0 && $REPLY == VV ]]; then kt_test_pass "ok"; else kt_test_fail "sl draws [${FVW_DRAWS[sl]:-0}] shadow cells [$REPLY]"; fi
fvw_full app; fvw_check "B1 order strips: the screen equals a full repaint" "" "$FVW_DIFF"
app.delete

# ---- OEX: the pre / post scan's test over the subviews' live Options ----------
fvw_classes2
TGroup.new g 0 0 30 10
g_data[State]=$(( g_data[State] | FV_SF_SELECTED ))
TTLeaf.new la 0 0 10 10; TTLeaf.new lb 10 0 20 10
la_data[Options]=$FV_OF_SELECTABLE lb_data[Options]=$FV_OF_SELECTABLE
fv.views.insert g la; fv.views.insert g lb
key() { FVW_GOT=''; fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1; fv.views._virt g HandleEvent; }
key kbF2; a=$FVW_GOT
TTLeaf.new lc 20 0 30 10
lc_data[Options]=$FV_OF_POSTPROCESS
fv.views.insert g lc
key kbF3; b=$FVW_GOT
kt_test_start "OEX dropped at insert: a subview inserted with ofPostProcess gets the key after Current"
if [[ $a == 'lb:evKeyDown:kbF2;' && $b == 'lb:evKeyDown:kbF3;lc:evKeyDown:kbF3;' ]]; then kt_test_pass "ok"; else kt_test_fail "before [$a] after [$b]"; fi
la_data[Options]=$(( la_data[Options] | FV_OF_PREPROCESS ))
key kbF4; c=$FVW_GOT
lc_data[Options]=0
key kbF5; d=$FVW_GOT
kt_test_start "OEX read live: ofPreProcess / ofPostProcess written through the friend contract are seen"
if [[ $c == 'la:evKeyDown:kbF4;lb:evKeyDown:kbF4;lc:evKeyDown:kbF4;' && $d == 'la:evKeyDown:kbF5;lb:evKeyDown:kbF5;' ]]; then kt_test_pass "ok"; else kt_test_fail "pre on [$c] post off [$d]"; fi
g.delete

# ---- drawView of a view outside its owner's clip still sends what is held ----
fvw_scene 80 24
fv.views.drawView desk
fv.views.moveTo w1 90 2
fvw_classes2
ppn() { local y; for (( y = FV_CLIP_Y1; y < FV_CLIP_Y2; y++ )); do fv.views.writeStr 0 "$y" 'NEWTEXT' 1; done; }
fv.views.drawPart w2l ppn 0 1
fvw_outsize; s0=$REPLY
fv.views.lock w1
fv.views.drawPart w2l ppn 2 3
fv.views.unlock w1
fvw_outsize; s1=$REPLY
kt_test_start "unlock of a view wholly outside its owner's clip: the frame held meanwhile is sent (nothing pending, bytes out)"
if (( ! __FV_VW_PEND && s1 > s0 )); then kt_test_pass "ok"; else kt_test_fail "PEND=$__FV_VW_PEND bytes=$(( s1 - s0 ))"; fi
fvw_outsize; s0=$REPLY
fv.views.redraw w1
fvw_outsize; s1=$REPLY
kt_test_start "redraw of a view outside its owner's clip: the forced update goes out at once (no forced update left for the next draw)"
if (( ! ${__FV_VW_FORCE:-0} && s1 > s0 )); then kt_test_pass "ok"; else kt_test_fail "FORCE=${__FV_VW_FORCE-} bytes=$(( s1 - s0 ))"; fi

kt_test_log "020_Caches.sh completed"
