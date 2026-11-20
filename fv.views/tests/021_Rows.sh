#!/usr/bin/env bash
# 021_Rows.sh - fv.views.writeLines X Y TEXTS ATTRS (D21 stage E: many rows
# in one call, over fv.video's friend entry _wrows):
#   * A/B: a drawPart painter that writes rows with one writeLines call
#     leaves the same screen, rc and RESULT as one `writeLine X Y+k 1
#     TEXTS[k] ATTRS[k]` per index k (rc 2 / RESULT '' when a row is
#     refused, else the widest row's RESULT): a seeded random mix of narrow,
#     Cyrillic, wide and emoji rows, a combining mark, a control character,
#     empty rows, sparse arrays, missing ATTRS elements, ATTRS of another
#     length, bad symbols; views reaching past their owner and off the
#     screen; negative X / Y (the checked path); painted row ranges
#     (FV_CLIP_*); rows with wide cells under them; ASCII mode; 40x12 and
#     200x50;
#   * a Draw override that draws its rows with writeLines (drawView) ==
#     the per-row Draw; RESULT and rc in a Draw;
#   * refusals, rc 2 with RESULT '' and nothing written: outside a Draw,
#     the count, X / Y not integers, names that are no identifiers, start
#     with __fv (any case) or are RESULT, an associative array; a row
#     refused: rc 2, RESULT '', the other rows written; under set -eu;
#   * writeRows X Y W TEXTS SYMS (P3 10.2) = fv.video._wrowsu at the view's
#     origin inside a drawPart (random cases); its refusals (count, X, W,
#     names, outside a Draw), a refused row, a wide pair cut at W.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "021: writeLines (D21 stage E)"
unset FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81'
POOL=('plain text' 'Привет, мир' '─┐ box ┌─' "${HAN}x${JI}" "a${EMO}b" "e${ACU}z" '' $'ctl\x01x' 'x' \
    'a much longer row of plain ASCII text that runs past the view' "$JI$JI$JI$JI")
SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
NARROW=('plain text' 'Привет, мир' '─┐ box ┌─' 'x')
printf -v BLANKS '%*s' 200 ''

# attrs TEXT KIND -> REPLY: KIND 0 the display width in random symbols, 7
# one cell short, 8 one cell long, 9 a bad symbol
attrs() {
    local w i s=''
    fv.video.strWidth "$1"; w=$RESULT
    case $2 in 7) w=$(( w > 0 ? w - 1 : 1 )) ;; 8) w=$(( w + 1 )) ;; esac
    for (( i = 0; i < w; i++ )); do s+=${SYMS:RANDOM % 62:1}; done
    if (( $2 == 9 )); then s+='#'; fi
    REPLY=$s
}
# the painters: FN V X Y (rows from RT / RA); OUTP = "rc[RESULT]"
p_one() {
    local k r=0 m=0
    for k in "${!RT[@]}"; do
        if fv.views.writeLine "$2" "$(( $3 + k ))" 1 "${RT[k]}" "${RA[k]-}"; then
            if (( RESULT > m )); then m=$RESULT; fi
        else r=1; fi
    done
    if (( r )); then OUTP='2[]'; else OUTP="0[$m]"; fi
}
p_all() {
    fv.views.writeLines "$2" "$3" RT RA; OUTP="$?[$RESULT]"
}
# the ground: every row of the screen pre-painted, wide characters and a
# marker on some rows (shown once: nothing damaged)
ground() {
    local y
    fv.video.fillRect 0 0 "$FV_SCREEN_W" "$FV_SCREEN_H" 1 '░'
    for (( y = 1; y < FV_SCREEN_H; y += 3 )); do fv.video.writeStr $(( y % 7 )) "$y" "${HAN}${JI}a${HAN}e${ACU}${EMO}" 2; done
    fv.video.updateScreen
}

# --- A/B: writeLines = writeLine per row ---------------------------------------------
RANDOM=2112
fail='' n=0 nref=0
for (( i = 0; i < 160; i++ )); do
    if (( i % 5 == 4 )); then W=200 H=50; else W=40 H=12; fi
    if (( i % 7 == 6 )); then FV_ASCII=1; else unset FV_ASCII; fi
    fvw_screen "$W" "$H"
    TGroup.new root 0 0 "$W" "$H"
    fvw_expose root
    gx=$(( RANDOM % 10 - 3 )) gy=$(( RANDOM % 6 - 2 ))
    TGroup.new g "$gx" "$gy" $(( gx + 6 + RANDOM % (W - 4) )) $(( gy + 3 + RANDOM % H ))
    vx=$(( RANDOM % 8 - 2 )) vy=$(( RANDOM % 6 - 2 ))
    TView.new v "$vx" "$vy" $(( vx + 1 + RANDOM % 50 )) $(( vy + 1 + RANDOM % 16 ))
    fv.views.insert root g; fv.views.insert g v
    x=$(( RANDOM % 14 - 4 )) y=$(( RANDOM % 8 - 3 ))
    y1=$(( RANDOM % 6 - 1 )) y2=$(( y1 + RANDOM % 14 ))
    RT=() RA=() K=()
    nr=$(( RANDOM % 14 )) k=$(( RANDOM % 3 ))
    for (( j = 0; j < nr; j++ )); do
        k=$(( k + 1 + (RANDOM % 5 == 0 ? RANDOM % 3 : 0) ))
        RT[k]=${POOL[RANDOM % ${#POOL[@]}]} K[k]=$(( RANDOM % 40 ))
    done
    for k in "${!K[@]}"; do
        if (( K[k] < 36 )); then attrs "${RT[k]}" 0; RA[k]=$REPLY
        elif (( K[k] > 36 )); then attrs "${RT[k]}" $(( K[k] - 30 )); RA[k]=$REPLY; fi   # (36: RA[k] missing)
    done
    ground
    OUTP=''; fv.views.drawPart v p_one "$y1" "$y2" "$x" "$y" 2>/dev/null; want=$OUTP
    fvw_snap; s1=$REPLY
    ground
    OUTP=''; fv.views.drawPart v p_all "$y1" "$y2" "$x" "$y" 2>/dev/null; got=$OUTP
    fvw_snap
    n=$(( n + 1 ))
    if [[ $want == 2* ]]; then nref=$(( nref + 1 )); fi
    if [[ $REPLY != "$s1" || $got != "$want" ]]; then fail+=" [i=$i ${W}x$H ascii=${FV_ASCII-0} g=$gx,$gy v=$vx,$vy x=$x y=$y rows=$y1-$y2 idx=${!RT[*]} got=$got want=$want]"; fi
    root.delete
done
unset FV_ASCII
fvw_check "writeLines = one writeLine per index inside a drawPart: $n random cases ($nref with a refused row; 40x12 and 200x50, ASCII mode, clipped views, negative X / Y, sparse arrays, rows with wide cells)" "" "$fail"

# --- a Draw override ------------------------------------------------------------------
class TRowsOne : TView
    public
        override proc Draw
end
TRowsOne.Draw() {
    local y s
    for (( y = 0; y < SizeY; y++ )); do
        s=" item $y ${NARROW[y % 4]}"; s+=${BLANKS:0:SizeX-${#s}}   # (printf pads by bytes in some bashes)
        fv.views.writeLine 0 "$y" 1 "${s:0:SizeX}" "${FVW_RA[$SizeX]}"
    done
}
build TRowsOne
class TRowsAll : TView
    public
        override proc Draw
end
TRowsAll.Draw() {
    local y s
    local -a tt=() aa=()
    for (( y = 0; y < SizeY; y++ )); do
        s=" item $y ${NARROW[y % 4]}"; s+=${BLANKS:0:SizeX-${#s}}   # (printf pads by bytes in some bashes)
        tt[y]=${s:0:SizeX} aa[y]=${FVW_RA[$SizeX]}
    done
    fv.views.writeLines 0 0 tt aa; DRAWR="$?[$RESULT]"
}
build TRowsAll
declare -A FVW_RA=()
printf -v s '%*s' 30 ''; FVW_RA[30]=${s// /5}
for c in TRowsOne TRowsAll; do
    fvw_screen 40 12
    TGroup.new root 0 0 40 12; fvw_expose root
    TGroup.new g 2 1 38 9
    "$c.new" v -3 -1 27 11
    fv.views.insert root g; fv.views.insert g v
    ground
    DRAWR=''; fv.views.drawView root; fvw_snap
    if [[ $c == TRowsOne ]]; then s1=$REPLY; else s2=$REPLY; fi
    root.delete
done
fvw_check "a Draw override drawing its rows with one writeLines (drawView, the view past its owner on three sides) == the per-row Draw; RESULT 30" "same 0[30]" "$([[ $s1 == "$s2" ]] && printf same) $DRAWR"

# --- refusals -----------------------------------------------------------------------
fvw_screen 20 6
TGroup.new root 0 0 20 6; fvw_expose root
TView.new v 1 1 15 5; fv.views.insert root v
fv.views.drawView root
fvw_snap; s0=$REPLY
RT=(ab cd) RA=(12 34)
declare -A MA=([0]=ab [1]=cd) MI=(['FVW_INJ=1']=ab)   # (MI: a key that arithmetic would run)
unset FVW_INJ
pbad() {
    local -a __fvx=(a) aa=(1)
    OUTP=''
    RESULT=keep; fv.views.writeLines 0 0 RT RA x; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 RT; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines x 0 RT RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 '1+1' RT RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 '' RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 RT 1a; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 'R-T' RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 'RT[0]' RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 __fvx aa; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 RT __FVW_x; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 RESULT RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 MA RA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 RT MA; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeLines 0 0 MI RA; OUTP+="$?[$RESULT]${FVW_INJ-}"
}
fv.views.drawPart v pbad 0 4
fvw_snap
fvw_check "malformed calls inside a Draw: rc 2, RESULT '', nothing written (count, X / Y, names: empty, a digit first, '-', a subscript, __fv / __FV prefixes, RESULT, associative arrays: no key evaluated)" \
    "2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[] same" "$OUTP $([[ $REPLY == "$s0" ]] && printf same)"
RESULT=keep; fv.views.writeLines 0 0 RT RA; r="$?[$RESULT]"
fvw_snap
fvw_check "outside a Draw: rc 2, RESULT '', nothing written" "2[] same" "$r $([[ $REPLY == "$s0" ]] && printf same)"
pok() {
    local -a t=(aa bb cc dd) a=(11 2 3# 44) e=() n=()
    unset 'n[0]'
    fv.views.writeLines 0 0 t a; OUTP="$?[$RESULT]"
    fv.views.writeLines 0 0 e e; OUTP+="$?[$RESULT]"
    fv.views.writeLines 0 0 nosuch_array nosuch_array; OUTP+="$?[$RESULT]"
    t=(x y) a=(9 9)
    fv.views.writeLines 0 -1 t a; OUTP+="$?[$RESULT]"
}
fv.views.drawPart v pok 0 4 2>/dev/null
r=$OUTP
fvw_cells 1 1 3; r+=" $RESULT"; fvw_cells 1 2 3; r+="|$RESULT"; fvw_cells 1 3 3; r+="|$RESULT"; fvw_cells 1 4 3; r+="|$RESULT"
fvw_check "a refused row: rc 2, RESULT '', the other rows written; no rows: RESULT 0; a negative Y (row -1 above the view: clipped, row 0 written)" \
    "2[]0[0]0[0]0[1] ya |   |   |dd " "$r"
root.delete

# --- writeRows (P3 10.2): fv.video._wrowsu in view coordinates ----------------------------
# p_rows / p_rowsu: FN V X Y W (rows from RT / RS); OUTP = "rc[RESULT]"
p_rows() { fv.views.writeRows "$2" "$3" "$4" RT RS; OUTP="$?[$RESULT]"; }
p_rowsu() { fv.video._wrowsu "$(( FV_DRAW_X + $2 ))" "$(( FV_DRAW_Y + $3 ))" "$4" RT RS; OUTP="$?[$RESULT]"; }
RANDOM=2113
fail='' n=0
for (( i = 0; i < 60; i++ )); do
    if (( i % 5 == 4 )); then W=200 H=50; else W=40 H=12; fi
    if (( i % 7 == 6 )); then FV_ASCII=1; else unset FV_ASCII; fi
    fvw_screen "$W" "$H"
    TGroup.new root 0 0 "$W" "$H"
    fvw_expose root
    vx=$(( RANDOM % 8 - 2 )) vy=$(( RANDOM % 6 - 2 ))
    TView.new v "$vx" "$vy" $(( vx + 1 + RANDOM % 50 )) $(( vy + 1 + RANDOM % 16 ))
    fv.views.insert root v
    x=$(( RANDOM % 14 )) y=$(( RANDOM % 8 )) w=$(( RANDOM % 30 ))
    y1=$(( RANDOM % 6 - 1 )) y2=$(( y1 + RANDOM % 14 ))
    RT=() RS=()
    for (( k = 0; k < RANDOM % 14; k++ )); do
        RT[k]=${POOL[RANDOM % ${#POOL[@]}]}
        if (( RANDOM % 15 )); then RS[k]=${SYMS:RANDOM % 62:1}; else RS[k]='#'; fi
    done
    ground
    OUTP=''; fv.views.drawPart v p_rowsu "$y1" "$y2" "$x" "$y" "$w" 2>/dev/null; want=$OUTP
    fvw_snap; s1=$REPLY
    ground
    OUTP=''; fv.views.drawPart v p_rows "$y1" "$y2" "$x" "$y" "$w" 2>/dev/null; got=$OUTP
    fvw_snap
    n=$(( n + 1 ))
    if [[ $REPLY != "$s1" || $got != "$want" ]]; then fail+=" [i=$i ${W}x$H x=$x y=$y w=$w got=$got want=$want]"; fi
    root.delete
done
unset FV_ASCII
fvw_check "writeRows = fv.video._wrowsu at the view's origin inside a drawPart: $n random cases (cut / padded rows, wide text, a refused symbol, ASCII mode, painted row ranges)" "" "$fail"
fvw_screen 20 6
TGroup.new root 0 0 20 6; fvw_expose root
TView.new v 1 1 15 5; fv.views.insert root v
fv.views.drawView root
fvw_snap; s0=$REPLY
RT=(ab cd) RS=(1 2)
pbadr() {
    local -a __fvx=(a) aa=(1)
    OUTP=''
    RESULT=keep; fv.views.writeRows 0 0 4 RT RS x; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 RT; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows x 0 4 RT RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 -1 RT RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4x RT RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 '' RT RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 '' RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 __fvx aa; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 RT RESULT; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 MA RS; OUTP+="$?[$RESULT]"
    RESULT=keep; fv.views.writeRows 0 0 4 MI RS; OUTP+="$?[$RESULT]${FVW_INJ-}"
}
fv.views.drawPart v pbadr 0 4
fvw_snap
fvw_check "writeRows: malformed calls inside a Draw: rc 2, RESULT '', nothing written (count, X, W negative / not digits / empty, names, associative arrays: no key evaluated)" \
    "2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[] same" "$OUTP $([[ $REPLY == "$s0" ]] && printf same)"
RESULT=keep; fv.views.writeRows 0 0 4 RT RS; r="$?[$RESULT]"
fvw_snap
fvw_check "writeRows outside a Draw: rc 2, RESULT '', nothing written" "2[] same" "$r $([[ $REPLY == "$s0" ]] && printf same)"
pokr() {
    local -a t=(aa "${HAN}${JI}x" cc dd) s=(1 2 '#' 4) e=()
    fv.views.writeRows 0 0 3 t s; OUTP="$?[$RESULT]"
    fv.views.writeRows 0 0 3 e e; OUTP+="$?[$RESULT]"
    t=(xy) s=(5)
    fv.views.writeRows 1 -1 3 t s; OUTP+="$?[$RESULT]"
}
fv.views.drawPart v pokr 0 4 2>/dev/null
r=$OUTP
fvw_cells 1 1 4; r+=" $RESULT"; fvw_cells 1 2 4; r+="|$RESULT"; fvw_cells 1 3 4; r+="|$RESULT"; fvw_cells 1 4 4; r+="|$RESULT"
fvw_check "writeRows: a refused row (rc 2, RESULT '', the others written), a wide pair cut at W 3, no rows RESULT 0, a negative Y (the checked path)" \
    "2[]0[0]0[3] aa  |${HAN}   |    |dd  " "$r"
root.delete

kt_test_start "under set -eu: writeLines in a Draw (plain, in if / ||, a refused call, an unset name), no error output"
out=$("$BASH" -c "set -eu
source '$FVW_TESTS_DIR/../fv.views.sh'
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o FV_SCREEN_W=20 FV_SCREEN_H=5; fv.video.initScreen
TGroup.new root 0 0 20 5; root_data[State]=\$(( root_data[State] | FV_SF_EXPOSED ))
TView.new v 0 0 20 5; fv.views.insert root v
pe() {
    local -a t=(ab 'жук') a=(12 345)
    fv.views.writeLines 0 0 t a
    if fv.views.writeLines 0 2 t; then exit 9; fi
    fv.views.writeLines 0 3 nothing_here nothing_here || exit 8
    t[1]=x
    fv.views.writeLines 1 3 t a || r=\$?
}
r=''
fv.views.drawPart v pe 0 5
fv.video.getRow 1
printf '%s|%s' \"\$r\" \"\$RESULT\"" 2>&1)
if [[ $out == '2|жук                 ' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out]"; fi

kt_test_log "021_Rows.sh completed"
