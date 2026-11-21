#!/usr/bin/env bash
# 025_WidePaths.sh - fv P3 stage 3v-1, headless: the wide write paths of the
# batch entries against the path they replace (kcl c3ed3a2's _wrows, _wrw,
# _wrb1 and _wrowsu, kept below verbatim as old._wrows / old._wrw /
# old._wrb1 / old._wrowsu and swapped in for the reference run):
#   * V1 (_wrb1): a fresh batch whose non-ASCII characters are all plain wide
#     takes the wide fast path once over the rows joined (without the
#     substitution, bash 5.1: the test once, the loop per row); the cache
#     answers (cells, marker lists) equal the per-row classes';
#   * V2 (_wrowsu): a wide cache hit read inline, the pad inline, a plain wide
#     row (no marker in the text or the row, inside the clip, no wide pair of
#     the row cut at X or X+W) spliced in place instead of _putw;
#   * V5 (_wrows' _wrw): a narrow row written into a row whose wide cells
#     are plain (WIDE 1), inside the clip, no wide pair cut at its edges,
#     spliced in place instead of _putw;
#   the A/B: seeded random scenes (rows with and without wide cells, wide
#   pairs at every edge, markers and emoji rows that must take the old path,
#   Cyrillic, controls, invalid UTF-8, clips with edges on wide pairs, cuts,
#   pads, refused rows, ASCII mode, fresh / warm / cached texts, narrow rows
#   over plain-wide rows), then the same writes again from the cache: every
#   buffer (CH AT WIDE X XV WNEW DX, OCH OAT OXV after the frame, XSEQ, the
#   text cache's answers), rc / RESULT and the frame bytes equal the old
#   path's; an edge sweep (W 1..10, X 0..4, pairs at both parities); a
#   narrow sweep (one _wrows of N 1..10 at X 0..4 into CJK rows at both
#   parities, WNEW cleared before) and a narrow write over every pair (WIDE
#   0, WNEW 1, the damage); the bash 5.1 loop (__FV_VS_AMP=0) and
#   patsub_replacement off;
#   * the calls: a fresh CJK page takes one _wfb and no _putw, the cached
#     page no _wrx, a narrow page beside a CJK one a _wrw and a _wrw5 per row
#     and no _putw, an emoji page one _putw per row; without the
#     substitution one _wfb (the test), the loop per row, never over the
#     rows joined;
#   * caller state (also a caller IFS holding \x01 before the screen and
#     around the writes: initScreen, the cache misses of the single-row
#     writes) and zero forks (PATH='').

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "025: the wide write paths (P3 3v V1, V2, V5) = the old _putw path"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81' VS16=$'\xef\xb8\x8f'

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
exec {nullfd}>/dev/null
FV_VIDEO_OUT_FD=$nullfd

# --- the reference: kcl c3ed3a2's batch entries, verbatim ------------------------------
old._wrows() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ -z $3 || -z $4 || $3$4 == *[!_$__FV_VS_SYMS]* || $3 == [0123456789]* || $4 == [0123456789]* || $3 == __[fF][vV]* || $4 == __[fF][vV]* || $3 == RESULT || $4 == RESULT ]]; then RESULT=''; return 3; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeBuf; return; fi
    local -n __fvv_tt=$3 __fvv_aa=$4
    local IFS=0 __fvv_x __fvv_y __fvv_t __fvv_a='' __fvv_b __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r __fvv_k __fvv_st=0 __fvv_sa=0 __fvv_ss=0 __fvv_s=0 __fvv_m=0 __fvv_e=0 __fvv_bt=0
    # (joined with '0': an associative array's attributes are 'A', no other's hold one)
    if [[ ${__fvv_tt[*]@a}${__fvv_aa[*]@a} == *A* ]]; then RESULT=''; return 3; fi
    if [[ ${__fvv_tt[*]-} == $__FV_VS_PNA ]]; then __fvv_st=1 __fvv_ss=1; fi
    if [[ ${__fvv_aa[*]-} == *[!$__FV_VS_SYMS]* ]]; then __fvv_sa=1 __fvv_ss=1; fi
    for __fvv_k in "${!__fvv_tt[@]}"; do
        __fvv_y=$(( $2 + __fvv_k )) __fvv_x=$1 __fvv_t=${__fvv_tt[__fvv_k]} __fvv_b=${__fvv_aa[__fvv_k]-}
        if (( __fvv_ss )); then
            if (( __fvv_st )) && [[ $__fvv_t == $__FV_VS_PNA ]]; then
                # (writeBuf's narrow cache hit; a wide hit or a miss: _wrx)
                __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
                if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._wrx || __fvv_s=1; fi
            fi
            if (( __fvv_sa )) && [[ $__fvv_b == *[!$__FV_VS_SYMS]* ]]; then __fvv_s=1; fi
        fi
        if (( __fvv_s || ${#__fvv_b} != ${#__fvv_t} )); then
            __fvv_s=0 __fvv_w=0 __fvv_xl=''
            if fv.video.writeBuf "$__fvv_x" "$__fvv_y" "${__fvv_tt[__fvv_k]}" "$__fvv_b"; then
                if (( RESULT > __fvv_m )); then __fvv_m=$RESULT; fi
            else __fvv_e=1; fi
            continue
        fi
        if (( ${#__fvv_t} > __fvv_m )); then __fvv_m=${#__fvv_t}; fi
        if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 )); then __fvv_w=0 __fvv_xl=''; continue; fi
        if (( __fvv_w || __FV_VS_WIDE[__fvv_y] )); then fv.video._wrw; continue; fi
        # (writeBuf's narrow row, as in its body)
        __fvv_n=${#__fvv_t} __fvv_o=0
        if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 || ! __fvv_n )); then fv.video._putc || continue; fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_b:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
    done
    if (( __fvv_e )); then RESULT=''; return 2; fi
    RESULT=$__fvv_m
}
old._wrb1() {
    local LC_ALL=C - IFS=$__FV_VS_US __fvv_t='' __fvv_j __fvv_f=1 __fvv_a4=0 __fvv_u=0 __fvv_s __fvv_p
    if [[ $__fvv_pe == 11 ]] && (( ! FV_VIDEO_ASCII )); then __fvv_u=1; fi
    for __fvv_j in "${!__fvv_tt[@]}"; do
        if (( __fvv_j < __fvv_k )); then continue; fi
        __fvv_q=${__fvv_tt[__fvv_j]}
        if [[ $__fvv_q != $__FV_VS_PNA || -n ${__FV_VS_TC[$__fvv_q]+1} ]]; then continue; fi
        __fvv_ms[__fvv_c]=$__fvv_q __fvv_c=$(( __fvv_c + 1 ))
        if [[ $__fvv_q == *[[:cntrl:]]* ]]; then __fvv_q=${__fvv_q//[[:cntrl:]]/"?"}; fi
        __fvv_t+=$__fvv_q$__FV_VS_US
        if (( __fvv_c >= 256 )); then break; fi
    done
    fv.video._san2
    set -f
    __fvv_mc=($__fvv_t)
    if (( ${#__fvv_mc[@]} != __fvv_c )); then __fvv_r=1; return 0; fi
    if (( ${#__FV_VS_TC[@]} + __fvv_c > 512 )); then fv.video._tcclear; fi
    for (( __fvv_i = 0; __fvv_i < __fvv_c; __fvv_i++ )); do
        __fvv_t=${__fvv_mc[__fvv_i]} __fvv_q=${__fvv_ms[__fvv_i]}
        if (( __fvv_f )) || fv.video._fast "$__fvv_t"; then __FV_VS_TC[$__fvv_q]=$__fvv_t
        elif [[ $__fvv_t == *[$'\xf0'-$'\xf4']* ]]; then __fvv_mw[__fvv_i]=1
        elif fv.video._wfb; then __FV_VS_TC[$__fvv_q]=$'\x03'$__fvv_t __FV_VS_TX[$__fvv_q]=''
        else __fvv_mw[__fvv_i]=0; fi
    done
}
old._wrowsu() {
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]; then fv.video._g "$FUNCNAME" "$@"; return; fi
    if [[ -z $4 || -z $5 || $4$5 == *[!_$__FV_VS_SYMS]* || $4 == [0123456789]* || $5 == [0123456789]* || $4 == __[fF][vV]* || $5 == __[fF][vV]* || $4 == RESULT || $5 == RESULT ]]; then RESULT=''; return 3; fi
    if (( ! __FV_VS_H )); then fv.video._noscr writeRows; return; fi
    local -n __fvv_tt=$4 __fvv_sy=$5
    local IFS=0 __fvv_x __fvv_y __fvv_t __fvv_a __fvv_b='' __fvv_w=0 __fvv_xl='' __fvv_n __fvv_o __fvv_r __fvv_k __fvv_c=$3 __fvv_p='' __fvv_m=0 __fvv_e=0 __fvv_bt=0 __fvv_st=0
    if [[ ${__fvv_tt[*]@a}${__fvv_sy[*]@a} == *A* ]]; then RESULT=''; return 3; fi
    if (( __fvv_c < 1 )); then __fvv_c=0; fi
    if [[ ${__fvv_tt[*]-} == $__FV_VS_PNA ]]; then __fvv_st=1; fi
    for __fvv_k in "${!__fvv_tt[@]}"; do
        __fvv_y=$(( $2 + __fvv_k )) __fvv_a=${__fvv_sy[__fvv_k]-} __fvv_m=$__fvv_c
        if [[ $__fvv_a != [$__FV_VS_SYMS] ]]; then __fvv_e=1; continue; fi
        if (( __fvv_y < __FV_VS_CY1 || __fvv_y >= __FV_VS_CY2 || ! __fvv_c )); then continue; fi
        __fvv_x=$1 __fvv_t=${__fvv_tt[__fvv_k]}
        if (( __fvv_st )) && [[ $__fvv_t == $__FV_VS_PNA ]]; then
            __FV_VS_V=${__FV_VS_TC[$__fvv_t]-$'\x04'}
            if [[ $__FV_VS_V == [!$'\x03\x04']* ]]; then __fvv_t=$__FV_VS_V; else fv.video._wrx || fv.video._textx; fi
        fi
        __fvv_n=${#__fvv_t}
        if (( __fvv_n != __fvv_c )); then fv.video._wrcut; fi
        if (( __fvv_w || __FV_VS_WIDE[__fvv_y] )); then
            fv.video._putw
            __fvv_w=0 __fvv_xl=''
            continue
        fi
        # (writeStr's narrow row, as in its body: the symbol's fill string)
        if [[ -z ${__FV_VS_FILL[$__fvv_a]+1} ]]; then __FV_VS_FILL[$__fvv_a]=${__FV_VS_SP// /$__fvv_a}; fi
        __fvv_n=$__fvv_c __fvv_o=0
        if (( __fvv_x < __FV_VS_CX1 || __fvv_x + __fvv_n > __FV_VS_CX2 )); then fv.video._putc || continue; fi
        __fvv_r=${__FV_VS_CH[__fvv_y]}
        __FV_VS_CH[__fvv_y]=${__fvv_r:0:__fvv_x}${__fvv_t:__fvv_o:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        __fvv_r=${__FV_VS_AT[__fvv_y]}
        __FV_VS_AT[__fvv_y]=${__fvv_r:0:__fvv_x}${__FV_VS_FILL[$__fvv_a]:0:__fvv_n}${__fvv_r:__fvv_x+__fvv_n}
        if (( ${__FV_VS_DX1[__fvv_y]-99999} > __fvv_x )); then __FV_VS_DX1[__fvv_y]=$__fvv_x; fi
        if (( ${__FV_VS_DX2[__fvv_y]-0} < __fvv_x + __fvv_n )); then __FV_VS_DX2[__fvv_y]=$(( __fvv_x + __fvv_n )); fi
    done
    if (( __fvv_e )); then RESULT=''; return 2; fi
    RESULT=$__fvv_m
}
old._wrw() {
    if (( __fvv_w )); then fv.video._lead; fi
    fv.video._putw
    __fvv_w=0 __fvv_xl=''
}

declare -A NEWSRC=() OLDSRC=()
for f in _wrows _wrw _wrb1 _wrowsu; do NEWSRC[$f]=$(declare -f "fv.video.$f"); OLDSRC[$f]=$(declare -f "old.$f"); OLDSRC[$f]="fv.video.${OLDSRC[$f]#old.}"; done
use() {   # old|new: the batch entries of c3ed3a2 or of this tree
    local f src
    for f in _wrows _wrw _wrb1 _wrowsu; do
        if [[ $1 == old ]]; then eval "${OLDSRC[$f]}"
        else eval "${NEWSRC[$f]}"; fi
    done
}
declare -gA CNT=()
wrap() {   # FUNC: count its calls
    local src
    src=$(declare -f "$1")
    eval "__cnt_${src}"
    eval "$1() { CNT[$1]=\$(( \${CNT[$1]:-0} + 1 )); __cnt_$1 \"\$@\"; }"
}
unwrap() {
    local src
    src=$(declare -f "__cnt_$1"); eval "${src#__cnt_}"; unset -f "__cnt_$1"
}

SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz
# random text: KIND 0 ASCII, 1 narrow non-ASCII, 2 CJK mixed with ASCII, 3
# anything (emoji, marks, VS16, controls, invalid), 4 CJK only
NARR=('ж' 'Ё' 'Отчёт' 'λ' 'é' '─' 'a' 'b' ' ' '.' '_' '7')
WIDE=("$HAN" "$JI" '报' '告' '文' '件' '한' 'カ' 'ひ' 'Ａ' '。' 'a' ' ' '1' '_')
CJK=("$HAN" "$JI" '报' '告' '文' '件' '한' 'カ' 'Ａ' '。')
ANY=("$EMO" "$ACU" "❤$VS16" $'\x01' $'\t' $'\xff' 'ж' "$HAN" 'a' ' ' '报')
rtext() {   # KIND LEN -> REPLY
    local i s=''
    for (( i = 0; i < $2; i++ )); do
        case $1 in
            0) s+=${SYMS:RANDOM % 62:1} ;;
            1) s+=${NARR[RANDOM % ${#NARR[@]}]} ;;
            2) s+=${WIDE[RANDOM % ${#WIDE[@]}]} ;;
            4) s+=${CJK[RANDOM % ${#CJK[@]}]} ;;
            *) s+=${ANY[RANDOM % ${#ANY[@]}]} ;;
        esac
    done
    REPLY=$s
}
attrs() {   # TEXT KIND -> REPLY: KIND 0 width in random symbols, 7 short, 9 a bad symbol
    local w i s=''
    fv.video.strWidth "$1"; w=$RESULT
    case $2 in 7) w=$(( w > 0 ? w - 1 : 1 )) ;; esac
    for (( i = 0; i < w; i++ )); do s+=${SYMS:RANDOM % 62:1}; done
    if (( $2 == 9 )); then s+='#'; fi
    REPLY=$s
}

# the case: the ground (GX GY GT GS: writeStr pieces), the warm texts (WARM),
# the clip (CLIP: "X1 Y1 X2 Y2" or ''), the writes (OPK 1 _wrowsu / 0 _wrows,
# OPX OPY OPW, the pages PT<o> PS<o> PA<o>), the cache keys to compare (KEYS)
ground() {   # W H ASCII
    local i t
    __FV_VS_XSEQ=0
    if (( $3 )); then FV_ASCII=1 FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen
    else FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; fi
    unset FV_ASCII
    fv.video.fillRect 0 0 "$1" "$2" 1 '░'
    for i in "${!GT[@]}"; do fv.video.writeStr "${GX[i]}" "${GY[i]}" "${GT[i]}" "${GS[i]}"; done
    fv.video.updateScreen
    __FV_VS_TC=() __FV_VS_TX=()
    for t in "${WARM[@]}"; do fv.video.writeStr 0 -1 "$t" 1; done
    if [[ -n $CLIP ]]; then fv.video.setClip $CLIP; fi
    # (CLRW=1: the rows' WNEW flags cleared, as the reader does, so that the
    # writes' own WNEW shows)
    if (( ${CLRW-0} )); then __FV_VS_WNEW=(); fi
}
gen_ground() {   # W H
    local y n j k
    GX=() GY=() GT=() GS=()
    for (( y = 0; y < $2; y++ )); do
        n=$(( RANDOM % 3 ))
        for (( j = 0; j < n; j++ )); do
            case $(( RANDOM % 10 )) in
                0|1|2|3|4) k=4 ;; 5|6) k=2 ;; 7) k=3 ;; *) k=1 ;;
            esac
            rtext "$k" $(( 1 + RANDOM % 14 ))
            GX+=("$(( RANDOM % ($1 + 2) - 2 ))") GY+=("$y") GT+=("$REPLY") GS+=("${SYMS:RANDOM % 62:1}")
        done
    done
}
gen_clip() {   # W H
    case $(( RANDOM % 6 )) in
        0|1) CLIP='' ;;
        2) CLIP="2 1 $(( $1 - 4 )) $(( $2 - 2 ))" ;;
        3) CLIP="0 2 $1 $(( $2 - 3 ))" ;;
        4) CLIP="5 0 6 $2" ;;
        *) CLIP="$(( RANDOM % ($1 / 2) )) 0 $(( $1 / 2 + RANDOM % ($1 / 2) )) $2" ;;
    esac
}
gen_ops() {   # W H KINDS
    local o n k nr kind c
    OPK=() OPX=() OPY=() OPW=() KEYS=() WARM=()
    n=$(( 1 + RANDOM % 3 ))
    for (( o = 0; o < n; o++ )); do
        local -n pt=PT$o ps=PS$o pa=PA$o
        pt=() ps=() pa=()
        OPK[o]=$(( RANDOM % 3 > 0 ))
        OPX[o]=$(( RANDOM % ($1 + 4) - 3 )) OPY[o]=$(( RANDOM % ($2 + 2) - 2 ))
        c=$(( RANDOM % ($1 / 2 + 3) - 1 ))
        OPW[o]=$c
        nr=$(( 1 + RANDOM % ($2 + 1) ))
        for (( k = 0; k < nr; k++ )); do
            kind=${3:RANDOM % ${#3}:1}
            if (( RANDOM % 12 == 0 )); then kind=3; fi
            if (( c > 0 && RANDOM % 4 == 0 )); then rtext "$kind" $(( c / 2 + RANDOM % (c / 2 + 3) ))
            else rtext "$kind" $(( RANDOM % 16 )); fi
            pt[k]=$REPLY
            if [[ $REPLY == $__FV_VS_PNA ]]; then
                KEYS+=("$REPLY")
                if (( RANDOM % 4 == 0 )); then WARM+=("$REPLY"); fi
            fi
            case $(( RANDOM % 40 )) in 0) ps[k]='#' ;; 1) ps[k]=ab ;; 2) ;; *) ps[k]=${SYMS:RANDOM % 62:1} ;; esac
            case $(( RANDOM % 40 )) in 0) attrs "$REPLY" 7; pa[k]=$REPLY ;; 1) attrs "$REPLY" 9; pa[k]=$REPLY ;; 2) ;; *) attrs "$REPLY" 0; pa[k]=$REPLY ;; esac
        done
        unset -n pt ps pa
    done
}
runops() {   # -> R: rc[RESULT] per write
    local o
    R=''
    for o in "${!OPK[@]}"; do
        if (( OPK[o] )); then fv.video._wrowsu "${OPX[o]}" "${OPY[o]}" "${OPW[o]}" "PT$o" "PS$o" 2>/dev/null
        else fv.video._wrows "${OPX[o]}" "${OPY[o]}" "PT$o" "PA$o" 2>/dev/null; fi
        R+="$?[$RESULT]"
    done
}
# snap -> S: the buffers (CH AT DX WIDE XV WNEW), the side map in key order,
# XSEQ, the text cache's answers for KEYS
snap() {
    local y k i
    local -a ks=()
    S="xseq=$__FV_VS_XSEQ"$'\n'
    for (( y = 0; y < __FV_VS_H; y++ )); do
        S+="${__FV_VS_CH[y]}|${__FV_VS_AT[y]}|${__FV_VS_DX1[y]-}-${__FV_VS_DX2[y]-}|${__FV_VS_WIDE[y]}|${__FV_VS_XV[y]-}|${__FV_VS_WNEW[y]-}"$'\n'
    done
    for k in "${!__FV_VS_X[@]}"; do
        for (( i = ${#ks[@]}; i > 0; i-- )); do
            if [[ ${ks[i-1]} < "$k" ]]; then break; fi
            ks[i]=${ks[i-1]}
        done
        ks[i]=$k
    done
    for k in "${ks[@]}"; do S+="$k=${__FV_VS_X[$k]};"; done
    for k in "${KEYS[@]}"; do S+="[${__FV_VS_TC[$k]-u}|${__FV_VS_TX[$k]-u}]"; done
}
# snapo -> S += the terminal's rows (OCH OAT OXV) and the cursor state
snapo() {
    local y
    S+=$'\n'"svis=$__FV_VS_SVIS spos=$__FV_VS_SPOS"$'\n'
    for (( y = 0; y < __FV_VS_H; y++ )); do
        S+="${__FV_VS_OCH[y]-}|${__FV_VS_OAT[y]-}|${__FV_VS_OXV[y]-}"$'\n'
    done
}
# one run (the entries of $1: old / new): the writes, a frame, the writes
# again (cached now), a frame -> OUT = state + rc + bytes of both rounds
onerun() {   # old|new W H ASCII
    local b1 b2 s1 r1
    use "$1"
    ground "$2" "$3" "$4"
    runops; r1=$R
    snap; s1=$S
    vt_capture fv.video.updateScreen; b1=$VT_OUT
    snapo; s1+=$S
    runops; r1+=" $R"
    snap
    vt_capture fv.video.updateScreen; b2=$VT_OUT
    snapo
    OUT="$s1"$'\n'"$S"$'\n'"rc $r1"$'\n'"$b1"$'\n'"$b2"
}
abrun() {   # TITLE N KINDS-LIST
    local i W H asc kinds fail='' a nputo=0 nputn=0 ascii=0 nk
    local -a kl
    read -r -a kl <<< "$3"
    wrap fv.video._putw
    for (( i = 0; i < $2; i++ )); do
        case $(( i % 4 )) in 0) W=30 H=10 ;; 1|2) W=80 H=24 ;; *) W=200 H=12 ;; esac
        asc=$(( i % 11 == 10 )) ascii=$(( ascii + asc ))
        kinds=${kl[RANDOM % ${#kl[@]}]}
        gen_ground "$W" "$H"; gen_clip "$W" "$H"
        CLIP0=$CLIP CLIP=''
        ground "$W" "$H" "$asc"
        gen_ops "$W" "$H" "$kinds"
        CLIP=$CLIP0
        CNT=()
        onerun old "$W" "$H" "$asc"; a=$OUT
        nputo=$(( nputo + ${CNT[fv.video._putw]:-0} )); CNT=()
        onerun new "$W" "$H" "$asc"
        nputn=$(( nputn + ${CNT[fv.video._putw]:-0} ))
        if [[ $OUT != "$a" ]]; then
            nk=$(( ${#fail} < 600 ))
            if (( nk )); then fail+=" [i=$i ${W}x$H ascii=$asc clip='$CLIP' kinds=$kinds ops=${OPK[*]}/${OPX[*]}/${OPY[*]}/${OPW[*]}]"; fi
        fi
    done
    unwrap fv.video._putw
    use new
    check "$1 ($2 random scenes, $ascii in ASCII mode; _putw calls old $nputo -> new $nputn)" "" "$fail"
    if (( nputn >= nputo )); then kt_test_start "$1: the new paths were taken"; kt_test_fail "_putw old $nputo new $nputn"; fi
}

# --- A/B: random scenes ---------------------------------------------------------------
RANDOM=2501
abrun "the batch entries = the old _putw path: buffers, side map, versions, WNEW, damage, terminal rows, cache answers, rc, RESULT, frame bytes; then the same writes from the cache" 150 "4 24 2 0 01 024 1234 0124 3"
AMP0=$__FV_VS_AMP
__FV_VS_AMP=0
RANDOM=2502
abrun "the same with the bash 5.1 loop of the wide fast path (__FV_VS_AMP=0)" 30 "4 24 0 024"
__FV_VS_AMP=$AMP0
if shopt -q patsub_replacement 2>/dev/null; then
    shopt -u patsub_replacement
    RANDOM=2503
    abrun "the same with patsub_replacement off" 20 "4 24 0 024"
    shopt -s patsub_replacement
fi

# --- the edge sweep -------------------------------------------------------------------
# a row of CJK from column 0 or 1 (pairs at both parities), a narrow row, a
# row with a marker; _wrowsu of CJK / narrow rows and _wrows of narrow rows at
# X 0..4, W 1..10 (pairs of the text cut at W, of the row at X and X+W)
fail='' n=0
for asc in 0 1; do
    for c in 1 2 3 4 5 6 7 8 9 10; do
        for x in 0 1 2 3 4; do
            GX=(0 1 0 2) GY=(0 1 2 3) GT=("报告文件报告文件报告" "报告文件报告文件报" "abcdefghijklmnopqrst" "x${EMO}报告y") GS=(1 2 3 4)
            WARM=() CLIP=''
            if (( c % 3 == 0 )); then CLIP="$x 0 $(( x + c + 1 )) 5"; fi
            OPK=(1 1 0) OPX=("$x" "$x" "$x") OPY=(0 2 0) OPW=("$c" "$c" 0)
            PT0=("文件报告文件报告" "报告文件报告文件x" "${HAN}a" "ab") PS0=(5 6 7 8)
            PT1=("报告文件" "a报告文件报告") PS1=(9 A)
            printf -v q '%*s' "$c" ''; PT2=("${q// /q}" "zz" "y" "w") PA2=()
            for k in "${!PT2[@]}"; do PA2[k]=${PT2[k]//?/B}; done
            KEYS=("${PT0[@]}" "${PT1[@]}")
            onerun old 24 5 "$asc"; a=$OUT
            onerun new 24 5 "$asc"
            n=$(( n + 1 ))
            if [[ $OUT != "$a" ]]; then fail+=" [ascii=$asc W=$c x=$x clip='$CLIP']"; fi
        done
    done
done
use new
check "edge sweep: W 1..10, X 0..4, wide pairs of the text and of the row at both edges, a clip at X..X+W+1 ($n cases, ASCII mode too) = the old path" "" "$fail"

# the narrow sweep (V5 on its own, P3 3v-1 fix): rows of CJK from column 0
# and from column 1 (pairs at both parities), WNEW cleared, then ONE _wrows
# of narrow text at X 0..4, N 1..10 over both rows -- no earlier write at
# that X, so a pair cut at X or at X+N is the row's own
fail='' n=0 nsp=0
wrap fv.video._putw
for c in 1 2 3 4 5 6 7 8 9 10; do
    for x in 0 1 2 3 4; do
        GX=(0 1) GY=(0 1) GT=("报告文件报告文件报告" "报告文件报告文件报告") GS=(1 2)
        WARM=() CLIP='' CLRW=1 KEYS=()
        printf -v q '%*s' "$c" ''
        OPK=(0) OPX=("$x") OPY=(0) OPW=(0) PT0=("${q// /q}" "${q// /r}") PA0=("${q// /B}" "${q// /C}")
        CNT=()
        onerun old 24 3 0; a=$OUT nsp=$(( nsp + ${CNT[fv.video._putw]:-0} )); CNT=()
        onerun new 24 3 0
        nsp=$(( nsp - ${CNT[fv.video._putw]:-0} ))
        n=$(( n + 1 ))
        if [[ $OUT != "$a" ]]; then fail+=" [N=$c x=$x]"; fi
    done
done
unwrap fv.video._putw
CLRW=0
use new
check "narrow sweep: N 1..10 at X 0..4 into CJK rows at both parities, no earlier write at X ($n cases) = the old path, WNEW included" "" "$fail"
kt_test_start "narrow sweep: the splice took the place of _putw"
if (( nsp > 0 )); then kt_test_pass "$nsp _putw calls fewer"; else kt_test_fail "_putw calls fewer: $nsp"; fi
# a narrow write over every pair of a plain-wide row: no wide cell left
FV_SCREEN_W=30 FV_SCREEN_H=2 fv.video.initScreen
fv.video.writeStr 0 0 "报告文件报告文件报告文件" 1
fv.video.writeStr 1 1 "报告文件报告文件报告文件" 1
fv.video.updateScreen
__FV_VS_WNEW=()
printf -v q '%24s' ''
T=("${q// /q}") A=("${q// /B}")
fv.video._wrows 0 0 T A; r="$?[$RESULT]"
fv.video._wrows 1 1 T A; r+=" $?[$RESULT]"
for y in 0 1; do r+=" ${__FV_VS_WIDE[y]}/${__FV_VS_WNEW[y]-u}/${__FV_VS_DX1[y]-u}-${__FV_VS_DX2[y]-u}/${__FV_VS_CH[y]:0:26}"; done
check "a narrow write over every pair of a plain-wide row (both parities): WIDE 0, WNEW 1, damage X..X+N" \
    "0[24] 0[24] 0/1/0-24/${q// /q}   0/1/1-25/ ${q// /q} " "$r"

# --- the calls ------------------------------------------------------------------------
for f in fv.video._putw fv.video._wfb fv.video._wfbl fv.video._wrx fv.video._wrcut fv.video._wrw fv.video._wrw5; do wrap "$f"; done
# (_wfbl also notes a text holding the rows' separator: the loop over the
# rows joined, quadratic -- F1)
fv.video._wfbl() {
    CNT[fv.video._wfbl]=$(( ${CNT[fv.video._wfbl]:-0} + 1 ))
    if [[ $__fvv_t == *"$__FV_VS_US"* ]]; then CNT[fv.video._joined]=1; fi
    __cnt_fv.video._wfbl "$@"
}
cnt() {   # NAMES... -> REPLY: name=count ...
    local f
    REPLY=''
    for f; do REPLY+="${REPLY:+ }$f=${CNT[fv.video._$f]:-0}"; done
}
FV_SCREEN_W=80 FV_SCREEN_H=24 fv.video.initScreen
LT=() LS=() NT=() NA=() ET=() ES=()
for (( k = 0; k < 21; k++ )); do
    LT[k]=" 报告文件_$k.txt   $(( k * 37 ))" LS[k]=5
    NT[k]="plain_$k.txt   $(( k * 37 ))   " NA[k]=${NT[k]//?/6}
    ET[k]=" a${EMO}b_$k" ES[k]=7
done
__FV_VS_TC=() __FV_VS_TX=() CNT=()
fv.video._wrowsu 1 1 38 LT LS; cnt wfb wfbl putw wrx wrcut; r=$REPLY
CNT=()
fv.video._wrowsu 1 1 38 LT LS; cnt putw wrx wrcut; r+=" | $REPLY"
CNT=()
fv.video._wrows 41 1 NT NA; cnt putw wrw wrw5; r+=" | $REPLY"
CNT=()
fv.video._wrowsu 41 1 38 ET ES; cnt putw; r+=" | $REPLY"
check "the calls: a fresh 21-row CJK page (_wrowsu), the same page cached, a narrow page beside it (_wrows), an emoji page (old path)" \
    "wfb=1 wfbl=0 putw=0 wrx=1 wrcut=0 | putw=0 wrx=0 wrcut=0 | putw=0 wrw=21 wrw5=21 | putw=21" "$r"
# the bash 5.1 loop (and patsub_replacement off): the batch takes _wfb's test
# once and the loop per row, never over the rows joined (F1)
FV_SCREEN_W=80 FV_SCREEN_H=24 fv.video.initScreen
__FV_VS_AMP=0
__FV_VS_TC=() __FV_VS_TX=() CNT=()
fv.video._wrowsu 1 1 38 LT LS; cnt wfb wfbl joined putw; r=$REPLY
__FV_VS_AMP=$AMP0
want="wfb=1 wfbl=21 joined=0 putw=0"
if shopt -q patsub_replacement 2>/dev/null; then
    shopt -u patsub_replacement
    __FV_VS_TC=() __FV_VS_TX=() CNT=()
    fv.video._wrowsu 1 1 38 LT LS; cnt wfb wfbl joined putw; r+=" | $REPLY"
    shopt -s patsub_replacement
    want+=" | $want"
fi
check "the calls without the substitution (__FV_VS_AMP=0, patsub_replacement off): one batch test, the loop per row" "$want" "$r"
for f in fv.video._putw fv.video._wfb fv.video._wfbl fv.video._wrx fv.video._wrcut fv.video._wrw fv.video._wrw5; do unwrap "$f"; done

# --- caller state -------------------------------------------------------------------
# (SCENE_A builds the screen and writes fresh texts, SCENE_B writes and shows
# it; a caller IFS that holds \x01 -- bash's internal quoting byte -- set
# before both (initScreen, the cache misses) or between the two: the entries
# run through fv.video._g then, under an IFS of their own, P3 3v F4)
SCENE_A='
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r=""
FV_SCREEN_W=20 FV_SCREEN_H=4 fv.video.initScreen
fv.video.writeStr 0 0 "报告文件报告文件" 1
fv.video.writeStr 0 1 "报告$p" 1
fv.video.writeStr 10 2 "报告文件" 2
'
SCENE_B='
T=("报告_1" "文件文件x" "ab" "报$p") S=(2 3 4 5)
fv.video._wrowsu 2 0 8 T S; r+="$?.$RESULT."
T2=("abc" "defg" "hi" "*?[x]") A2=(123 4567 89 ABCDE)
fv.video._wrows 12 0 T2 A2; r+="$?.$RESULT."
fv.video._wrowsu 2 0 8 T S; r+="$?.$RESULT."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$TMPF" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1 2 3; do ( LC_ALL=C; printf " [%q|%s|%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}" "${__FV_VS_WIDE[y]}" "${__FV_VS_WNEW[y]-}" ); done
'
STATE='printf "%s|%s|%q|%s|%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS-unset}" "${LC_ALL-unset}" "$(locale charmap 2>/dev/null)"'
run() {   # SETUP (before the screen) [LATE (after it, before the writes)]
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/wide.out'
source '$FVV_TESTS_DIR/../fv.video.sh'
p=\$'\\xd0\\xb6'
$1
$SCENE_A
${2-}
$STATE
printf '#'
$SCENE_B
printf '#'
$STATE" 2>&1)
}
run ''
ref=${OUT#*#} ref=${ref%#*}
check "caller state: the reference scene" "0.8.0.5.0.8.0." "${ref%% \$*}"
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'IFS=' 'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -u patsub_replacement 2>/dev/null || :" \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C" \
    "IFS=\$'\\x01'" "IFS=\$'\\x01\\x1f0 '" "set -u; unset IFS" \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS=\$'*?[]a\\x01'; export LC_ALL=C" \
    "late:IFS=\$'\\x01'" "late:IFS=\$'\\x01\\x1f0 '" \
    "late:shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS=\$'*?[]a\\x01'; export LC_ALL=C"; do
    kt_test_start "caller state: same output and the state kept: $setup"
    if [[ $setup == late:* ]]; then run '' "${setup#late:}"; else run "$setup"; fi
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done
# the four single-row writes of a wide text the cache does not hold, under a
# caller IFS holding \x01 = under the default IFS (F4: the wide fast path of
# the miss kept its continuations)
ifsw() {   # IFS-VALUE -> REPLY: rc.RESULT per write, then the rows
    local y
    FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen
    IFS=$1
    __FV_VS_TC=() __FV_VS_TX=(); fv.video.writeStr 0 0 "$HAN$JI" 1; REPLY="$?.$RESULT"
    __FV_VS_TC=() __FV_VS_TX=(); fv.video.writeBuf 1 1 "a$HAN$JI" 12345; REPLY+=" $?.$RESULT"
    __FV_VS_TC=() __FV_VS_TX=(); fv.video._wstr 0 2 "$JI${HAN}b" 2; REPLY+=" $?.$RESULT"
    __FV_VS_TC=() __FV_VS_TX=(); fv.video._wbf 2 3 "$HAN$JI" 6789; REPLY+=" $?.$RESULT"
    IFS=$' \t\n'
    for (( y = 0; y < 4; y++ )); do REPLY+=" [${__FV_VS_CH[y]}|${__FV_VS_AT[y]}|${__FV_VS_WIDE[y]}]"; done
}
ifsw $' \t\n'; ref=$REPLY
ifsw $'\x01'; got=$REPLY
ifsw $'\x01\x1f0 '; got+=" / $REPLY"
check "writeStr, writeBuf, _wstr, _wbf of fresh wide texts under a caller IFS holding byte 01 (alone, and with 1F, 0 and a blank) = under the default IFS" "$ref / $ref" "$got"
check "the reference of that: the continuations kept" "0.4 0.5 0.5 0.4" "${ref%% \[*}"
# (the palette built afresh: the per-process copy, D18, emptied in the subshell)
kt_test_start "initScreen under a caller IFS holding byte 01: rc 0, the palette and the blank screen as under the default IFS"
got=$(__FV_VS_CPAL=''; FV_SCREEN_W=6 FV_SCREEN_H=2 fv.video.initScreen; r=$?; printf '%s|%s|%s|' "$r" "${__FV_VS_PAL[*]}" "${__FV_VS_CH[*]}")
out=$(__FV_VS_CPAL=''; IFS=$'\x01'; FV_SCREEN_W=6 FV_SCREEN_H=2 fv.video.initScreen; r=$?; IFS=' '; printf '%s|%s|%s|' "$r" "${__FV_VS_PAL[*]}" "${__FV_VS_CH[*]}" 2>&1)
if [[ $out == "$got" && $got == 0\|?* ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$got]"; fi

# --- zero forks ------------------------------------------------------------------
kt_test_start "PATH='': a fresh CJK page (_wrowsu, one batch), the same cached, a narrow page into plain-wide rows (_wrows), an emoji row, an update"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=40 FV_SCREEN_H=4
fv.video.initScreen
fv.video.writeStr 0 1 'a${HAN}b${JI}${JI}${JI}${JI}${JI}${JI}${JI}' 1
PATH=''
r=''
T=('报告_1' '文件文件x' 'x${EMO}' '报告') S=(1 2 3 4)
fv.video._wrowsu 0 0 9 T S; r+=\$?
fv.video._wrowsu 0 0 9 T S; r+=\$RESULT
T=('abc' 'defg') A=(123 4567)
fv.video._wrows 12 0 T A; r+=\$RESULT
fv.video.updateScreen; r+=\$?
printf '%s|%s|%s' \"\$r\" \"\${__FV_VS_WIDE[1]}\" \"\${__FV_VS_WNEW[1]}\"" 2>&1)
want="0940|1|1"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

exec {nullfd}>&-
kt_test_log "025_WidePaths.sh completed"
