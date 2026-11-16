#!/usr/bin/env bash
# 010_Palette.sh - the palette and the colour depth (D10):
#   * the default palette: symbol 0 = FPC's DefaultAttr $07, 1-9 A-U = the 30
#     distinct bytes of FV's CAppColor, V = FV's ShadowAttr $08 (P2), DOS
#     nibbles mapped to ANSI;
#   * definePalette: values, SGR strings with 256 and 16 colours, bold as
#     SGR 1 only;
#   * nearest-16 for all 256 indices against the VT model's own computation
#     and hand-computed values;
#   * setColorDepth and a changed palette entry repaint what they change (VT
#     model), an unchanged one repaints nothing, an undefined symbol shows
#     as the default one;
#   * the depth: headless 256, FV_COLORS (a bad value ignored with a debug
#     line), detection: TERM *256color*, COLORTERM, TERM=linux, tput (a
#     stub), no tput.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "010: palette and colour depth"

E=$'\e'
check() {
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
scr() { FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; }
# frame -> update through the VT model, rc 1 + VT_ERR on a difference
frame() {
    vt_capture fv.video.updateScreen "$@" || return 1
    vt_feed "$VT_OUT" || return 1
    vt_cmp
}

unset FV_COLORS COLORTERM
scr 4 2
# hand-converted from FV app.inc CAppColor (byte $BF: B = background, F =
# foreground, DOS order 0 black 1 blue 2 green 3 cyan 4 red 5 magenta 6 brown
# 7 lightgray, +8 bright)
want='0=7 0 0 1=4 7 0 2=0 7 0 3=8 7 0 4=1 7 0 5=0 2 0 6=8 2 0 7=1 2 0 8=7 4 0 9=15 4 0 A=10 4 0 B=4 6 0 C=11 4 0 D=7 6 0 E=15 6 0 F=10 6 0 G=6 4 0 H=11 6 0 I=4 2 0 J=15 7 0 K=10 7 0 L=11 7 0 M=14 2 0 N=15 2 0 O=11 2 0 P=0 6 0 Q=2 7 0 R=8 6 0 S=0 4 0 T=2 4 0 U=2 6 0 V=8 0 0'
got=''
for s in 0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V; do got+="$s=${__FV_VS_PAL[$s]} "; done
check "the default palette: 32 symbols, FV classic colours as ANSI indices, V = ShadowAttr \$08" "$want 32" "${got% } ${#__FV_VS_PAL[@]}"
check "headless initScreen: 256 colours, no detection" "256 256" "$FV_VIDEO_COLORS $__FV_VS_DEPTH"
check "the default symbol's SGR (256)" "${E}[0;38;5;7;48;5;0m" "${__FV_VS_SGR[0]}"

fv.video.definePalette x 007 200 1; r="$? ${__FV_VS_PAL[x]} ${__FV_VS_SGR[x]}"
check "definePalette: decimal values, bold -> SGR 1 first" "0 7 200 1 ${E}[0;1;38;5;7;48;5;200m" "$r"
fv.video.definePalette y 255 0; r="${__FV_VS_PAL[y]} ${__FV_VS_SGR[y]}"
check "definePalette without BOLD: 0" "255 0 0 ${E}[0;38;5;255;48;5;0m" "$r"

fv.video.setColorDepth 16
r=''
for s in 'a 9 12 0' 'b 1 0 0' 'c 15 8 1' 'd 196 21 0' 'e 244 250 0' 'f 7 15 0'; do
    read -r n f b o <<< "$s"
    fv.video.definePalette "$n" "$f" "$b" "$o"
    r+="${__FV_VS_SGR[$n]} "
done
check "16 colours: fg 30-37 / 90-97, bg 40-47 / 100-107, bold only from BOLD, 256-indices via nearest-16" \
    "${E}[0;91;104m ${E}[0;31;40m ${E}[0;1;97;100m ${E}[0;91;44m ${E}[0;90;47m ${E}[0;37;107m " "$r"
check "setColorDepth 16 rebuilt the default palette too" "16 ${E}[0;37;40m ${E}[0;34;47m" "$FV_VIDEO_COLORS ${__FV_VS_SGR[0]} ${__FV_VS_SGR[1]}"

kt_test_start "nearest-16: hand-computed values (cube, greys, 0-15 themselves)"
r=''
for i in 0 9 15 16 21 46 196 226 231 232 244 250 255 136; do fv.video._n16 "$i"; r+="$i:${__FV_VS_N16[i]} "; done
want='0:0 9:9 15:15 16:0 21:4 46:10 196:9 226:11 231:15 232:0 244:8 250:7 255:7 136:3 '
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "nearest-16: all 256 indices equal the VT model's own computation"
bad=''
for (( i = 0; i < 256; i++ )); do
    fv.video._n16 "$i"; vt_n16 "$i"
    if [[ ${__FV_VS_N16[i]} != "$VT_N" ]]; then bad+=" $i:${__FV_VS_N16[i]}/$VT_N"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

kt_test_start "nearest-16 is memoised by definePalette only for the indices it uses"
out=$("$BASH" -c "source '$FVV_TESTS_DIR/../fv.video.sh'; FV_SCREEN_W=2 FV_SCREEN_H=1 fv.video.initScreen
fv.video.definePalette q 100 200; printf '%s ' \"\${!__FV_VS_N16[@]}\"" 2>&1)
if [[ $out == '0 1 2 4 6 7 8 10 11 14 15 100 200 ' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

# --- repaints through the VT model ------------------------------------------------
scr 8 3
vt_init 8 3
fv.video.definePalette p 196 21
fv.video.definePalette q 46 0 1
fv.video.writeStr 0 0 'red' p
fv.video.writeStr 2 1 'green' q
fv.video.writeStr 0 2 'undef' z
kt_test_start "VT model: a frame with defined, default and undefined symbols (256)"
if frame; then kt_test_pass "ok"; else kt_test_fail "$VT_ERR"; fi
kt_test_start "VT model: setColorDepth 16 repaints every row in 16-colour SGR"
fv.video.setColorDepth 16
if frame && [[ $VT_OUT == *"${E}[2;1H"* && $VT_OUT == *"${E}[0;91;44m"* && $VT_OUT != *'38;5'* ]]; then kt_test_pass "ok"; else kt_test_fail "${VT_ERR:-$VT_OUT}"; fi
kt_test_start "VT model: setColorDepth 256 back"
fv.video.setColorDepth 256
if frame && [[ $VT_OUT == *'38;5;196'* ]]; then kt_test_pass "ok"; else kt_test_fail "${VT_ERR:-$VT_OUT}"; fi
fv.video.definePalette q 46 0 1
vt_capture fv.video.updateScreen
check "definePalette with the same values: nothing to repaint" "''" "'$VT_OUT'"
kt_test_start "definePalette changing a symbol in use repaints only the rows holding it"
fv.video.definePalette q 21 226
if frame && [[ $VT_OUT == "${E}[2;1H"* && $VT_OUT != *"${E}[1;1H"* && $VT_OUT != *"${E}[3;1H"* ]]; then kt_test_pass "ok"; else kt_test_fail "${VT_ERR:-$VT_OUT}"; fi
kt_test_start "redefining the default symbol repaints every row (undefined symbols show as it)"
fv.video.definePalette 0 3 5
if frame && [[ $VT_OUT == *"${E}[1;1H"* && $VT_OUT == *"${E}[0;38;5;3;48;5;5m"*"${E}[3;1Hundef"* ]]; then kt_test_pass "ok"; else kt_test_fail "${VT_ERR:-$VT_OUT}"; fi

# --- the depth -------------------------------------------------------------------------
# depth ENV... -> the depth initScreen / detectColorDepth picks in a child shell
depth() {
    "$BASH" -c "
unset FV_COLORS COLORTERM TERM
$1
source '$FVV_TESTS_DIR/../fv.video.sh'
FV_SCREEN_W=2 FV_SCREEN_H=1
${2:-fv.video.detectColorDepth; printf '%s/%s' \"\$RESULT\" \"\$FV_VIDEO_COLORS\"}" 2>&1
}
r=''
r+="$(depth 'export FV_COLORS=16' 'fv.video.initScreen; printf %s $FV_VIDEO_COLORS') "
r+="$(depth 'export FV_COLORS=256 FV_VIDEO_ON=1 TERM=linux' 'fv.video.initScreen; printf %s $FV_VIDEO_COLORS') "
r+="$(depth 'export TERM=linux' 'fv.video.initScreen; printf %s $FV_VIDEO_COLORS') "
r+="$(depth 'export TERM=linux FV_VIDEO_ON=1' 'fv.video.initScreen; printf %s $FV_VIDEO_COLORS')"
check "initScreen: FV_COLORS headless too; detection only with the terminal on (FV_VIDEO_ON)" "16 256 256 16" "$r"
r=$(depth 'export FV_COLORS=88 VERBOSE_KKLASS=debug' 'fv.video.initScreen; printf %s $FV_VIDEO_COLORS')
check "a bad FV_COLORS is ignored with one debug line" "Error: fv.video: FV_COLORS='88' is not 16 or 256; ignored
256" "$r"
r=''
for env in 'export TERM=xterm-256color' 'export TERM=screen-256color-bce' 'export TERM=xterm COLORTERM=truecolor' \
    'export TERM=linux' 'export TERM=xterm; tput() { echo 256; }' 'export TERM=xterm; tput() { echo 88; }' \
    'export TERM=xterm; tput() { return 1; }' 'export TERM=xterm; tput() { echo x; }' \
    'export TERM=xterm PATH=/nonexistent' 'export TERM=linux FV_COLORS=256' 'export TERM=xterm-256color FV_COLORS=16' \
    'export TERM=xterm; tput() { echo 16777216; }' 'export TERM=xterm; tput() { echo 0256; }' 'export TERM=xterm; tput() { echo 0016; }'; do
    r+="$(depth "$env") "
done
check "detectColorDepth: TERM *256color* / COLORTERM -> 256, linux -> 16, tput >= 256 (any length: xterm-direct 16777216; leading zeros) -> 256, else / failing / missing -> 16; FV_COLORS wins" \
    "256/256 256/256 256/256 16/16 256/256 16/16 16/16 16/16 16/16 256/256 16/16 256/256 256/256 16/16 " "$r"
kt_test_start "detectColorDepth with TERM *256color* does not fork (PATH='', tput absent)"
r=$(depth "export TERM=xterm-256color; PATH=''")
if [[ $r == '256/256' ]]; then kt_test_pass "ok"; else kt_test_fail "[$r]"; fi

kt_test_log "010_Palette.sh completed"
