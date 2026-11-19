#!/usr/bin/env bash
# 019_Palette.sh - the palette model (design §1.9):
#   * the app palette (the root mapping; a stub until fv.app, stage 2f) is
#     FV's CAppColor: entry i is the fv.video symbol whose default colours
#     are CAppColor's byte i (the 127 bytes of app.inc, hand-copied here);
#   * the resolution chain: a view's GetPalette indexes its owner's resolved
#     palette, '' (TView's) maps as the owner does, the root maps into the
#     app palette; TFrame (CFrame 1 1 2 2 3) inside a blue / cyan / gray
#     window gives CAppColor 8.. / 16.. / 24..; an index 0, past the
#     palette below or not a number gives ErrorAttr's symbol (0);
#   * the cache: resolved once per view (GetPalette dispatched once for a
#     user override, however often it draws), dropped for the subtree on
#     delete / insert into another owner and by resetPalette V / resetPalette;
#     a changed Palette field shows after resetPalette; RESULT kept by the
#     resolution; refusals rc 2.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "019: palettes"

# FV app.inc CAppColor, the 127 attribute bytes ($BF: B background, F foreground)
CAPP=(71 70 78 74 20 28 24 17 1F 1A 31 31 1E 71 1F 37 3F 3A 13 13 3E 21 3F 70 7F 7A 13 13 70 7F 7E
      70 7F 7A 13 13 70 70 7F 7E 20 2B 2F 78 2E 70 30 3F 3E 1F 2F 1A 20 72 31 31 30 2F 3E 31 13 38 31
      17 1F 1A 71 71 1E 17 1F 1E 20 2B 2F 78 2E 10 30 3F 3E 70 2F 7A 20 12 31 31 30 2F 3E 31 13 38 31
      37 3F 3A 13 13 3E 30 3F 3E 20 2B 2F 78 2E 30 70 7F 7E 1F 2F 1A 20 32 31 71 70 2F 7E 71 13 38 71)
DOS=(0 4 2 6 1 5 3 7 8 12 10 14 9 13 11 15)

fvw_screen 40 10

kt_test_start "the app palette: 127 entries, entry i's symbol has CAppColor byte i's colours in fv.video's default palette"
bad=''
(( ${#CAPP[@]} == 127 )) || bad+=" CAPP has ${#CAPP[@]}"
(( ${#__FV_VW_APAL} == 127 )) || bad+=" APAL has ${#__FV_VW_APAL}"
for (( i = 0; i < 127; i++ )); do
    b=${CAPP[i]}
    want="${DOS[16#${b:1:1}]} ${DOS[16#${b:0:1}]} 0"
    s=${__FV_VW_APAL:i:1}
    [[ ${__FV_VS_PAL[$s]-} == "$want" ]] || bad+=" entry $(( i + 1 )): $s=[${__FV_VS_PAL[$s]-}] want [$want]"
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

fvw_classes
TGroup.new root 0 0 40 10
TView.new lone 0 0 1 1

kt_test_start "the chain: a root without a palette maps into the app palette; TView's '' maps as its owner"
out=''
for i in 1 2 8 127; do fv.views.getColor lone "$i"; out+="$RESULT"; done
TView.new kid 0 0 1 1
fv.views.insert root kid
for i in 1 8; do fv.views.getColor kid "$i"; out+="$RESULT"; done
if [[ $out == "${__FV_VW_APAL:0:1}${__FV_VW_APAL:1:1}${__FV_VW_APAL:7:1}${__FV_VW_APAL:126:1}${__FV_VW_APAL:0:1}${__FV_VW_APAL:7:1}" && $out == 128118 ]]; then kt_test_pass "ok"
else kt_test_fail "[$out]"; fi

kt_test_start "TFrame in a blue / cyan / gray window: CFrame -> the window's 8.. / 16.. / 24.. -> CAppColor's symbols"
out=''
for p in 0 1 2; do
    TTWin.new "pw$p" 0 0 10 5
    declare -n pd="pw${p}_data"; pd[Palette]=$p; unset -n pd
    TFrame.new "pf$p" 0 0 10 5
    fv.views.insert "pw$p" "pf$p"
    fv.views.insert root "pw$p"
    for i in 1 2 3 4 5; do fv.views.getColor "pf$p" "$i"; out+="$RESULT"; done
    out+=' '
done
# blue: 8 8 9 9 10 -> $17 $17 $1F $1F $1A; cyan: 16 16 17 17 18 -> $37 $37 $3F $3F $3A; gray 24.. -> $70 $70 $7F $7F $7A
want="${__FV_VW_APAL:7:1}${__FV_VW_APAL:7:1}${__FV_VW_APAL:8:1}${__FV_VW_APAL:8:1}${__FV_VW_APAL:9:1} "
want+="${__FV_VW_APAL:15:1}${__FV_VW_APAL:15:1}${__FV_VW_APAL:16:1}${__FV_VW_APAL:16:1}${__FV_VW_APAL:17:1} "
want+="${__FV_VW_APAL:23:1}${__FV_VW_APAL:23:1}${__FV_VW_APAL:24:1}${__FV_VW_APAL:24:1}${__FV_VW_APAL:25:1} "
if [[ $out == "$want" && $out == '8899A DDEEF 22JJK ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out] want [$want]"; fi

class TOdd : TView
    public
        override func GetPalette
end
TOdd.GetPalette() { RESULT='1 0 200 x 3'; }
build TOdd
kt_test_start "an index 0, past the palette below or not a number: ErrorAttr's symbol (0); getColor past the view's palette too"
TOdd.new odd 0 0 1 1
fv.views.insert pw0 odd
out=''
for i in 1 2 3 4 5 6; do fv.views.getColor odd "$i"; out+="$RESULT"; done
if [[ $out == "${__FV_VW_APAL:7:1}000${__FV_VW_APAL:9:1}0" ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "the cache: a user GetPalette resolves once (1 dispatch per view) however often the view draws; RESULT kept"
fvw_expose root
fv.views.resetPalette
fvw_count_on; FVW_CALLS=0
RESULT=keep
fv.views.drawView pw0; n1=$FVW_CALLS; fv.views.drawView pw0; fv.views.drawView pw0
n=$(( FVW_CALLS - n1 )) r=$RESULT
fvw_count_off
if [[ $n1 == 4 && $n == 0 && $r == keep && -n ${__FV_VW_PAL[pw0]+x} && ${__FV_VW_PAL[odd]} == "${__FV_VW_APAL:7:1}000${__FV_VW_APAL:9:1}" ]]; then kt_test_pass "ok (first draw $n1: pw0, odd and the windows pw1, pw2 painted over it; then 0)"
else kt_test_fail "calls=$n1+$n RESULT=$r pal=[${__FV_VW_PAL[pw0]-unset}] [${__FV_VW_PAL[odd]-unset}]"; fi

kt_test_start "a changed Palette field shows after resetPalette V (the subtree re-resolved), not before"
pw0_data[Palette]=2
fv.views.getColor pf0 1; a=$RESULT
fv.views.resetPalette pw0
b="${__FV_VW_PAL[pw0]-unset} ${__FV_VW_PAL[pf0]-unset}"
fv.views.getColor pf0 1; c=$RESULT
if [[ $a == 8 && $b == 'unset unset' && $c == 2 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c]"; fi

kt_test_start "delete and insert into another owner drop the subtree's cache: the frame takes the new window's colours"
fv.views.getColor pf1 1; a=$RESULT
fv.views.delete pw1 pf1
b=${__FV_VW_PAL[pf1]-unset}
fv.views.getColor pf1 1; c=$RESULT
fv.views.insert pw2 pf1
fv.views.getColor pf1 1; d=$RESULT
if [[ $a == D && $b == unset && $c == 1 && $d == 2 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] [$c] [$d]"; fi

kt_test_start "resetPalette with no argument drops every cache; refusals: not a view, a wrong count, a bad index (rc 2)"
fv.views.getColor kid 1
fv.views.resetPalette
a=${#__FV_VW_PAL[@]}
out=''
fv.views.resetPalette nosuch; out+="$?"; fv.views.resetPalette a b; out+="$?"
fv.views.getColor kid; out+="$?"; fv.views.getColor kid -1; out+="$?"; fv.views.getColor kid 99999; out+="$?"
if [[ $a == 0 && $out == 22222 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$out]"; fi

root.delete; lone.delete

# D21: the GetPalette answer is split without a here-string: the first line
# only, at blanks only (a tab stays inside its word), no globbing (a '*' in
# a folder holding a file named 7 is no index 7), the caller's set -f kept
class TPOdd : TView
    public
        override func GetPalette
end
TPOdd.GetPalette() { RESULT=$PODD; }
build TPOdd
TPOdd.new podd 0 0 2 1
kt_test_start "GetPalette's answer: the first line, split at blanks, a tab inside a word, no globbing; set -f state kept"
(
    cd "$FVW_TMP" && : > ./7 && : > ./3
    PODD=$'  2  *  4\t5  ?  3 \n9 9' fv.views._pal podd
    a=${__FV_VW_PAL[podd]}
    set -f; unset '__FV_VW_PAL[podd]'
    PODD=$'*\n' fv.views._pal podd
    b="${__FV_VW_PAL[podd]}:$-"
    printf "%s %s" "$a" "$b" > "$FVW_TMP/podd.out"
)
r=$(<"$FVW_TMP/podd.out")
want="2${__FV_VW_ERRSYM}${__FV_VW_ERRSYM}${__FV_VW_ERRSYM}3 ${__FV_VW_ERRSYM}:"
if [[ $r == "$want"*f* ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] want [$want...f...]"; fi
podd.delete
kt_test_log "019_Palette.sh completed"
