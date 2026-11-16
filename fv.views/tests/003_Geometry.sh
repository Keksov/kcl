#!/usr/bin/env bash
# 003_Geometry.sh - FV corner bounds and the geometry procedures: the
# constructors' R.Assign corners and FV's field defaults, MaxViewWidth,
# getBounds / getExtent (RESULT and FV_RECT_*), the bounds cache (absolute
# origin, clip = own rect ∩ the owner's clip, nested, empty, detached),
# centring at insert, locate (SizeLimits clamp: the owner's size, no owner =
# high(Sw_Integer)) / moveTo / growTo, changeBounds and an owner resize by
# every GrowMode flag (gfGrowRel, the S = D guard, the MaxViewWidth cap),
# CalcBounds / SizeLimits answers, makeLocal / makeGlobal / mouseInView,
# GetHelpCtx, bad numbers, the hook's `bounds` / `move` calls; a group moved
# and resized at once (each subview's old rect in its hook), a CalcBounds
# override that sets nothing, a subview destroyed during the owner resize.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "003: bounds and geometry"

HOOK=()
fv.views._changed() { HOOK+=("$1 $2 ${3:-.} $4 $5 $6 $7"); }
fields() {   # V -> REPLY: every field
    local -n __f=${1}_data
    local k
    REPLY=''
    for k in Owner OriginX OriginY SizeX SizeY CursorX CursorY State Options EventMask GrowMode DragMode HelpCtx Current Phase EndState LockFlag; do
        if [[ -n ${__f[$k]+x} ]]; then REPLY+="$k=${__f[$k]} "; fi
    done
    REPLY=${REPLY% }
}
cache() { REPLY="${__FV_VW_AX[$1]} ${__FV_VW_AY[$1]} / ${__FV_VW_C1[$1]} ${__FV_VW_C2[$1]} ${__FV_VW_C3[$1]} ${__FV_VW_C4[$1]}"; }

TView.new v 10 5 50 20
fields v
fvw_check "TView.new v 10 5 50 20 = FV Init(R.Assign(10,5,50,20)): 40x15 and FV's defaults (State sfVisible, EventMask evMouseDown+evKeyDown+evCommand, DragMode dmLimitLoY)" \
    "Owner= OriginX=10 OriginY=5 SizeX=40 SizeY=15 CursorX=0 CursorY=0 State=1 Options=0 EventMask=273 GrowMode=0 DragMode=32 HelpCtx=0" "$REPLY"
TGroup.new g 0 1 80 24
fields g
fvw_check "TGroup.new: TView's + Options ofSelectable+ofBuffered, EventMask \$FFFF, Current '', Phase phFocused, EndState '', LockFlag 0" \
    "Owner= OriginX=0 OriginY=1 SizeX=80 SizeY=23 CursorX=0 CursorY=0 State=1 Options=65 EventMask=65535 GrowMode=0 DragMode=32 HelpCtx=0 Current= Phase=phFocused EndState= LockFlag=0" "$REPLY"

kt_test_start "bounds as typed: negative, leading zeros (decimal), an inverted rect (negative size), MaxViewWidth (1024) caps the width"
TView.new n -5 -3 007 08; fv.views.getBounds n; a=$RESULT
TView.new inv 10 10 5 2; fv.views.getBounds inv; b=$RESULT
TView.new wide 0 0 3000 2; fv.views.getExtent wide; c=$RESULT
if [[ $a == '-5 -3 7 8' && $b == '10 10 5 2' && $c == '0 0 1024 2' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "getBounds / getExtent: RESULT and FV_RECT_AX/_AY/_BX/_BY"
fv.views.getBounds v; a="$RESULT|$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
fv.views.getExtent v; b="$RESULT|$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
if [[ $a == '10 5 50 20|10 5 50 20' && $b == '0 0 40 15|0 0 40 15' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b]"; fi

kt_test_start "the cache: a view without an owner = its own rect; inserted = absolute origin and the clip cut by the owners"
cache v; a=$REPLY
TGroup.new w 70 10 100 30
fv.views.insert g w
TView.new lab 2 15 20 25
fv.views.insert w lab
cache w; b=$REPLY; cache lab; c=$REPLY
# w: abs 70 11, rect 70..100 x 11..31, owner clip 0 1 80 24 -> 70 11 80 24
# lab: abs 72 26, rect 72..90 x 26..36, w's clip -> 72 26 80 24 -> empty (C4 = C2)
if [[ $a == '10 5 / 10 5 50 20' && $b == '70 11 / 70 11 80 24' && $c == '72 26 / 72 26 80 26' ]]; then kt_test_pass "ok"
else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "moveTo the window: its subtree's cache follows; hook move = old ∪ new (after the view's own bounds call)"
HOOK=()
fv.views.moveTo w 5 2
cache w; a=$REPLY; cache lab; b=$REPLY
if [[ $a == '5 3 / 5 3 35 23' && $b == '7 18 / 7 18 25 23' \
   && "${HOOK[*]}" == 'bounds w g 5 3 100 31 move w g 5 3 100 31' ]]; then kt_test_pass "ok"
else kt_test_fail "[$a] [$b] hook=[${HOOK[*]}]"; fi

kt_test_start "locate: the size clamped to SizeLimits (Max = the owner's size); unchanged bounds = no ChangeBounds, no hook"
fv.views.locate w 1 1 500 400; fv.views.getBounds w; a=$RESULT
HOOK=()
fv.views.locate w 1 1 81 24; b=${#HOOK[@]}
fv.views.locate w 1 1 1 1; fv.views.getBounds w; c=$RESULT
fv.views.locate v -10 -10 99999 99999; fv.views.getBounds v; d=$RESULT
if [[ $a == '1 1 81 24' && $b == 0 && $c == '1 1 1 1' && $d == '-10 -10 1014 99999' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] hooks=$b [$c] [$d]"; fi

kt_test_start "growTo: from the origin; SizeLimits answers in FV_MIN_* / FV_MAX_* (no owner: high(Sw_Integer))"
fv.views.locate w 5 2 35 22
fv.views.growTo w 10 4; fv.views.getBounds w; a=$RESULT
w.SizeLimits; b="$FV_MIN_X $FV_MIN_Y $FV_MAX_X $FV_MAX_Y"
v.SizeLimits; c="$FV_MIN_X $FV_MIN_Y $FV_MAX_X $FV_MAX_Y"
if [[ $a == '5 2 15 6' && $b == '0 0 80 23' && $c == '0 0 2147483647 2147483647' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "centring at insert: ofCenterX / ofCenterY (FV div, toward zero; also a view wider than the group)"
TGroup.new box 0 0 21 11
TView.new cx 0 3 4 4; cx_data[Options]=$FV_OF_CENTERX
TView.new cy 1 0 2 3; cy_data[Options]=$FV_OF_CENTERY
TView.new cc 0 0 30 2; cc_data[Options]=$FV_OF_CENTERED
fv.views.insert box cx; fv.views.insert box cy; fv.views.insert box cc
fv.views.getBounds cx; a=$RESULT; fv.views.getBounds cy; b=$RESULT; fv.views.getBounds cc; c=$RESULT
if [[ $a == '8 3 12 4' && $b == '1 4 2 7' && $c == '-4 4 26 6' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

# --- owner resize: GrowMode -------------------------------------------------
TGroup.new o 0 0 40 20
mk() {   # NAME AX AY BX BY GROWMODE
    TView.new "$1" "$2" "$3" "$4" "$5"
    local -n __d=${1}_data
    __d[GrowMode]=$6
    fv.views.insert o "$1"
}
mk g0 1 1 11 6 0
mk glx 1 1 11 6 $FV_GF_GROWLOX
mk ghx 1 1 11 6 $FV_GF_GROWHIX
mk gly 1 1 11 6 $FV_GF_GROWLOY
mk ghy 1 1 11 6 $FV_GF_GROWHIY
mk gall 1 1 11 6 $FV_GF_GROWALL
mk grel 10 5 30 15 $(( FV_GF_GROWALL | FV_GF_GROWREL ))
mk gst 0 19 40 20 $(( FV_GF_GROWLOY | FV_GF_GROWHIX | FV_GF_GROWHIY ))
kt_test_start "changeBounds of the owner +20 x +10: every subview by its GrowMode (FV CalcBounds; gfGrowRel scales: I := (I*S + (S-D) shr 1) div (S-D))"
HOOK=()
fv.views.changeBounds o 0 0 60 30
out=''
for k in g0 glx ghx gly ghy gall grel gst; do fv.views.getBounds "$k"; out+="$k:$RESULT|"; done
# grel: x (10*60 + 40>>1) div 40 = 15, (30*60 + 20) div 40 = 45; y (5*30 + 20>>1) div 20 = 8, (15*30 + 10) div 20 = 23;
# glx / gly: the low edge moved past the high one -> the size clamped to 0 (FV Range)
want='g0:1 1 11 6|glx:21 1 21 6|ghx:1 1 31 6|gly:1 11 11 11|ghy:1 1 11 16|gall:21 11 31 16|grel:15 8 45 23|gst:0 29 60 30|'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi
fvw_check "the hook: each subview's own bounds call (front to back), then the group's (old ∪ new)" \
    "bounds gst o 0 19 60 30|bounds grel o 10 5 45 23|bounds gall o 1 1 31 16|bounds ghy o 1 1 11 16|bounds gly o 1 1 11 11|bounds ghx o 1 1 31 6|bounds glx o 1 1 21 6|bounds g0 o 1 1 11 6|bounds o . 0 0 60 30" \
    "$(IFS='|'; echo "${HOOK[*]}")"

kt_test_start "glx with a negative size after GrowLoX: the size clamped to SizeLimits' minimum 0 (FV Range)"
fv.views.getExtent glx
if [[ $RESULT == '0 0 0 5' ]]; then kt_test_pass "ok"; else kt_test_fail "$RESULT"; fi

kt_test_start "a group resize without a size change (a move): SetBounds + one bounds hook, the subviews untouched"
HOOK=()
fv.views.changeBounds o 3 4 63 34
fv.views.getBounds g0; a=$RESULT; cache g0; b=$REPLY
if [[ $a == '1 1 11 6' && $b == '4 5 / 4 5 14 10' && "${HOOK[*]}" == 'bounds o . 0 0 63 34' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] hook=[${HOOK[*]}]"; fi

kt_test_start "gfGrowRel with the owner's old size 0 (S = D): the edge becomes 1 (FV's guard, no division by zero)"
TGroup.new z 0 0 0 0
TView.new zr 0 0 0 0; zr_data[GrowMode]=$(( FV_GF_GROWALL | FV_GF_GROWREL )); fv.views.insert z zr
fv.views.changeBounds z 0 0 10 10; r=$?
fv.views.getBounds zr
if [[ $r == 0 && $RESULT == '1 1 1 1' ]]; then kt_test_pass "ok"; else kt_test_fail "rc=$r $RESULT"; fi

kt_test_start "CalcBounds answers in FV_RECT_* and leaves the bounds; GrowMode 0 or no owner = the bounds as they are; the width capped at MaxViewWidth"
fv.views.getBounds ghx; before=$RESULT
ghx.CalcBounds 5 5; a="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
fv.views.getBounds ghx; after=$RESULT
g0.CalcBounds 5 5; b="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
v.CalcBounds 5 5; c="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
TGroup.new big 0 0 1000 10; TView.new bw 0 0 1000 1; bw_data[GrowMode]=$FV_GF_GROWHIX; fv.views.insert big bw
bw.CalcBounds 500 0; d="$FV_RECT_AX $FV_RECT_BX"
if [[ $a == '1 1 36 6' && $before == "$after" && $b == '1 1 11 6' && $c == '-10 -10 1014 99999' && $d == '0 1000' ]]; then kt_test_pass "ok"
else kt_test_fail "[$a] [$before]/[$after] [$b] [$c] [$d]"; fi

kt_test_start "the detached subtree: after delete, the view's cache is relative to nothing (its own rect)"
fv.views.delete w lab
cache lab
if [[ $REPLY == '2 15 / 2 15 20 25' ]]; then kt_test_pass "ok"; else kt_test_fail "$REPLY"; fi

kt_test_start "makeLocal / makeGlobal: RESULT and FV_POINT_X/_Y through the cached absolute origin"
fv.views.insert w lab   # w at 5 2 (abs 5 3) -> lab abs 7 18
fv.views.makeLocal lab 10 20; a="$RESULT|$FV_POINT_X $FV_POINT_Y"
fv.views.makeGlobal lab 0 0; b="$RESULT|$FV_POINT_X $FV_POINT_Y"
fv.views.makeLocal lab 0 0; c=$RESULT
if [[ $a == '3 2|3 2' && $b == '7 18|7 18' && $c == '-7 -18' ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "mouseInView: inside / on each edge / outside (B exclusive)"
out=''
for p in '7 18' '24 18' '25 18' '6 18' '7 27' '7 28' '7 17'; do
    if fv.views.mouseInView lab $p; then out+=1; else out+=0; fi
done
if [[ $out == 1100100 ]]; then kt_test_pass "ok"; else kt_test_fail "$out"; fi

kt_test_start "GetHelpCtx (func): HelpCtx; hcDragging while sfDragging; a group asks Current first, then its own"
lab_data[HelpCtx]=7; w_data[HelpCtx]=3
lab_data[Options]=$FV_OF_SELECTABLE; fv.views.delete w lab; fv.views.insert w lab
RESULT=x; lab.GetHelpCtx; a=$RESULT
RESULT=x; w.GetHelpCtx; b=$RESULT
lab_data[State]=$(( lab_data[State] | FV_SF_DRAGGING )); RESULT=x; w.GetHelpCtx; c=$RESULT
lab_data[State]=$(( lab_data[State] & ~FV_SF_DRAGGING )); lab_data[HelpCtx]=0; RESULT=x; w.GetHelpCtx; d=$RESULT
if [[ $a$b$c$d == 7713 ]]; then kt_test_pass "ok"; else kt_test_fail "$a $b $c $d"; fi

kt_test_start "bad numbers: rc 2, RESULT '', nothing changed (non-digits, '+1', '--1', 10 digits, empty, an expression)"
fv.views.getBounds w; before=$RESULT
out=''
for bad in x '+1' '--1' 1234567890 '' '1+1' '$(echo 1)' 'a[0]' '0x10'; do
    RESULT=y; fv.views.moveTo w "$bad" 1; out+="$?$RESULT"
    RESULT=y; fv.views.locate w 0 0 1 "$bad"; out+="$?$RESULT"
done
RESULT=y; fv.views.growTo w 1; out+=" $?$RESULT"
RESULT=y; fv.views.makeLocal w 1; out+="$?$RESULT"
RESULT=y; fv.views.changeBounds w 1 2 3 x; out+="$?$RESULT"
RESULT=y; fv.views.mouseInView w 1 x; out+="$?$RESULT"
fv.views.getBounds w
want="$(printf '22%.0s' 1 2 3 4 5 6 7 8 9) 2222"
if [[ $out == "$want" && $RESULT == "$before" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want] bounds [$RESULT] vs [$before]"; fi

kt_test_start "the constructor: bounds that are not four integers -> rc 2 and one Error line; the name is no live view"
out=$(TView.new badb 1 2 3 2>&1); r=$?
out2=$(TView.new badc 1 2 3 x 2>&1); r2=$?
if [[ $r == 2 && $r2 == 2 && $out == 'Error: fv.views: TView.Create: '\''badb'\'': the bounds must be four integers AX AY BX BY (got: 1 2 3)' && $out2 == *'Error: fv.views:'* ]]; then kt_test_pass "ok"
else kt_test_fail "rc=$r/$r2 [$out] [$out2]"; fi


kt_test_start "a group moved and resized at once: each subview's bounds hook gets ITS old rect ∪ its new one (review 2c-1 #2); the subtree cache ends consistent"
TGroup.new RP 0 0 80 25
TGroup.new RG 10 5 50 20
TView.new RK 2 2 12 6; RK_data[GrowMode]=$FV_GF_GROWHIX
TView.new RJ 1 1 3 3
fv.views.insert RP RG; fv.views.insert RG RK; fv.views.insert RG RJ
HOOK=()
fv.views.changeBounds RG 20 8 65 23
h1=$(IFS='|'; echo "${HOOK[*]}")
cache RK; c1=$REPLY; cache RJ; c2=$REPLY
# RK: old abs 12 7 22 11, new 22 10 37 14 (GrowHiX +5); RJ (GrowMode 0): old 11 6 13 8, new 21 9 23 11
want='bounds RJ RG 11 6 23 11|bounds RK RG 12 7 37 14|bounds RG RP 10 5 65 23'
if [[ $h1 == "$want" && $c1 == '22 10 / 22 10 37 14' && $c2 == '21 9 / 21 9 23 11' ]]; then kt_test_pass "ok"
else kt_test_fail "hook [$h1] want [$want] cache [$c1] [$c2]"; fi

kt_test_start "locate of that group to 0 0 30 10: the subviews' hooks span old (moved group) ∪ new; then the move hook"
HOOK=()
fv.views.locate RG 0 0 30 10
h1=$(IFS='|'; echo "${HOOK[*]}")
cache RK; c1=$REPLY
# RG 45x15 -> 30x10 (-15, -5); RK 2 2 17 6 -> BX 2 (size 0): old abs 22 10 37 14, new 2 2 2 6
want='bounds RJ RG 1 1 23 11|bounds RK RG 2 2 37 14|bounds RG RP 0 0 65 23|move RG RP 0 0 65 23'
if [[ $h1 == "$want" && $c1 == '2 2 / 2 2 2 6' ]]; then kt_test_pass "ok"; else kt_test_fail "hook [$h1] want [$want] cache [$c1]"; fi
RP.delete

kt_test_start "an owner resize: a CalcBounds override that sets nothing keeps its view in place; a subview destroyed by an earlier one's ChangeBounds is skipped (review 2c-1 #6)"
class TStay : TView
    public
        override proc CalcBounds
end
TStay.CalcBounds() { :; }
build TStay
class TKiller : TView
    public
        override proc ChangeBounds
end
TKiller.ChangeBounds() { inherited ChangeBounds "$@"; if declare -F victim.delete >/dev/null; then victim.delete; fi; }
build TKiller
TGroup.new og 0 0 40 20
TView.new victim 0 0 5 5; victim_data[GrowMode]=$FV_GF_GROWALL
TStay.new stay 3 3 8 8; stay_data[GrowMode]=$FV_GF_GROWALL
TView.new prev 1 1 2 2; prev_data[GrowMode]=$FV_GF_GROWALL
TKiller.new killer 0 0 4 4; killer_data[GrowMode]=$FV_GF_GROWHIX
# back to front: victim stay prev killer -> ForEach order killer, prev, stay, victim
fv.views.insert og victim; fv.views.insert og stay; fv.views.insert og prev; fv.views.insert og killer
fv.views.changeBounds og 0 0 50 25 2>"$FVW_TMP/kid.err"; r=$?
fv.views.getBounds stay; a=$RESULT; fv.views.getBounds prev; b=$RESULT; fv.views.getBounds killer; c=$RESULT
fvw_tree og
if [[ $r == 0 && ! -s $FVW_TMP/kid.err && $a == '3 3 8 8' && $b == '11 6 12 7' && $c == '0 0 14 4' && $REPLY == 'og[stay prev killer]' ]]; then kt_test_pass "ok"
else kt_test_fail "rc=$r err=[$(<"$FVW_TMP/kid.err")] stay=[$a] prev=[$b] killer=[$c] tree=$REPLY"; fi
og.delete

kt_test_log "003_Geometry.sh completed"
