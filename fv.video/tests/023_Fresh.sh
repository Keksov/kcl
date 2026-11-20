#!/usr/bin/env bash
# 023_Fresh.sh - fv P3 stage 3a-1, headless: fresh non-ASCII rows (10.11), the
# wide fast path (10.12) and the uniform-symbol rows (10.2):
#   * the wide fast path = the walk: _text's cells, wide flag and marker list
#     with the fast path against the walk alone (seeded random text: CJK,
#     kana, Hangul, fullwidth, CJK punctuation mixed with ASCII, and with
#     everything that must refuse it: VS16, ZWJ, combining marks after a CJK
#     character, emoji, Cyrillic, controls, invalid UTF-8); the 5.1 loop
#     forced; patsub_replacement off;
#   * _wrows on fresh pages (every text new to the cache) = one writeBuf per
#     row with the walk (today's path): cells, symbols, side map, wide flags,
#     versions, damage, rc, RESULT over seeded random pages of ASCII,
#     Cyrillic, Greek, Latin-1, CJK, Hangul, emoji, ZWJ, VS16, combining
#     marks, controls (\x1f too) and invalid UTF-8 (one invalid row among
#     valid ones), refused rows, clips, X / Y off the edges, ASCII mode, the
#     loops forced, a nearly full text cache, a page of 300 rows (two
#     batches); the same page again (cached) = the same screen;
#   * the calls: a fresh Cyrillic / CJK page takes one validity check and no
#     writeBuf, a cached CJK page none of either, an emoji page one walk per
#     row;
#   * _wrowsu X Y W TEXTS SYMS = per row a writeBuf clipped to [X, X+W) plus
#     spaces to X+W, in the one symbol: a wide pair at the edge at every
#     width, seeded random rows (fresh and cached), clips, refused symbols,
#     W 0 and negative, RESULT; the names rc 3; no screen rc 1;
#   * VT-model frames, the installed UTF-8 locales (013's list, also with
#     globasciiranges off), caller state, zero forks (PATH='').

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "023: fresh rows (10.11), the wide fast path (10.12), uniform rows (10.2)"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81' ZWJ=$'\xe2\x80\x8d' VS16=$'\xef\xb8\x8f'
for c in "$HAN" "$JI" "$EMO" '报' '告' '文' '件' '한' 'カ' 'Ａ' '。'; do VT_WD[$c]=2; done
VT_WD[$ACU]=0 VT_PICT[$EMO]=1

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
snap() {
    local y k i
    local -a ks=()
    S=''
    for (( y = 0; y < __FV_VS_H; y++ )); do
        S+="${__FV_VS_CH[y]}|${__FV_VS_AT[y]}|${__FV_VS_DX1[y]-}-${__FV_VS_DX2[y]-}|${__FV_VS_WIDE[y]}|${__FV_VS_XV[y]+v}"$'\n'
    done
    for k in "${!__FV_VS_X[@]}"; do
        for (( i = ${#ks[@]}; i > 0; i-- )); do
            if [[ ${ks[i-1]} < "$k" ]]; then break; fi
            ks[i]=${ks[i-1]}
        done
        ks[i]=$k
    done
    for k in "${ks[@]}"; do S+="$k=${__FV_VS_X[$k]};"; done
}
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
WB=("${__FV_VS_WB[@]}")
nofast() { __FV_VS_WB=(); }
fast() { __FV_VS_WB=("${WB[@]}"); }
SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz

# random text: KIND 0 ASCII, 1 narrow non-ASCII (Cyrillic, Greek, Latin-1, box),
# 2 CJK-ish (the wide fast path), 3 anything (emoji, ZWJ, VS16, marks,
# controls, invalid), 4 CJK with one character that refuses the fast path
NARR=('ж' 'Ё' 'Отчёт' 'λ' 'Ω' 'é' 'ß' '¶' '─' '┐' 'a' 'b' ' ' '.' '_' '7')
WIDE=("$HAN" "$JI" '报' '告' '한' '국' 'カ' 'ひ' 'ゟ' 'Ａ' '￥' '。' '「' '豈' 'a' ' ' '1' '_')
ANY=("$EMO" "👨${ZWJ}👩" "❤$VS16" "$ACU" $'\xe3\x82\x99' '🇩🇪' '⌚' '👍🏽' $'\xe2\x80\x8b' "$ZWJ" "$VS16"
     $'\x01' $'\t' $'\x1f' $'\x7f' $'\xc2\x85' $'\xff' $'\xe2\x94' $'\x80' 'ж' "$HAN" 'a' ' ')
BREAK=("$VS16" "$ZWJ" "$ACU" $'\xe3\x82\x99' "$EMO" 'ж' $'\x01' $'\xff' '⌚' $'\xe2\x80\x8b')
rtext() {   # KIND LEN -> REPLY
    local i s=''
    for (( i = 0; i < $2; i++ )); do
        case $1 in
            0) s+=${SYMS:RANDOM % 62:1} ;;
            1) s+=${NARR[RANDOM % ${#NARR[@]}]} ;;
            2|4) s+=${WIDE[RANDOM % ${#WIDE[@]}]} ;;
            *) s+=${ANY[RANDOM % ${#ANY[@]}]} ;;
        esac
    done
    if (( $1 == 4 )); then i=$(( RANDOM % (${#s} + 1) )); s=${s:0:i}${BREAK[RANDOM % ${#BREAK[@]}]}${s:i}; fi
    REPLY=$s
}

# --- the wide fast path = the walk -------------------------------------------------
tx1() {   # TEXT -> REPLY = cells|w|markers (the caller sets fast / nofast)
    local __fvv_t=$1 __fvv_w=0 __fvv_xl=''
    __FV_VS_TC=() __FV_VS_TX=()
    if [[ $__fvv_t == $__FV_VS_PNA ]]; then fv.video._text; fi
    REPLY="$__fvv_t|$__fvv_w|$__fvv_xl"
}
txcmp() {   # TITLE N
    local i t a b fail='' nw=0
    for (( i = 0; i < $2; i++ )); do
        rtext $(( i % 5 )) $(( RANDOM % 16 )); t=$REPLY
        nofast; fv.video._g tx1 "$t"; a=$REPLY
        fast; fv.video._g tx1 "$t"; b=$REPLY
        if [[ $a == *$'\x01'* && $a != *$'\x02'* ]]; then nw=$(( nw + 1 )); fi
        if [[ $a != "$b" ]]; then fail+=" [$(printf %q "$t"): walk $(printf %q "$a") fast $(printf %q "$b")]"; fi
        if (( ${#fail} > 600 )); then break; fi
    done
    check "$1 ($2 random texts, $nw with plain wide cells only)" "" "$fail"
}
FV_SCREEN_W=40 FV_SCREEN_H=4 fv.video.initScreen
AMP0=$__FV_VS_AMP   # (1 from bash 5.2 on: put back after forcing the loops)
RANDOM=2301
txcmp "_text with the wide fast path = the walk alone: cells, wide flag, markers" 400
__FV_VS_AMP=0
RANDOM=2302
txcmp "the same with the bash 5.1 loop (__FV_VS_AMP=0)" 150
__FV_VS_AMP=$AMP0
if shopt -q patsub_replacement 2>/dev/null; then
    shopt -u patsub_replacement
    RANDOM=2303
    txcmp "the same with patsub_replacement off" 150
    shopt -s patsub_replacement
fi
r=''
for t in "a${HAN}" "${HAN}${VS16}" "${HAN}${ZWJ}${JI}" "${HAN}${ACU}" 'か'$'\xe3\x82\x99' "${EMO}${HAN}" "${HAN}"$'\xf0\xa0\x80\x80'; do
    nofast; fv.video._g tx1 "$t"; a=$REPLY
    fast; fv.video._g tx1 "$t"; [[ $a == "$REPLY" ]] && r+=1 || r+=0
done
check "the joins after a CJK character the fast path must refuse (VS16, ZWJ, a combining mark, the kana voicing mark, an emoji, CJK Ext B) give the walk's cells" "1111111" "$r"

# --- _wrows on fresh pages = writeBuf per row with the walk ----------------------------
# ground W H ASCII CLIP — the screen with wide cells and markers on some rows, shown
ground() {
    if (( $3 )); then FV_ASCII=1 FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen
    else FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; fi
    fv.video.fillRect 0 0 "$1" "$2" 1 '░'
    fv.video.writeStr 3 2 "${HAN}${JI}${HAN}${JI}" 2
    fv.video.writeStr 0 5 "a${EMO}bc e${ACU}x" 3
    fv.video.writeStr $(( $1 - 3 )) $(( $2 - 1 )) "${JI}" 4
    fv.video.updateScreen
    case $4 in
        1) fv.video.setClip 2 1 $(( $1 - 4 )) $(( $2 - 2 )) ;;
        2) fv.video.setClip 0 4 "$1" 7 ;;
    esac
    __FV_VS_TC=() __FV_VS_TX=()
}
attrs() {   # TEXT KIND -> REPLY: KIND 0 width in random symbols, 7 short, 8 long, 9 a bad symbol
    local w i s=''
    fv.video.strWidth "$1"; w=$RESULT
    case $2 in 7) w=$(( w > 0 ? w - 1 : 1 )) ;; 8) w=$(( w + 1 )) ;; esac
    for (( i = 0; i < w; i++ )); do s+=${SYMS:RANDOM % 62:1}; done
    if (( $2 == 9 )); then s+='#'; fi
    REPLY=$s
}
# page N KINDS -> T A: N rows, the kinds picked from KINDS; one row in ~6
# invalid / controls when KINDS has no 3; a refused row now and then
page() {
    local k kind
    T=() A=()
    for (( k = 0; k < $1; k++ )); do
        kind=${2:RANDOM % ${#2}:1}
        if (( RANDOM % 9 == 0 )); then kind=3; fi
        rtext "$kind" $(( 1 + RANDOM % 20 )); T[k]=$REPLY
    done
    if (( RANDOM % 3 == 0 )); then T[RANDOM % $1]=$'Отчёт_\xff_bad.txt'; fi
    for k in "${!T[@]}"; do
        if (( RANDOM % 25 == 0 )); then attrs "${T[k]}" $(( 7 + RANDOM % 3 )); else attrs "${T[k]}" 0; fi
        A[k]=$REPLY
    done
}
abrun() {   # TITLE N
    local i W H asc clip x y r1 m want got s1 nref=0 fail='' kinds
    for (( i = 0; i < $2; i++ )); do
        case $(( i % 4 )) in 0) W=30 H=10 ;; 1|2) W=80 H=24 ;; *) W=200 H=50 ;; esac
        asc=$(( i % 9 == 8 )) clip=$(( RANDOM % 3 ))
        x=$(( RANDOM % 12 - 4 )) y=$(( RANDOM % 6 - 3 ))
        case $(( i % 5 )) in 0) kinds=1 ;; 1) kinds=2 ;; 2) kinds=12 ;; 3) kinds=0123 ;; *) kinds=124 ;; esac
        ground "$W" "$H" "$asc" "$clip"
        page $(( 1 + RANDOM % (H + 2) )) "$kinds"
        # (the reference: one public writeBuf per row, the walk alone, a cold cache)
        ground "$W" "$H" "$asc" "$clip"
        nofast
        r1=0 m=0
        for k in "${!T[@]}"; do
            if fv.video.writeBuf "$x" "$(( y + k ))" "${T[k]}" "${A[k]-}" 2>/dev/null; then
                if (( RESULT > m )); then m=$RESULT; fi
            else r1=1; fi
        done
        fast
        if (( r1 )); then want="2[]"; nref=$(( nref + 1 )); else want="0[$m]"; fi
        snap; s1=$S
        ground "$W" "$H" "$asc" "$clip"
        if (( ${PREFILL:-0} )); then for (( k = 0; k < PREFILL; k++ )); do __FV_VS_TC[x$k$'\xd0\xb6']=x; done; fi
        fv.video._wrows "$x" "$y" T A 2>/dev/null; got="$?[$RESULT]"
        snap
        if [[ $S != "$s1" || $got != "$want" ]]; then fail+=" [i=$i ${W}x$H ascii=$asc clip=$clip x=$x y=$y kinds=$kinds got=$got want=$want]"; fi
        # the same page again: from the cache
        ground "$W" "$H" "$asc" "$clip"
        fv.video._wrows "$x" "$y" T A 2>/dev/null
        ground "$W" "$H" "$asc" "$clip"
        fv.video._wrows "$x" "$y" T A 2>/dev/null; got="$?[$RESULT]"
        snap
        if [[ $S != "$s1" || $got != "$want" ]]; then fail+=" [cached i=$i got=$got want=$want]"; fi
        if (( ${#fail} > 800 )); then break; fi
    done
    unset FV_ASCII
    check "$1 ($2 random pages, $nref with a refused row)" "" "$fail"
}
RANDOM=2311
abrun "_wrows on fresh pages = one writeBuf per row with the walk (cells, symbols, side map, flags, versions, damage, rc, RESULT); the same page again from the cache" 160
__FV_VS_AMP=0
RANDOM=2312
abrun "the same with the bash 5.1 loops (__FV_VS_AMP=0)" 40
__FV_VS_AMP=$AMP0
PREFILL=500
RANDOM=2313
abrun "the same with the text cache nearly full (500 entries before the page)" 30
PREFILL=0

# a page of 300 fresh rows on a 40x310 screen: two batches (256 + the rest)
ground 40 310 0 0
T=() A=()
for (( k = 0; k < 300; k++ )); do T[k]="Отчёт_$k $HAN"; attrs "${T[k]}" 0; A[k]=$REPLY; done
ground 40 310 0 0
nofast
for k in "${!T[@]}"; do fv.video.writeBuf 1 "$k" "${T[k]}" "${A[k]}"; done
fast
snap; s1=$S
ground 40 310 0 0
fv.video._wrows 1 0 T A; r="$?[$RESULT]"
snap
check "300 fresh rows (two batches) = writeBuf per row" "0[12] same" "$r $([[ $S == "$s1" ]] && printf same)"

# --- the calls -------------------------------------------------------------------------
declare -gA CNT=()
wrap() {   # FUNC: count its calls
    local src
    src=$(declare -f "$1")
    eval "__cnt_${src}"
    eval "$1() { CNT[$1]=\$(( \${CNT[$1]:-0} + 1 )); __cnt_$1 \"\$@\"; }"
}
for f in fv.video.writeBuf fv.video._san2 fv.video._textw fv.video._wfb; do wrap "$f"; done
calls() {   # KIND -> REPLY = writeBuf/_san2/_textw on a fresh 21-row page, then the same page cached
    local k
    ground 80 24 0 0
    T=() A=()
    for (( k = 0; k < 21; k++ )); do
        case $1 in
            cyr) T[k]=" Отчёт_квартал_$k.txt   $(( k * 37 ))" ;;
            cjk) T[k]=" 报告文件_$k.txt   $(( k * 37 ))" ;;
            emo) T[k]=" a${EMO}b_$k" ;;
        esac
        attrs "${T[k]}" 0; A[k]=$REPLY
    done
    __FV_VS_TC=() __FV_VS_TX=() CNT=()
    fv.video._wrows 0 1 T A
    REPLY="${CNT[fv.video.writeBuf]:-0}/${CNT[fv.video._san2]:-0}/${CNT[fv.video._textw]:-0}"
    CNT=()
    fv.video._wrows 0 1 T A
    REPLY+=" ${CNT[fv.video.writeBuf]:-0}/${CNT[fv.video._san2]:-0}/${CNT[fv.video._textw]:-0}"
}
calls cyr; r=$REPLY
calls cjk; r+=" | $REPLY"
calls emo; r+=" | $REPLY"
check "the calls of a 21-row page (writeBuf / validity checks / walks), fresh then cached: Cyrillic, CJK, emoji" "0/1/0 0/0/0 | 0/1/0 0/0/0 | 0/1/21 0/0/0" "$r"
for f in fv.video.writeBuf fv.video._san2 fv.video._textw fv.video._wfb; do
    src=$(declare -f "__cnt_$f"); eval "${src#__cnt_}"; unset -f "__cnt_$f"
done

# --- _wrowsu = writeBuf clipped to [X, X+W) + spaces ----------------------------------
# ref X Y W TEXTS SYMS (the arrays' names) -> the reference writes; REPLY = rc[RESULT]
ref() {
    local -n rt=$4 rs=$5
    local k s w cx1 cy1 cx2 cy2 e=0 m=0 c=$3 sy
    cx1=$__FV_VS_CX1 cy1=$__FV_VS_CY1 cx2=$__FV_VS_CX2 cy2=$__FV_VS_CY2
    if (( c < 1 )); then c=0; fi
    for k in "${!rt[@]}"; do
        sy=${rs[k]-}
        m=$c
        if [[ ${#sy} != 1 || $sy != [$SYMS] ]]; then e=1; continue; fi
        (( c )) || continue
        fv.video.strWidth "${rt[k]}"; w=$RESULT
        printf -v s '%*s' "$w" ''; s=${s// /$sy}
        if (( $1 + c > cx1 && $1 < cx2 )); then
            fv.video.setClip $(( $1 > cx1 ? $1 : cx1 )) "$cy1" $(( $1 + c < cx2 ? $1 + c : cx2 )) "$cy2"
            fv.video.writeBuf "$1" $(( $2 + k )) "${rt[k]}" "$s"
            fv.video.setClip "$cx1" "$cy1" "$cx2" "$cy2"
        fi
        if (( w < c )); then printf -v s '%*s' $(( c - w )) ''; fv.video.writeStr $(( $1 + w )) $(( $2 + k )) "$s" "$sy"; fi
    done
    if (( e )); then REPLY='2[]'; else REPLY="0[$m]"; fi
}
# edges: a row of wide characters over a row with wide cells, every W
r='' fail=''
for asc in 0 1; do
    for (( W = -1; W <= 10; W++ )); do
        for x in 0 1 7; do
            TT=("a${HAN}${JI}${HAN}x" "${EMO}${HAN}e${ACU}" "") SS=(3 4 5)
            ground 12 8 "$asc" 0
            ref "$x" 1 "$W" TT SS; want=$REPLY
            snap; s1=$S
            ground 12 8 "$asc" 0
            fv.video._wrowsu "$x" 1 "$W" TT SS; got="$?[$RESULT]"
            snap
            if [[ $S != "$s1" || $got != "$want" ]]; then fail+=" [ascii=$asc W=$W x=$x got=$got want=$want]"; fi
        done
    done
done
unset FV_ASCII
check "_wrowsu: a wide pair and a wide marker at the edge at every width W -1..10, X 0 / 1 / 7, ASCII mode too (= writeBuf clipped to [X, X+W) + spaces)" "" "$fail"
RANDOM=2321
fail='' n=0 nref=0
for (( i = 0; i < 160; i++ )); do
    case $(( i % 3 )) in 0) W=30 H=10 ;; 1) W=80 H=24 ;; *) W=200 H=50 ;; esac
    asc=$(( i % 8 == 7 )) clip=$(( RANDOM % 3 ))
    x=$(( RANDOM % 14 - 5 )) y=$(( RANDOM % 6 - 3 )) c=$(( RANDOM % 50 - 2 ))
    ground "$W" "$H" "$asc" "$clip"
    page $(( 1 + RANDOM % (H + 2) )) 01234
    S2=()
    for k in "${!T[@]}"; do
        case $(( RANDOM % 30 )) in 0) S2[k]='#' ;; 1) S2[k]=ab ;; 2) ;; *) S2[k]=${SYMS:RANDOM % 62:1} ;; esac
    done
    warm=$(( RANDOM % 2 ))
    ground "$W" "$H" "$asc" "$clip"
    ref "$x" "$y" "$c" T S2 2>/dev/null; want=$REPLY
    snap; s1=$S
    ground "$W" "$H" "$asc" "$clip"
    if (( warm )); then for k in "${!T[@]}"; do fv.video.strWidth "${T[k]}"; done; fi
    fv.video._wrowsu "$x" "$y" "$c" T S2; got="$?[$RESULT]"
    snap
    n=$(( n + 1 ))
    if [[ $want == 2* ]]; then nref=$(( nref + 1 )); fi
    if [[ $S != "$s1" || $got != "$want" ]]; then fail+=" [i=$i ${W}x$H ascii=$asc clip=$clip x=$x y=$y W=$c warm=$warm got=$got want=$want]"; fi
    if (( ${#fail} > 800 )); then break; fi
done
unset FV_ASCII
check "_wrowsu = per row a writeBuf clipped to [X, X+W) + spaces in the one symbol: $n random cases ($nref with a refused symbol; fresh and warm cache, clips, X / Y off the edges, W -2..47, ASCII mode)" "" "$fail"
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen; fv.video.updateScreen
snap; s0=$S
declare -A MI=(['INJ=1']=ab); unset INJ
T=(ab) S2=(1) r=''
for nm in "'' S2" "T ''" '1T S2' 'T S-2' 'T[0] S2' '__fvv_t S2' 'T __FVx' 'RESULT S2' 'T RESULT' 'MI S2' 'T MI'; do
    eval "set -- $nm"
    RESULT=keep; fv.video._wrowsu 0 0 5 "$1" "$2"; r+="$?[$RESULT]"
done
T=() S2=(); unset NOSUCH
fv.video._wrowsu 0 0 5 T S2; r+=" $?[$RESULT]"
fv.video._wrowsu 0 0 5 NOSUCH NOSUCH; r+="$?[$RESULT]"
snap
check "_wrowsu: names refused rc 3 (no key evaluated, nothing written, no message); no rows RESULT 0" \
    "3[]3[]3[]3[]3[]3[]3[]3[]3[]3[]3[] 0[0]0[0] same" "$r ${INJ-}$([[ $S == "$s0" ]] && printf same)"
r=$(__FV_VS_H=0; T=(a) S2=(1); fv.video._wrowsu 0 0 3 T S2 2>/dev/null; printf '%s[%s]' "$?" "$RESULT")
check "_wrowsu: no screen rc 1, RESULT ''" "1[]" "$r"

# --- frames ------------------------------------------------------------------------------
kt_test_start "VT model: fresh Cyrillic, CJK and emoji pages by _wrows and _wrowsu over rows with wide cells; incremental = forced"
ground 30 10 0 0
vt_init 30 10; frame force >/dev/null
T=(" Отчёт_1.txt" " 报告文件_2.txt" " a${EMO}b" "e${ACU}x ${HAN}" ' ') A=()
for k in "${!T[@]}"; do attrs "${T[k]}" 0; A[k]=$REPLY; done
fv.video._wrows 1 1 T A
S2=(3 4 5 6 7)
fv.video._wrowsu 2 5 9 T S2
fv.video.setClip 4 0 20 10
T=(" Ёлка_3.txt" " 文件_${JI}${JI}${JI}${JI}${JI}${JI}${JI}${JI}") A=(); for k in 0 1; do attrs "${T[k]}" 0; A[k]=$REPLY; done
fv.video._wrows 3 2 T A
fv.video._wrowsu 3 7 15 T S2
fv.video.resetClip
if frame && same_as_force; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "$VT_ERR"; fi

# --- installed UTF-8 locales ---------------------------------------------------------
LOCSCENE=$(cat <<'EOF'
FV_SCREEN_W=30 FV_SCREEN_H=6
exec {fd}>/dev/null; FV_VIDEO_OUT_FD=$fd
fv.video.initScreen
T=(' Отчёт_1.txt' ' 报告文件，。_2' $' ＡＢ\xe2\x80\x8bc' ' カタカナ한국' $' x\xc4\x81y') A=('000000000000' '111111111111111' '222222' '3333333333333' '4444')
fv.video._wrows 0 0 T A; r="$?.$RESULT."
S2=(5 6 7 8 9)
fv.video._wrowsu 0 1 13 T S2; r+="$?.$RESULT."
fv.video.clusters "${T[1]}" CL CW; r+="$RESULT.${CW[*]}."
for y in 0 1 2 3 4 5; do fv.video.getRow $y; r+="[$RESULT|$REPLY]"; done
printf '%s' "$r"
EOF
)
REF=$(LC_ALL=C.UTF-8 "$BASH" -c "source '$FVV_TESTS_DIR/../fv.video.sh'
$LOCSCENE" 2>&1)
check "locales: the reference scene under C.UTF-8 (a fresh page by _wrows, _wrowsu, clusters)" "0.15.0.13.9.1 2 2 2 2 2 2 1 1." "${REF%%\[*}"
nloc=0
for l in en_US.UTF-8 de_DE.UTF-8 en_GB.UTF-8 ru_RU.UTF-8 fr_FR.UTF-8; do
    LC_ALL=$l "$BASH" -c 'x=$'"'"'\xd0\xb6'"'"'; (( ${#x} == 1 ))' 2>/dev/null || continue
    nloc=$(( nloc + 1 ))
    for opt in '' 'shopt -u globasciiranges'; do
        kt_test_start "locales: the same scene under $l ${opt:+($opt)} (bash $BASH_VERSION)"
        OUT=$(LC_ALL=$l "$BASH" -c "$opt
source '$FVV_TESTS_DIR/../fv.video.sh'
$LOCSCENE" 2>&1)
        if [[ $OUT == "$REF" ]]; then kt_test_pass "ok"; else kt_test_fail "[$OUT] vs [$REF]"; fi
    done
done
if (( nloc == 0 )); then kt_test_start "locales: skipped (no other UTF-8 locale installed)"; kt_test_pass "skipped"; fi

# --- caller state ----------------------------------------------------------------------
SCENE='
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r=""
FV_SCREEN_W=14 FV_SCREEN_H=4 fv.video.initScreen
fv.video.writeStr 0 3 "a$p 漢b" 1
T=("*[a]?$p" "漢字 ab" "$p$p" "x") A=("123456" "1234567" "zz" "0")
fv.video._wrows 1 0 T A; r+="$?.$RESULT."
S2=(1 2 3 4)
fv.video._wrowsu 2 0 5 T S2; r+="$?.$RESULT."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$TMPF" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1 2 3; do printf " [%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done
'
STATE='printf "%s|%s|%s|%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
run() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/fresh.out'
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
check "caller state: the reference scene" "0.7.0.5.0." "${ref%% \$*}"
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'IFS=' 'set -eu -o pipefail' 'export LC_ALL=C' \
    'shopt -u patsub_replacement 2>/dev/null || :' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C"; do
    kt_test_start "caller state: same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done

# --- zero forks ------------------------------------------------------------------
kt_test_start "PATH='': _wrows on fresh pages (Cyrillic, CJK, emoji, invalid, a control), _wrowsu, the loops, an update"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=16 FV_SCREEN_H=5
fv.video.initScreen
fv.video.writeStr 0 1 'a${HAN}b' 1
PATH=''
r=''
T=('жук' '报告文件' 'x${EMO}' \$'a\\xffb' \$'c\\x1fd') A=(123 45678901 123 123 123)
fv.video._wrows 0 0 T A; r+=\$?\$RESULT
S2=(1 2 3 4 5)
fv.video._wrowsu 1 0 6 T S2; r+=\$?\$RESULT
__FV_VS_AMP=0; __FV_VS_TC=()
T=('Ёлка' '文件文件') A=(1234 12345678)
fv.video._wrows 2 0 T A; r+=\$?\$RESULT
fv.video.updateScreen; r+=\$?
printf '%s' \"\$r\"" 2>&1)
want="0806080"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

exec {nullfd}>&-
kt_test_log "023_Fresh.sh completed"
