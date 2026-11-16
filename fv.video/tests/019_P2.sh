#!/usr/bin/env bash
# 019_P2.sh - the fv.video additions for the P2 views (stage 2a), headless:
#   * writeBuf X Y TEXT ATTRS [H]: H rows from Y (FV WriteLine), H 1 or
#     omitted byte-identical to P1, H 0 nothing, RESULT the row width, bad H
#     rc 2 with nothing written, the clip on every row (top, bottom, left,
#     right), wide text, rows holding wide cells (half-overwrites per row),
#     markers per row, a huge H, ASCII mode;
#   * shadeRect X Y W H [ATTR]: characters kept, the symbol V (FV ShadowAttr
#     $08) or ATTR, the clip, negative and empty rectangles, a half-covered
#     wide character shaded whole (also outside the clip), markers and the
#     side map untouched, the damage, bad arguments, no screen; frames after
#     shadeRect through the VT model (narrow and wide, incremental = forced);
#   * getRow Y: the display text (continuations dropped, markers expanded),
#     REPLY the symbols, read-only, bad Y, no screen, ASCII mode;
#   * getClip: setClip's corner form after initScreen, setClip (clamped),
#     resetClip, a save / restore round trip, bad arguments, no screen;
#   * the default palette cached per process (D18): a cached initScreen
#     equals a fresh build at 256 and 16 colours, after definePalette and
#     setColorDepth too, with the 16-colour map emptied, in ASCII mode;
#   * the fast argument check: every coordinate form a write accepted before
#     (digits, leading zeros, negatives) still accepted with the same value,
#     everything else rc 2 - for writeStr, writeBuf, writeCStr, writeChar,
#     fillRect, setClip and shadeRect;
#   * caller state (013-style): a P2 scene under nocasematch, failglob,
#     nullglob, noglob, extglob, globasciiranges off, odd IFS, set -eu, a C
#     locale and all at once gives the reference output and keeps the state;
#   * zero forks: the new functions with PATH=''.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "019: fv.video for P2"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81'
for c in "$HAN" "$JI" "$EMO"; do VT_WD[$c]=2; done
VT_WD[$ACU]=0 VT_PICT[$EMO]=1

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
scr() { FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; }
# rows -> R = every row as "cells|symbols" joined by '/' (\x01 '<', \x02 '#')
rows() {
    local y c
    R=''
    for (( y = 0; y < __FV_VS_H; y++ )); do
        c=${__FV_VS_CH[y]}; c=${c//$'\x01'/'<'}; c=${c//$'\x02'/'#'}
        R+="$c|${__FV_VS_AT[y]}/"
    done
}
# dmg -> D = the damaged columns per row, "y:x1-x2 ..."
dmg() {
    local y
    D=''
    for y in "${!__FV_VS_DX1[@]}"; do D+="$y:${__FV_VS_DX1[y]}-${__FV_VS_DX2[y]} "; done
}
# xs -> XS = the side map, sorted
xs() {
    local k
    XS=''
    while IFS= read -r k; do [[ -n $k ]] && XS+="$k=${__FV_VS_X[$k]};"; done < <(printf '%s\n' "${!__FV_VS_X[@]}" | sort -t' ' -k1,1n -k2,2n)
}
# inv -> INV = '' when the buffer keeps 017's grammar (rows W long, a
# continuation's symbol = its lead's, markers = side entries, flags exact)
inv() {
    local y x c a f n=0 k e=''
    for (( y = 0; y < __FV_VS_H; y++ )); do
        c=${__FV_VS_CH[y]} a=${__FV_VS_AT[y]}
        (( ${#c} == __FV_VS_W && ${#a} == __FV_VS_W )) || e+=" row $y length ${#c}/${#a}"
        [[ ${c:0:1} == $'\x01' ]] && e+=" row $y starts with a continuation"
        for (( x = 1; x < ${#c}; x++ )); do
            if [[ ${c:x:1} == $'\x01' ]]; then
                [[ ${a:x:1} == "${a:x-1:1}" ]] || e+=" $y,$x continuation symbol ${a:x:1} != lead ${a:x-1:1}"
            fi
            if [[ ${c:x:1} == $'\x02' ]]; then n=$(( n + 1 )); [[ -n ${__FV_VS_X["$y $x"]+x} ]] || e+=" $y,$x marker without content"; fi
        done
        if [[ ${c:0:1} == $'\x02' ]]; then n=$(( n + 1 )); [[ -n ${__FV_VS_X["$y 0"]+x} ]] || e+=" $y,0 marker without content"; fi
        f=0
        [[ $c == *$'\x01'* ]] && f=1
        [[ $c == *$'\x02'* ]] && f=$(( f + 2 ))
        [[ ${__FV_VS_WIDE[y]} == "$f" ]] || e+=" row $y flag ${__FV_VS_WIDE[y]} != $f"
    done
    (( n == ${#__FV_VS_X[@]} )) || e+=" $n markers, ${#__FV_VS_X[@]} entries"
    INV=$e
}
# frame [force] -> an update through the VT model, then vt_cmp
frame() {
    if [[ ${1-} == force ]]; then vt_capture fv.video.updateScreen force; else vt_capture fv.video.updateScreen; fi
    if (( VT_RC )); then VT_ERR="updateScreen rc $VT_RC"; return 1; fi
    vt_feed "$VT_OUT" || return 1
    vt_cmp
}
same_as_force() {
    local a
    vt_grid; a=$VT_GRID
    vt_init "$__FV_VS_W" "$__FV_VS_H"
    frame force || return 1
    vt_grid
    if [[ $VT_GRID != "$a" ]]; then VT_ERR="incremental grid != forced repaint"; return 1; fi
}
exec {nullfd}>/dev/null
FV_VIDEO_OUT_FD=$nullfd

# --- no screen -------------------------------------------------------------------
__FV_VS_H=0 __FV_VS_PAL=()
r=''
fv.video.shadeRect 0 0 1 1; r+="$? "
fv.video.getRow 0; r+="$?[$RESULT|$REPLY] "
fv.video.getClip; r+="$?[$RESULT] "
fv.video.writeBuf 0 0 a 1 3; r+="$? "
fv.video.writeBuf 0 0 a 1 x; r+="$? "
fv.video.writeBuf 0 0 a 1 -1; r+="$?"
check "no screen yet: shadeRect, getRow, getClip, writeBuf with H are rc 1; a bad H is rc 2 first" "1 1[|] 1[] 1 2 2" "$r"

# --- writeBuf with a repeat count -----------------------------------------------
scr 8 5
fv.video.writeBuf 1 1 'abc' 'ABC'; a=$?:$RESULT; rows; ra=$R; dmg; da=$D
scr 8 5
fv.video.writeBuf 1 1 'abc' 'ABC' 1; b=$?:$RESULT; rows; rb=$R; dmg; db=$D
scr 8 5
fv.video.writeBuf 1 1 'abc' 'ABC' ''; c=$?:$RESULT; rows
check "writeBuf: H 1 and an empty H are what P1 did without H (rows, damage, RESULT)" "same" \
    "$( [[ $a == "$b" && $a == "$c" && $ra == "$rb" && $ra == "$R" && $da == "$db" && $a == 0:3 ]] && echo same || echo "[$a $ra $da] [$b $rb $db] [$c $R]")"
scr 8 5
fv.video.writeBuf 1 1 '║ab║' '9119' 3; r="$? $RESULT"; rows
check "writeBuf H 3: the row on rows 1-3, RESULT the row width" \
    "0 4         |00000000/ ║ab║   |09119000/ ║ab║   |09119000/ ║ab║   |09119000/        |00000000/" "$r $R"
scr 8 5
fv.video.updateScreen
fv.video.writeBuf 1 1 'ab' '12' 0; r="$? $RESULT"; rows; dmg
blank8='        |00000000/'
check "writeBuf H 0: nothing written, nothing damaged, RESULT the width" "0 2 $blank8$blank8$blank8$blank8$blank8 []" "$r $R [$D]"
r=''
for h in -1 x 1.5 ' 2' 2x 99999999; do
    fv.video.writeBuf 0 0 'ab' '12' "$h"; r+="$?[$RESULT] "
done
rows; dmg
check "writeBuf: a bad H (-1 x 1.5 ' 2' 2x 8 digits) is rc 2, RESULT '', nothing written" \
    "2[] 2[] 2[] 2[] 2[] 2[] $blank8$blank8$blank8$blank8$blank8 []" "$r$R [$D]"
fv.video.writeBuf 0 0 'ab' '123' 2; r="$?[$RESULT]"
check "writeBuf: ATTRS of another length with H is still rc 2" "2[]" "$r"
fv.video.writeBuf 0 0 'ab' '12' 007; r="$?[$RESULT]"; rows
check "writeBuf: H with leading zeros is decimal (007 = 7 rows, clipped to the screen)" \
    "0[2] ab      |12000000/ab      |12000000/ab      |12000000/ab      |12000000/ab      |12000000/" "$r $R"
scr 8 6
fv.video.setClip 2 1 6 4
fv.video.writeBuf 0 0 'abcdefgh' '12345678' 6; r="$? $RESULT"; rows
check "writeBuf H with a clip: rows above / below and columns left / right of the clip untouched" \
    "0 8         |00000000/  cdef  |00345600/  cdef  |00345600/  cdef  |00345600/        |00000000/        |00000000/" "$r $R"
fv.video.resetClip
scr 6 3
t0=$EPOCHREALTIME
fv.video.writeBuf 0 1 'xy' '12' 9999999; r="$? $RESULT"
t1=$EPOCHREALTIME
us=$(( ${t1/[.,]/} - ${t0/[.,]/} ))
rows
check "writeBuf H 9999999: clamped to the screen rows (fast), rows 1-2 written" "0 2       |000000/xy    |120000/xy    |120000/" "$r $R"
kt_test_log "writeBuf H 9999999 took $us us"

# wide text and rows with wide cells
scr 10 4
fv.video.writeStr 0 0 "a${HAN}b" 1
fv.video.writeStr 0 1 "a${HAN}b" 1
fv.video.writeStr 0 2 "a${HAN}b" 1
fv.video.writeBuf 2 0 "${JI}${EMO}z" '23456' 3; r="$? $RESULT"; rows; inv; xs
check "writeBuf H 3 with wide text and markers over rows holding wide cells: half-overwrites per row, a marker entry per row, grammar kept" \
    "0 5|a <#<z   |1122446000/a <#<z   |1122446000/a <#<z   |1122446000/          |0000000000/||0 4=$EMO;1 4=$EMO;2 4=$EMO;" \
    "$r|${R//字/}|$INV|$XS"
rows
check "  the cells (字 at 2-3 on each row, the symbol of a continuation = its lead's)" \
    "a 字<#<z   " "$(c=${__FV_VS_CH[1]}; c=${c//$'\x01'/'<'}; c=${c//$'\x02'/'#'}; printf '%s' "$c")"
FV_ASCII=1 fv.video.initScreen
fv.video.writeBuf 0 1 "╔═${HAN}╗" '1234' 2; r="$? $RESULT ${__FV_VS_CH[1]:0:4} ${__FV_VS_CH[2]:0:4} ${__FV_VS_AT[2]:0:4}"
check "writeBuf H in ASCII mode: the mapped text on each row" "0 4 +=?+ +=?+ 1234" "$r"

# --- shadeRect ------------------------------------------------------------------------
scr 10 4
check "the reserved shadow symbol V: FV ShadowAttr \$08, dark grey (8) on black (0)" "8 0 0 ${__FV_VS_SGR[V]@Q}" \
    "${__FV_VS_PAL[V]} $'\E[0;38;5;8;48;5;0m'"
fv.video.writeStr 0 1 'abcdefghij' 1
fv.video.writeStr 0 2 'Привет мир' 2
fv.video.updateScreen
fv.video.shadeRect 2 1 3 2; r="$? $RESULT"; rows; dmg
check "shadeRect 2 1 3 2: characters kept, symbols V, the damage = the rectangle, RESULT W" \
    "0 3           |0000000000/abcdefghij|11VVV11111/Привет мир|22VVV22222/          |0000000000/ 1:2-5 2:2-5 " "$r $R $D"
fv.video.shadeRect 8 0 5 9 A; r="$? $RESULT"; rows
check "shadeRect with ATTR, cut by the screen's right and bottom edges" \
    "0 5           |00000000AA/abcdefghij|11VVV111AA/Привет мир|22VVV222AA/          |00000000AA/" "$r $R"
fv.video.setClip 1 1 4 3
fv.video.shadeRect 0 0 10 4 B; rows
fv.video.resetClip
check "shadeRect inside a clip: only the clip's cells" \
    "          |00000000AA/abcdefghij|1BBBV111AA/Привет мир|2BBBV222AA/          |00000000AA/" "$R"
r=''
fv.video.shadeRect -3 -1 5 3 C; r+="$?:$RESULT "
fv.video.shadeRect 4 0 -2 3 C; r+="$?:$RESULT "
fv.video.shadeRect 4 0 2 0 C; r+="$?:$RESULT "
fv.video.shadeRect 004 0 1 1 C; r+="$?:$RESULT"
rows
check "shadeRect: negative X Y (cut), W < 0 (RESULT 0) and H 0 change nothing, leading zeros decimal" \
    "0:5 0:0 0:2 0:1           |CC00C000AA/abcdefghij|CCBBV111AA/Привет мир|2BBBV222AA/          |00000000AA/" "$r $R"
r=''
for a in 'x 0 1 1' '0 x 1 1' '0 0 x 1' '0 0 1 x' '0 0 1 1 *' '0 0 1 1 ab' '0 0 1' '' '0 0 1 1.5'; do
    read -r -a args <<< "$a"
    fv.video.shadeRect "${args[@]}"; r+="$?[$RESULT] "
done
check "shadeRect: bad arguments are rc 2, RESULT ''" "2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] " "$r"

# wide characters
scr 12 3
fv.video.writeStr 0 0 "a${HAN}${JI}${EMO}e${ACU}x" 1
xs; x0=$XS v0=${__FV_VS_XV[0]-}
fv.video.updateScreen
fv.video.shadeRect 2 0 3 1; rows; dmg; xs; inv
check "shadeRect over half of a wide character at each edge: both pairs shaded whole, the damage widened" \
    "a${HAN}<${JI}<#<#x   |1VVVV1111000/|0:1-5 |same|" "${R%%/*}/|$D|$( [[ $XS == "$x0" && ${__FV_VS_XV[0]-} == "$v0" ]] && echo same || echo "$XS $v0")|$INV"
fv.video.setClip 0 0 6 3
fv.video.shadeRect 5 0 3 1 W; rows; inv
fv.video.resetClip
check "shadeRect: the clip cuts a marker pair (emoji at 5-6, clip x < 6): its half outside the clip is shaded too" \
    "1VVVVWW11000||" "${__FV_VS_AT[0]}|$INV|"
check "shadeRect never touches a cell's characters or the side map (markers kept, the version unchanged)" "same" \
    "$( xs; [[ $XS == "$x0" && ${__FV_VS_XV[0]-} == "$v0" ]] && echo same || echo "$XS")"

# frames through the VT model
scr 16 5
vt_init 16 5
kt_test_start "VT model: a window with a shadow (2x rows right, 1 row below) over text and wide characters"
fv.video.fillRect 0 0 16 5 1 '░'
fv.video.writeStr 0 3 "x${HAN}${JI}${EMO}ok${ACU}" 2
fv.video.fillRect 2 0 8 3 8
fv.video.writeBuf 2 1 '║ text ║' '98888889' 1
fv.video.shadeRect 10 1 2 3
fv.video.shadeRect 4 3 8 1
inv
if [[ -z $INV ]] && frame && same_as_force; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "${INV:-$VT_ERR}"; fi
kt_test_start "VT model: the shadow moved (repainted, shaded elsewhere) - incremental frame = forced repaint"
vt_init 16 5; frame force >/dev/null
fv.video.fillRect 0 0 16 5 1 '░'
fv.video.writeStr 0 3 "x${HAN}${JI}${EMO}ok${ACU}" 2
fv.video.shadeRect 1 3 4 2
fv.video.shadeRect 3 2 1 1 V
if frame && same_as_force; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "$VT_ERR"; fi
kt_test_start "VT model: shadeRect with 16 colours"
fv.video.setColorDepth 16
fv.video.shadeRect 0 0 16 1
if frame && [[ $VT_OUT == *$'\e[0;90;40m'* ]] && same_as_force; then kt_test_pass "ok"; else kt_test_fail "${VT_ERR:-${VT_OUT@Q}}"; fi

# --- getRow -------------------------------------------------------------------------
scr 12 3
fv.video.writeStr 0 0 "a${HAN}b${EMO}e${ACU}z" 1
fv.video.writeStr 0 1 'plain ║ text' 2
fv.video.updateScreen
rows; r0=$R; dmg; d0=$D; xs; x0=$XS
fv.video.getRow 0; r="$?|$RESULT|$REPLY"
check "getRow: wide characters once (continuations dropped), markers expanded, REPLY one symbol per cell" \
    "0|a${HAN}b${EMO}e${ACU}z    |111111110000" "$r"
fv.video.getRow 1; r="$?|$RESULT|$REPLY|${#REPLY}"
check "getRow: a narrow row as it is" "0|plain ║ text|222222222222|12" "$r"
rows; dmg; xs
check "getRow is read-only (cells, symbols, damage, side map)" "same" \
    "$( [[ $R == "$r0" && $D == "$d0" && $XS == "$x0" ]] && echo same || echo changed)"
r=''
for a in -1 3 x '' 01 '1 2'; do
    if [[ $a == '1 2' ]]; then fv.video.getRow 1 2; else fv.video.getRow "$a"; fi
    r+="$?[$RESULT|$REPLY] "
done
check "getRow: a bad Y (-1, H, x, '', 01, two arguments) is rc 2, RESULT and REPLY ''" \
    "2[|] 2[|] 2[|] 2[|] 2[|] 2[|] " "$r"
FV_ASCII=1 FV_SCREEN_W=12 FV_SCREEN_H=3 fv.video.initScreen
fv.video.writeStr 0 0 "╔═${HAN}╗" 1
fv.video.getRow 0; r="$?|$RESULT|$REPLY"
check "getRow in ASCII mode" "0|+=?+        |111100000000" "$r"

# --- getClip ---------------------------------------------------------------------
scr 20 10
r=''
fv.video.getClip; r+="[$RESULT] "
fv.video.setClip 2 3 15 8; fv.video.getClip; r+="[$RESULT] "
fv.video.setClip -4 -1 99 50; fv.video.getClip; r+="[$RESULT] "
fv.video.setClip 7 2 3 1; fv.video.getClip; r+="[$RESULT] "
fv.video.resetClip; fv.video.getClip; r+="[$RESULT]"
check "getClip: X1 Y1 X2 Y2 after initScreen, setClip (clamped to the screen; an empty clip as set), resetClip" \
    "[0 0 20 10] [2 3 15 8] [0 0 20 10] [7 2 3 1] [0 0 20 10]" "$r"
fv.video.setClip 1 2 9 7
fv.video.getClip; saved=$RESULT
fv.video.setClip 0 0 3 3
IFS=' ' read -r a b c d <<< "$saved"; fv.video.setClip "$a" "$b" "$c" "$d"
fv.video.getClip
check "getClip: a save and restore round trip" "1 2 9 7" "$RESULT"
fv.video.getClip x; r="$?[$RESULT]"
check "getClip with an argument is rc 2" "2[]" "$r"
fv.video.resetClip

# --- the default palette, cached per process (D18) --------------------------------
# palstate -> P = PAL and SGR sorted (a state to compare)
palstate() {
    local k
    P=''
    for k in $(printf '%s\n' "${!__FV_VS_PAL[@]}" | LC_ALL=C sort); do P+="$k=${__FV_VS_PAL[$k]}=${__FV_VS_SGR[$k]@Q};"; done
}
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
pal() { local k; P=''; for k in \$(printf '%s\n' \"\${!__FV_VS_PAL[@]}\" | LC_ALL=C sort); do P+=\"\$k=\${__FV_VS_PAL[\$k]}=\${__FV_VS_SGR[\$k]@Q};\"; done; }
FV_SCREEN_W=4 FV_SCREEN_H=2
r=''
[[ -z \$__FV_VS_CPAL\$__FV_VS_CSG256\$__FV_VS_CSG16 ]] && r+=empty,
fv.video.initScreen; pal; f256=\$P
[[ -n \$__FV_VS_CPAL && -n \$__FV_VS_CSG256 && -z \$__FV_VS_CSG16 ]] && r+=built256,
fv.video.definePalette 1 200 100 1; fv.video.definePalette V 1 2; fv.video.definePalette z 3 4; fv.video.setColorDepth 16
fv.video.initScreen; pal; [[ \$P == \"\$f256\" ]] && r+=cached256,
FV_COLORS=16 fv.video.initScreen; pal; f16=\$P
[[ -n \$__FV_VS_CSG16 ]] && r+=built16,
fv.video.definePalette 2 9 9; FV_COLORS=16 fv.video.initScreen; pal; [[ \$P == \"\$f16\" ]] && r+=cached16,
__FV_VS_N16=()
fv.video.initScreen; fv.video.setColorDepth 16; pal; [[ \$P == \"\$f16\" ]] && r+=n16-emptied,
FV_ASCII=1 fv.video.initScreen; pal; [[ \$P == \"\$f256\" && \$FV_VIDEO_ASCII == 1 ]] && r+=ascii,
printf '%s|%s' \"\$r\" \"\$f256\"" 2>&1)
fresh=$("$BASH" -c "
export LC_ALL=C.UTF-8 FV_COLORS=16
source '$FVV_TESTS_DIR/../fv.video.sh'
FV_SCREEN_W=4 FV_SCREEN_H=2 fv.video.initScreen
fv.video.setColorDepth 256
P=''; for k in \$(printf '%s\n' \"\${!__FV_VS_PAL[@]}\" | LC_ALL=C sort); do P+=\"\$k=\${__FV_VS_PAL[\$k]}=\${__FV_VS_SGR[\$k]@Q};\"; done
printf '%s' \"\$P\"" 2>&1)
check "palette cache: built per depth at the first initScreen; a later initScreen gives the fresh default palette (after definePalette, setColorDepth, an emptied 16-colour map, in ASCII mode)" \
    "empty,built256,cached256,built16,cached16,n16-emptied,ascii,|same" "${out%%|*}|$( [[ ${out#*|} == "$fresh" && -n $fresh ]] && echo same || echo "[${out#*|}] vs [$fresh]")"
# the cache never comes from the environment (initScreen evals it)
out=$(__FV_VS_CPAL='[0]=$(echo INJECTED)' __FV_VS_CSG256='[0]=x' __FV_VS_CSG16='[0]=x' "$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
FV_SCREEN_W=4 FV_SCREEN_H=2 fv.video.initScreen
printf '%s:%s' \"\${#__FV_VS_PAL[@]}\" \"\${__FV_VS_PAL[V]}\"" 2>&1)
check "palette cache: values in the environment are ignored at load (no eval of them)" "32:8 0 0" "$out"

# --- the fast argument check -----------------------------------------------------
# every coordinate form: valid ones with their value, the rest rc 2
scr 30 12
r='' bad=''
for v in 0 7 10 007 08 -1 -0 -007 1234567 9999999 12345678 '' ' 1' '1 ' 1x +1 0x1 $'\xd9\xa3' '1e2' '--1'; do
    want=2
    if [[ $v =~ ^-?[0-9]{1,7}$ ]]; then want=0; fi
    got=''
    fv.video.writeStr "$v" 1 'a' 1; got+=$?
    fv.video.writeStr 1 "$v" 'a' 1; got+=$?
    fv.video.writeBuf "$v" 1 'a' 1; got+=$?
    fv.video.writeCStr 1 "$v" 'a' 1 2; got+=$?
    fv.video.writeChar "$v" 1 'a' 1; got+=$?
    fv.video.fillRect 1 "$v" 1 1 1; got+=$?
    fv.video.fillRect 1 1 "$v" 1 1; got+=$?
    fv.video.fillRect 1 1 1 "$v" 1; got+=$?
    fv.video.shadeRect "$v" 1 1 1; got+=$?
    fv.video.shadeRect 1 1 1 "$v"; got+=$?
    fv.video.setClip "$v" 0 30 12; got+=$?
    fv.video.setClip 0 0 30 "$v"; got+=$?
    fv.video.resetClip
    printf -v w '%012d' 0; [[ $want == 2 ]] && w=${w//0/2}
    [[ $got == "$w" ]] || bad+=" [${v@Q}]=$got"
done
check "the fast check: integers of 1-7 digits (leading zeros, a minus) pass, everything else is rc 2, in every write and setClip" "" "$bad"
scr 30 12
r=''
fv.video.writeStr 007 008 'v' 1; r+="${__FV_VS_CH[8]:7:1} "
fv.video.writeStr -0 1 'w' 1; r+="${__FV_VS_CH[1]:0:1} "
fv.video.writeStr -2 2 'abc' 1; r+="${__FV_VS_CH[2]:0:2} "
fv.video.setClip 001 002 010 009; fv.video.getClip; r+="[$RESULT] "
fv.video.resetClip
fv.video.fillRect 03 03 02 02 4 '#'; r+="${__FV_VS_CH[4]:2:4} "
fv.video.writeChar 09 9 '=' 1 03; r+="${__FV_VS_CH[9]:8:5}"
check "the slow path keeps the values: leading zeros decimal, -0, negatives" "v w c  [1 2 10 9]  ##   === " "$r"

# --- caller state ----------------------------------------------------------------
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}" "${#p}"'
SCENE='
FV_SCREEN_W=12 FV_SCREEN_H=4
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r=""
fv.video.initScreen; r+="$?."
fv.video.writeBuf 1 0 "*[a]?ж" "aAaAaA" 3; r+="$RESULT."
fv.video.setClip 1 1 9 3; fv.video.getClip; r+="$RESULT."
fv.video.writeBuf 0 0 "?*[a]" "AaAaA" 4; fv.video.resetClip
fv.video.shadeRect 2 1 3 2; r+="$RESULT."
fv.video.shadeRect 0 3 4 1 a; r+="$RESULT."
fv.video.getRow 1; r+="$RESULT|$REPLY."
fv.video.getRow x || r+="$?."
fv.video.writeBuf 0 0 ab "*?" 2 || r+="$?."
fv.video.shadeRect 0 0 1 1 "*" || r+="$?."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$TMPF" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1 2 3; do printf " [%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done
'
run() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/p2cs.out'
source '$FVV_TESTS_DIR/../fv.video.sh'
p=\$'\\xd0\\xb6'
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}
run ''
ref=${OUT#*#} ref=${ref%#*}
check "caller state: the reference scene" "0.6.1 1 9 3.3.4. *[a]?ж     |0aVVVaA00000.2.2.2.0." "${ref%% \$*}"
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'IFS=' 'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C"; do
    kt_test_start "caller state: same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done

# --- zero forks ------------------------------------------------------------------
kt_test_start "PATH='': writeBuf H, shadeRect (narrow and wide rows), getRow, getClip, a cached initScreen, an update"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=10 FV_SCREEN_H=4
fv.video.initScreen
PATH=''
r=''
fv.video.initScreen; r+=\$?
fv.video.writeBuf 0 0 'a${HAN}b' '1234' 3; r+=\$RESULT
fv.video.shadeRect 1 0 2 4; r+=\$RESULT
fv.video.getRow 1; r+=\"\$RESULT\$REPLY\"
fv.video.setClip 1 1 5 3; fv.video.getClip; r+=\"[\$RESULT]\"
fv.video.updateScreen; r+=\$?
printf '%s' \"\$r\"" 2>&1)
want="042a${HAN}b      1VV4000000[1 1 5 3]0"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

exec {nullfd}>&-
kt_test_log "019_P2.sh completed"
