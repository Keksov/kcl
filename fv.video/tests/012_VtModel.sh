#!/usr/bin/env bash
# 012_VtModel.sh - every frame replayed through the pure-bash VT model
# (fvv_vt.sh), whose grid starts as garbage, and compared with the buffer:
#   * scripted scenes: a framed window with a ~hot~ title, partial updates,
#     clipping, the cursor, a resize, an 80x24 scene;
#   * a seeded random property test: many random writes, clips, palette and
#     depth changes, cursor moves and resizes; after every update the VT grid
#     equals the buffer, the buffer equals an independent per-cell shadow
#     model of the writes, and every few frames the incremental grid equals
#     one forced full repaint into a fresh garbage grid. The text pieces
#     include control characters, DEL, C1, invalid and cut UTF-8 (the shadow
#     knows the cells each becomes). Wide characters, emoji and clusters come
#     with the width-aware model (P1c); 017_Wide checks their frames meanwhile.
# FVV_SEED (default 20261109) picks the random sequence; FVV_FRAMES (default
# 240) the number of frames.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "012: the VT model replays every frame"

unset FV_COLORS FV_ASCII
# frame [force] -> update through the VT model; rc 1 + VT_ERR on a difference
frame() {
    vt_capture fv.video.updateScreen "$@"
    if (( VT_RC )); then VT_ERR="updateScreen rc $VT_RC"; return 1; fi
    vt_feed "$VT_OUT" || return 1
    vt_cmp
}
# same_as_force -> rc 0 when a forced repaint into a fresh garbage grid gives
# the grid the incremental frames built
same_as_force() {
    local a
    vt_grid; a=$VT_GRID
    vt_init "$__FV_VS_W" "$__FV_VS_H"
    frame force || return 1
    vt_grid
    if [[ $VT_GRID != "$a" ]]; then VT_ERR="incremental grid != forced repaint"; return 1; fi
}
scene() {   # TITLE CMDS...
    local t=$1 c
    shift
    kt_test_start "$t"
    for c; do eval "$c"; done
    if frame; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "$VT_ERR"; fi
}

FV_SCREEN_W=40 FV_SCREEN_H=12 fv.video.initScreen
vt_init 40 12
scene "a desktop and a framed window with a ~hot~ title (first frame paints every garbage cell)" \
    "fv.video.fillRect 0 0 40 12 1 '░'" \
    "fv.video.fillRect 5 2 24 7 8" \
    "fv.video.writeStr 5 2 '╔══════════════════════╗' 9" \
    "for y in 3 4 5 6 7; do fv.video.writeStr 5 \$y '║' 9; fv.video.writeStr 28 \$y '║' 9; done" \
    "fv.video.writeStr 5 8 '╚══════════════════════╝' 9" \
    "fv.video.writeCStr 9 2 ' ~F~ile ~E~dit ' 8 C" \
    "fv.video.writeStr 7 4 'Привет, мир!' A"
scene "a partial update: one list row repainted" "fv.video.writeBuf 7 5 'item 1' 'BBBBBB'"
scene "a clipped write and fill inside the window" \
    "fv.video.setClip 6 3 28 8" "fv.video.writeStr 0 6 '0123456789012345678901234567890123456789' E" \
    "fv.video.fillRect 20 2 30 3 G '#'" "fv.video.resetClip"
scene "the cursor shown at 9,4 then moved" "fv.video.setCursorType 2" "fv.video.setCursorPos 9 4"
scene "the cursor moved only" "fv.video.setCursorPos 12 7"
scene "a 16-colour switch and a palette change" "fv.video.setColorDepth 16" "fv.video.definePalette A 202 17 1"
kt_test_start "the incremental grid equals one forced repaint into fresh garbage"
if same_as_force; then kt_test_pass "ok"; else kt_test_fail "$VT_ERR"; fi
scene "resize to 30x8: everything repainted (a fresh garbage grid of the new size)" \
    "FV_SCREEN_W=30 FV_SCREEN_H=8 fv.video.resizeScreen" "vt_init 30 8" "fv.video.writeStr 2 2 'after resize' D"
scene "an 80x24 scene from scratch" \
    "FV_SCREEN_W=80 FV_SCREEN_H=24 fv.video.initScreen" "vt_init 80 24" \
    "for y in {0..23}; do fv.video.writeBuf 0 \$y \"\$(printf '%-80.80s' \"row \$y ─│┌┐└┘ жёлтый текст \$y\")\" \"\$(printf '%080d' 0 | tr 0 \"\${__FV_VS_SYMS:y%31:1}\")\"; done"

# --- the property test -------------------------------------------------------------
SEED=${FVV_SEED:-20261109} FRAMES=${FVV_FRAMES:-240}
# POOL: raw text pieces; POOLC: the cells a write stores for each (control,
# DEL, C1, invalid, cut and overlong sequences -> '?'; no wide character, no
# cluster: their frames are 017_Wide's until P1c). No piece starts with a
# continuation byte except the lone 0x9b, and the cut e2 94 is always
# followed by a blank, so
# no two pieces can join into another character.
POOL=(a b c Q x ' ' ' ' ж ю ё ─ │ ┌ ═ '~' '*' '?' '[' ']' $'\x01' $'\t' é 7 '#'
    $'\x7f' $'\xc2\x85' $'\xff' $'\xe2\x94 ' $'\x9b' $'\xc0\x80')
POOLC=(a b c Q x ' ' ' ' ж ю ё ─ │ ┌ ═ '~' '*' '?' '[' ']' '?' '?' é 7 '#'
    '?' '?' '?' '? ' '?' '?')
SYMS=(a b c d e 0 1 9 U z)
declare -a SH_C=() SH_A=()
SW=0 SH=0 SX1=0 SY1=0 SX2=0 SY2=0
sh_alloc() {
    local i
    SW=$1 SH=$2 SX1=0 SY1=0 SX2=$1 SY2=$2 SH_C=() SH_A=()
    for (( i = 0; i < SW * SH; i++ )); do SH_C[i]=' ' SH_A[i]=0; done
}
sh_put() {   # X Y CHAR SYM - one cell, if inside the clip
    if (( $1 >= SX1 && $1 < SX2 && $2 >= SY1 && $2 < SY2 )); then
        local c=$3
        if [[ $c == $'\x01' || $c == $'\t' ]]; then c='?'; fi
        SH_C[$2 * SW + $1]=$c SH_A[$2 * SW + $1]=$4
    fi
}
rnd() { RN=$(( RANDOM % ($2 - $1 + 1) + $1 )); }
rtext() {   # -> RT, 0..N random pool pieces; RTC = the cells a write stores for them
    local n i k
    rnd 0 "$1"; n=$RN RT='' RTC=''
    for (( i = 0; i < n; i++ )); do k=$(( RANDOM % ${#POOL[@]} )); RT+=${POOL[k]} RTC+=${POOLC[k]}; done
}
rsym() { RS=${SYMS[RANDOM % ${#SYMS[@]}]}; }
sh_cmp() {
    local y x rc ra
    for (( y = 0; y < SH; y++ )); do
        rc='' ra=''
        for (( x = 0; x < SW; x++ )); do rc+=${SH_C[y * SW + x]} ra+=${SH_A[y * SW + x]}; done
        if [[ $rc != "${__FV_VS_CH[y]}" || $ra != "${__FV_VS_AT[y]}" ]]; then
            VT_ERR="shadow row $y [$rc|$ra] != buffer [${__FV_VS_CH[y]}|${__FV_VS_AT[y]}] after: $LAST"
            return 1
        fi
    done
}
op() {
    local x y w h t a b i k c n
    rnd 0 99; k=$RN
    rnd -4 $(( SW + 2 )); x=$RN
    rnd -2 $(( SH + 1 )); y=$RN
    if (( k < 30 )); then
        rtext 12; t=$RT; rsym; a=$RS
        LAST="writeStr $x $y [${t@Q}] $a"
        fv.video.writeStr "$x" "$y" "$t" "$a"
        for (( i = 0; i < ${#RTC}; i++ )); do sh_put $(( x + i )) "$y" "${RTC:i:1}" "$a"; done
    elif (( k < 42 )); then
        rtext 10; t=$RT b=''
        for (( i = 0; i < ${#RTC}; i++ )); do rsym; b+=$RS; done
        LAST="writeBuf $x $y [${t@Q}] $b"
        fv.video.writeBuf "$x" "$y" "$t" "$b"
        for (( i = 0; i < ${#RTC}; i++ )); do sh_put $(( x + i )) "$y" "${RTC:i:1}" "${b:i:1}"; done
    elif (( k < 52 )); then
        rtext 12; t=$RT; rsym; a=$RS; rsym; b=$RS
        LAST="writeCStr $x $y [${t@Q}] $a $b"
        fv.video.writeCStr "$x" "$y" "$t" "$a" "$b"
        n=0
        for (( i = 0; i < ${#RTC}; i++ )); do
            c=${RTC:i:1}
            if [[ $c == '~' ]]; then c=$a a=$b b=$c; continue; fi
            sh_put $(( x + n )) "$y" "$c" "$a"; n=$(( n + 1 ))
        done
    elif (( k < 62 )); then
        rtext 1; t=${RT:- } c=${RTC:- }; rsym; a=$RS; rnd 0 12; n=$RN
        LAST="writeChar $x $y [${t@Q}] $a $n"
        fv.video.writeChar "$x" "$y" "$t" "$a" "$n"
        for (( i = 0; i < n; i++ )); do sh_put $(( x + i )) "$y" "${c:0:1}" "$a"; done
    elif (( k < 72 )); then
        rnd -2 $(( SW + 2 )); w=$RN; rnd -1 $(( SH + 1 )); h=$RN; rtext 1; t=${RT:- } c=${RTC:- }; rsym; a=$RS
        LAST="fillRect $x $y $w $h $a [${t@Q}]"
        fv.video.fillRect "$x" "$y" "$w" "$h" "$a" "$t"
        for (( i = y; i < y + h; i++ )); do for (( n = x; n < x + w; n++ )); do sh_put "$n" "$i" "${c:0:1}" "$a"; done; done
    elif (( k < 80 )); then
        rnd -3 $(( SW + 3 )); w=$RN; rnd -2 $(( SH + 2 )); h=$RN
        LAST="setClip $x $y $w $h"
        fv.video.setClip "$x" "$y" "$w" "$h"
        SX1=$(( x < 0 ? 0 : x )) SY1=$(( y < 0 ? 0 : y )) SX2=$(( w > SW ? SW : w )) SY2=$(( h > SH ? SH : h ))
    elif (( k < 84 )); then
        LAST=resetClip; fv.video.resetClip; SX1=0 SY1=0 SX2=$SW SY2=$SH
    elif (( k < 88 )); then
        rnd 0 $(( SW + 3 )); x=$RN; rnd 0 $(( SH + 2 )); y=$RN; rnd 0 3; n=$RN
        LAST="cursor $x $y $n"; fv.video.setCursorPos "$x" "$y"; fv.video.setCursorType "$n"
    elif (( k < 93 )); then
        rsym; a=$RS; rnd 0 255; w=$RN; rnd 0 255; h=$RN; rnd 0 1; n=$RN
        LAST="definePalette $a $w $h $n"; fv.video.definePalette "$a" "$w" "$h" "$n"
    elif (( k < 95 )); then
        n=$(( __FV_VS_DEPTH == 256 ? 16 : 256 ))
        LAST="setColorDepth $n"; fv.video.setColorDepth "$n"
    elif (( k < 97 )); then
        rsym; a=$RS
        LAST="clearScreen $a"; fv.video.clearScreen "$a"
        for (( i = 0; i < SW * SH; i++ )); do SH_C[i]=' ' SH_A[i]=$a; done
    else
        rnd 1 30; w=$RN; rnd 1 9; h=$RN
        LAST="resize ${w}x$h"
        FV_SCREEN_W=$w FV_SCREEN_H=$h fv.video.resizeScreen
        sh_alloc "$w" "$h"
        vt_init "$w" "$h"
    fi
}

kt_test_start "property: $FRAMES random frames (seed $SEED): VT grid == buffer == shadow after every update, incremental == forced repaint"
RANDOM=$SEED
FV_SCREEN_W=23 FV_SCREEN_H=7 fv.video.initScreen
sh_alloc 23 7
vt_init 23 7
LAST=init bad='' nforce=0 nbytes=0 nempty=0
for (( f = 1; f <= FRAMES; f++ )); do
    rnd 1 6
    for (( j = 0; j < RN; j++ )); do op; done
    if ! sh_cmp; then bad="frame $f: $VT_ERR"; break; fi
    if ! frame; then bad="frame $f: $VT_ERR (last op: $LAST)"; break; fi
    nbytes=$(( nbytes + ${#VT_OUT} ))
    if [[ -z $VT_OUT ]]; then nempty=$(( nempty + 1 )); fi
    if (( f % 12 == 0 )); then
        if ! same_as_force; then bad="frame $f: $VT_ERR"; break; fi
        nforce=$(( nforce + 1 ))
    fi
done
if [[ -z $bad ]]; then kt_test_pass "ok: $FRAMES frames, $nforce forced comparisons, $nempty empty frames, $nbytes chars"; else kt_test_fail "$bad"; fi

kt_test_log "012_VtModel.sh completed"
