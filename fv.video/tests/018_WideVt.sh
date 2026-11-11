#!/usr/bin/env bash
# 018_WideVt.sh - frames with wide characters, emoji and clusters replayed
# through the VT model (fvv_vt.sh), whose widths come from the table below
# (never from fv.unicode), so the model checks the unit instead of echoing it:
#   * scripted scenes: the resync after wide and marker cells (CHA), the
#     pre-blank of wide markers, half-overwrites, the cursor after a resync,
#     a cluster replaced by another in the same cell;
#   * a terminal that DISAGREES (it draws emoji, a CJK character or a VS16
#     sequence narrow): with the resync every other cell still equals the
#     buffer and a narrow-drawn wide marker leaves a blank, never stale
#     text; with the resync turned off (__FV_VS_RSYNC=0, a test-only switch)
#     the same frames fail - the check can tell;
#   * a terminal that draws a narrow marker WIDE: rewriting the marker
#     re-sends the cell it covers (the range widening after a narrow marker);
#   * seeded random property runs (FVV_FRAMES, default 200, three seeds, one
#     of them wide-heavy; most frames carry a write of wide pieces): random
#     writes, clips, units, cursor moves, clears and resizes; after every
#     update the VT grid equals the buffer and the buffer keeps its grammar
#     (017's invariants); every few frames the incremental grid equals one
#     forced repaint into a fresh garbage grid; a minimum share of frames
#     with a resync and with a pre-blank is asserted;
#   * an incremental random run against a disagreeing terminal (emoji drawn
#     narrow, U+10FFFF and a lone regional indicator drawn wide): after every
#     frame every cell but the deviating ones equals the buffer (it fails
#     without the widening after a narrow marker).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "018: wide characters through the VT model"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' TADA=$'\xf0\x9f\x8e\x89'
ACU=$'\xcc\x81' DIA=$'\xcc\x88' ZWJ=$'\xe2\x80\x8d' VS16=$'\xef\xb8\x8f' KEYC=$'\xe2\x83\xa3'
COPY=$'\xc2\xa9' HEART=$'\xe2\x9d\xa4' WATCH=$'\xe2\x8c\x9a'
MAN=$'\xf0\x9f\x91\xa8' WOMAN=$'\xf0\x9f\x91\xa9' THUMB=$'\xf0\x9f\x91\x8d' TONE=$'\xf0\x9f\x8f\xbd'
RID=$'\xf0\x9f\x87\xa9' RIE=$'\xf0\x9f\x87\xaa' HI=$'\xf4\x8f\xbf\xbf'

# the model's own table: widths, Extended_Pictographic, modifiers, regional indicators
for c in "$HAN" "$JI" "$EMO" "$TADA" "$WATCH" "$MAN" "$WOMAN" "$THUMB" "$TONE"; do VT_WD[$c]=2; done
for c in "$ACU" "$DIA" "$ZWJ" "$VS16" "$KEYC"; do VT_WD[$c]=0; done
for c in "$EMO" "$TADA" "$WATCH" "$MAN" "$WOMAN" "$THUMB" "$COPY" "$HEART"; do VT_PICT[$c]=1; done
VT_MOD[$TONE]=1 VT_RI[$RID]=1 VT_RI[$RIE]=1

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
# frame [force] [dev] -> an update through the VT model, then vt_cmp [dev]
frame() {
    local dev=''
    if [[ ${1-} == force ]]; then vt_capture fv.video.updateScreen force; shift; else vt_capture fv.video.updateScreen; fi
    dev=${1-}
    if (( VT_RC )); then VT_ERR="updateScreen rc $VT_RC"; return 1; fi
    vt_feed "$VT_OUT" || return 1
    vt_cmp $dev
}
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
E=$'\e'

# --- scripted scenes ----------------------------------------------------------------
FV_SCREEN_W=24 FV_SCREEN_H=6 fv.video.initScreen
vt_init 24 6
scene "CJK, emoji, clusters, a flag, a keycap, a ZWJ pair, ⌚ and © with VS16 in one frame (the grid starts as garbage)" \
    "fv.video.writeStr 0 0 'a${HAN}b${EMO}c${JI}' 1" \
    "fv.video.writeStr 0 1 \$'e${ACU}x${RID}${RIE}1${VS16}${KEYC}${MAN}${ZWJ}${WOMAN}' 2" \
    "fv.video.writeStr 0 2 \$'${WATCH}${COPY}${VS16}${COPY}${THUMB}${TONE}a${TONE}${HI}' 3" \
    "fv.video.writeStr 0 3 \$'${ACU}orphan ${TADA}${TADA}${TADA}' 4"
scene "half-overwrites: a narrow write on each half of a wide character, a wide write across two" \
    "fv.video.writeStr 2 0 Z 5" "fv.video.writeStr 5 0 Q 5" "fv.video.writeStr 1 2 '${JI}' 6"
scene "a cluster replaced by another in the same cell: the frame has the new one" \
    "fv.video.writeStr 10 4 \$'e${ACU}' 1" "fv.video.updateScreen >/dev/null; vt_capture fv.video.updateScreen; vt_feed \"\$VT_OUT\"" \
    "fv.video.writeStr 10 4 \$'e${DIA}' 1"
r=${__FV_VS_X[4 10]}
check "... and the model's cell holds e + U+0308" "e$DIA" "$r"
scene "the cursor after a resync: shown on the second half of a wide character, then hidden" \
    "fv.video.setCursorPos 4 0" "fv.video.setCursorType 1"
scene "the cursor hidden again" "fv.video.setCursorType 0"
kt_test_start "the incremental grid equals one forced repaint into fresh garbage"
if same_as_force; then kt_test_pass "ok"; else kt_test_fail "$VT_ERR"; fi

# the frame's bytes for one row: the resync and the pre-blank
FV_SCREEN_W=12 FV_SCREEN_H=1 fv.video.initScreen
fv.video.writeStr 0 0 "a${HAN}${EMO}b" 0
vt_capture fv.video.updateScreen force
f=${VT_OUT#*m} f=${f%%"${E}[?25l"*}
check "the bytes of a row: no CHA after 漢 since a wide marker follows (its pre-blank moves the cursor anyway), the marker pre-blanked + CHA, nothing after the range's last cell" \
    "a${HAN}${E}[5G ${E}[4G${EMO}${E}[6Gb      " "$f"
fv.video.writeStr 7 0 "${JI}" 0
vt_capture fv.video.updateScreen
check "a damaged range that ends on a wide character: no CHA after it (the next row's CUP or the cursor's places the cursor)" \
    "${E}[1;8H${E}[0;38;5;7;48;5;0m${JI}" "${VT_OUT}"
fv.video.writeStr 0 0 "${HAN}" 0
vt_capture fv.video.updateScreen
check "a write over the first half of a wide character blanks its second half; the CHA after the new one goes before that blank" \
    "${E}[1;1H${E}[0;38;5;7;48;5;0m${HAN}${E}[3G " "${VT_OUT}"

# --- a terminal that disagrees --------------------------------------------------------
# dev_scene NAME SETUP — the scene drawn by a terminal with SETUP's deviation,
# once with the resync (vt_cmp dev must pass) and once without (must fail)
DEVTEXT="x${EMO}y${HAN}z${COPY}${VS16}w${THUMB}${TONE}v${WATCH}u"
dev_scene() {
    local name=$1 setup=$2 ok no
    VT_DEV=() VT_NOVS16=0
    eval "$setup"
    FV_SCREEN_W=24 FV_SCREEN_H=2 fv.video.initScreen
    vt_init 24 2
    fv.video.writeStr 0 0 "$DEVTEXT" 1
    fv.video.writeStr 0 1 "garbage under the row ..." 2
    frame force dev && ok=pass || ok="fail: $VT_ERR"
    __FV_VS_RSYNC=0
    vt_init 24 2
    frame force dev && no=pass || no=fail
    __FV_VS_RSYNC=1
    VT_DEV=() VT_NOVS16=0
    check "a terminal that draws $name narrow: with the resync every other cell equals the buffer and a wide marker leaves a blank; without the resync the check fails" \
        "pass fail" "$ok $no"
}
dev_scene "emoji (😀 👍🏽 ⌚)" "VT_DEV[\$EMO]=1; VT_DEV[\$THUMB]=1; VT_DEV[\$TONE]=1; VT_DEV[\$WATCH]=1"
dev_scene "a CJK character (漢)" "VT_DEV[\$HAN]=1"
dev_scene "a VS16 sequence (©️)" "VT_NOVS16=1"

kt_test_start "with a disagreeing terminal the stale cell after a narrow-drawn wide marker is blanked (a garbage grid, marker repainted)"
VT_DEV=() VT_DEV[$EMO]=1
FV_SCREEN_W=8 FV_SCREEN_H=1 fv.video.initScreen
vt_init 8 1
fv.video.writeStr 0 0 "${EMO}ab" 1
frame force dev; r=$?
c1=${VT_C[1]}
VT_DEV=()
if (( r == 0 )) && [[ $c1 == ' ' ]]; then kt_test_pass "ok"; else kt_test_fail "rc $r cell 1 [$c1] $VT_ERR"; fi

kt_test_start "a terminal that draws a narrow marker wide (U+10FFFF here; a newer table, a lone regional indicator): rewriting the marker re-sends the cell it covers"
VT_DEV=() VT_DEV[$HI]=2
FV_SCREEN_W=8 FV_SCREEN_H=1 fv.video.initScreen
vt_init 8 1
fv.video.writeStr 0 0 "ab${HI}cdef" 1
frame force dev; r1=$?
fv.video.writeStr 2 0 "${HI}" 2
frame dev; r2=$?
c3=${VT_C[3]}
VT_DEV=()
if (( r1 == 0 && r2 == 0 )) && [[ $c3 == c ]]; then kt_test_pass "ok"; else kt_test_fail "rc $r1/$r2 cell 3 [${c3@Q}] $VT_ERR"; fi

# --- the property runs ------------------------------------------------------------------
FRAMES=${FVV_FRAMES:-200}
POOLN=(a b c ' ' ' ' ж ─ é 7 '~' '*' "e${ACU}" "$ACU" "$COPY")
POOLW=("$HAN" "$JI" "$EMO" "$TADA" "$HI" "${RID}${RIE}" "$RID" "${COPY}${VS16}" "1${VS16}${KEYC}" "${THUMB}${TONE}" "a${TONE}" "${MAN}${ZWJ}${WOMAN}" "$WATCH" "${HEART}${ZWJ}${EMO}")
SYMS=(a b c 0 1 9 U z)
rnd() { RN=$(( RANDOM % ($2 - $1 + 1) + $1 )); }
rtext() {   # N -> RT: 0..N pieces, wide ones with the run's weight (WEIGHT of 10)
    local n i
    rnd 0 "$1"; n=$RN RT=''
    for (( i = 0; i < n; i++ )); do
        if (( RANDOM % 10 < WEIGHT )); then RT+=${POOLW[RANDOM % ${#POOLW[@]}]}; else RT+=${POOLN[RANDOM % ${#POOLN[@]}]}; fi
    done
}
rsym() { RS=${SYMS[RANDOM % ${#SYMS[@]}]}; }
op() {
    local x y w h t a b i k n
    rnd 0 99; k=$RN
    rnd -4 $(( __FV_VS_W + 2 )); x=$RN
    rnd -1 $(( __FV_VS_H )); y=$RN
    if (( k < 30 )); then
        rtext 8; rsym; LAST="writeStr $x $y [${RT@Q}] $RS"; fv.video.writeStr "$x" "$y" "$RT" "$RS"
    elif (( k < 40 )); then
        rtext 6; t=$RT; fv.video.strWidth "$t"; b=''
        for (( i = 0; i < RESULT; i++ )); do rsym; b+=$RS; done
        LAST="writeBuf $x $y [${t@Q}] $b"; fv.video.writeBuf "$x" "$y" "$t" "$b"
    elif (( k < 50 )); then
        rtext 8; rsym; a=$RS; rsym; LAST="writeCStr $x $y [${RT@Q}] $a $RS"; fv.video.writeCStr "$x" "$y" "$RT" "$a" "$RS"
    elif (( k < 58 )); then
        rtext 1; rsym; rnd 0 7; LAST="writeChar $x $y [${RT@Q}] $RS $RN"; fv.video.writeChar "$x" "$y" "$RT" "$RS" "$RN"
    elif (( k < 72 )); then
        rnd -1 13; w=$RN; rnd 0 3; h=$RN; rtext 1; rsym
        LAST="fillRect $x $y $w $h $RS [${RT@Q}]"; fv.video.fillRect "$x" "$y" "$w" "$h" "$RS" "$RT"
    elif (( k < 74 )); then
        rnd -2 $(( __FV_VS_W + 2 )); w=$RN; rnd -1 $(( __FV_VS_H + 1 )); h=$RN
        LAST="setClip $x $y $w $h"; fv.video.setClip "$x" "$y" "$w" "$h"
    elif (( k < 80 )); then
        LAST=resetClip; fv.video.resetClip
    elif (( k < 88 )); then
        rnd 0 $(( __FV_VS_W + 2 )); x=$RN; rnd 0 $(( __FV_VS_H + 1 )); y=$RN; rnd 0 3; n=$RN
        LAST="cursor $x $y $n"; fv.video.setCursorPos "$x" "$y"; fv.video.setCursorType "$n"
    elif (( k < 92 )); then
        rsym; LAST="definePalette $RS"; rnd 0 255; w=$RN; rnd 0 255; fv.video.definePalette "$RS" "$w" "$RN"
    elif (( k < 95 )); then
        n=$(( __FV_VS_DEPTH == 256 ? 16 : 256 )); LAST="setColorDepth $n"; fv.video.setColorDepth "$n"
    elif (( k < 98 )); then
        rsym; LAST="clearScreen $RS"; fv.video.clearScreen "$RS"
    else
        rnd 2 26; w=$RN; rnd 1 6; h=$RN
        LAST="resize ${w}x$h"; FV_SCREEN_W=$w FV_SCREEN_H=$h fv.video.resizeScreen; vt_init "$w" "$h"
    fi
}
# wop — a writeStr of wide pieces only, on the screen
wop() {
    local x y i t=''
    rnd 0 $(( __FV_VS_W - 1 )); x=$RN; rnd 0 $(( __FV_VS_H - 1 )); y=$RN
    for (( i = RANDOM % 4; i >= 0; i-- )); do t+=${POOLW[RANDOM % ${#POOLW[@]}]}; done
    rsym; LAST="wide writeStr $x $y [${t@Q}] $RS"; fv.video.writeStr "$x" "$y" "$t" "$RS"
}
# gram -> GERR = '' when the buffer keeps its grammar (as 017's inv)
gram() {
    local y x c n=0 k e=''
    for (( y = 0; y < __FV_VS_H; y++ )); do
        c=${__FV_VS_CH[y]}
        (( ${#c} == __FV_VS_W )) || e+=" row $y length"
        [[ ${c:0:1} == $'\x01' || $c == *$'\x01\x01'* ]] && e+=" row $y continuation"
        for (( x = 0; x < ${#c}; x++ )); do
            if [[ ${c:x:1} == $'\x02' ]]; then n=$(( n + 1 )); [[ -n ${__FV_VS_X["$y $x"]+x} ]] || e+=" $y,$x no entry"; fi
        done
    done
    for k in "${!__FV_VS_X[@]}"; do [[ ${__FV_VS_CH[${k% *}]:${k#* }:1} == $'\x02' ]] || e+=" stale [$k]"; done
    (( n == ${#__FV_VS_X[@]} )) || e+=" $n markers ${#__FV_VS_X[@]} entries"
    GERR=$e
}
RE_CHA=$'\e\[[0-9]+G' RE_PB=$'\e\[[0-9]+G \e\[[0-9]+G'
prop() {   # SEED WEIGHT TITLE MIN_CHA% MIN_PREBLANK% [dev]
    local f j bad='' nforce=0 nbytes=0 ncha=0 npb=0 dev=${6-}
    WEIGHT=$2
    if [[ -n $dev ]]; then
        kt_test_start "property against a DISAGREEING terminal (emoji drawn narrow, U+10FFFF and a lone regional indicator drawn wide): $FRAMES incremental frames, seed $1: after every frame every cell but the deviating ones equals the buffer"
    else
        kt_test_start "property: $FRAMES random frames, seed $1, $3: VT grid == buffer, the grammar after every update, incremental == forced repaint; >= $4 % of the frames with a resync, >= $5 % with a pre-blank"
    fi
    RANDOM=$1
    FV_SCREEN_W=19 FV_SCREEN_H=5 fv.video.initScreen
    vt_init 19 5
    LAST=init
    for (( f = 1; f <= FRAMES; f++ )); do
        if (( RANDOM % 10 < WEIGHT )); then wop; fi
        rnd 1 5
        for (( j = 0; j < RN; j++ )); do op; done
        gram; if [[ -n $GERR ]]; then bad="frame $f: grammar:$GERR (last op: $LAST)"; break; fi
        if ! frame $dev; then bad="frame $f: $VT_ERR (last op: $LAST)"; break; fi
        nbytes=$(( nbytes + ${#VT_OUT} ))
        if [[ $VT_OUT =~ $RE_CHA ]]; then ncha=$(( ncha + 1 )); fi
        if [[ $VT_OUT =~ $RE_PB ]]; then npb=$(( npb + 1 )); fi
        if [[ -z $dev ]] && (( f % 10 == 0 )); then
            if ! same_as_force; then bad="frame $f: $VT_ERR"; break; fi
            nforce=$(( nforce + 1 ))
        fi
    done
    if [[ -z $bad ]] && (( ncha * 100 < $4 * FRAMES || npb * 100 < $5 * FRAMES )); then bad="only $ncha frames with a resync, $npb with a pre-blank"; fi
    if [[ -z $bad ]]; then kt_test_pass "ok: $ncha frames with a resync, $npb with a pre-blank, $nforce forced comparisons, $nbytes chars"; else kt_test_fail "$bad"; fi
}
prop 20261112 4 "a mixed pool" 20 15
prop 7 4 "a mixed pool" 20 15
prop 424242 8 "a wide-heavy pool" 50 40
VT_DEV=() VT_DEV[$EMO]=1 VT_DEV[$TADA]=1 VT_DEV[$HI]=2 VT_DEV[$RID]=2
prop 1111 7 "" 30 10 dev
VT_DEV=()

kt_test_log "018_WideVt.sh completed"
