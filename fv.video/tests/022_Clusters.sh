#!/usr/bin/env bash
# 022_Clusters.sh - fv P3 stage 3a-1, headless: fv.video.clusters TEXT CL CW
# (10.1) and the table of the wide fast path (10.12):
#   * the wide fast path's characters: every code point U+3000-U+FFFF that
#     __FV_VS_WB accepts is exactly one of the design's runs, and every one
#     of them is class w in fv.unicode (never wider than the walk decides);
#     a sample of U+0080-U+2FFF and of 4-byte characters refused;
#   * clusters = the cells of the walk (_san + _textw: CL the cells' contents,
#     CW their widths, an orphan's screen space dropped) over seeded random
#     text mixing ASCII, Cyrillic, Greek, Latin-1, CJK, Hangul, kana,
#     fullwidth, emoji, ZWJ sequences, VS16, keycaps, flags, combining marks,
#     controls, C1 and invalid UTF-8; RESULT = the count, the widths sum to
#     strWidth, valid text without controls comes back whole; the same with
#     the bash 5.1 loops forced (__FV_VS_AMP=0) and with patsub_replacement
#     off; ASCII mode: one cluster of one cell per UTF-8 sequence (as the
#     writes count them), TEXT's own bytes, joined = TEXT;
#   * the answers: an empty TEXT, printable ASCII (the fast path), arrays
#     replaced, a caller's local arrays, no screen needed; refusals rc 2 with
#     RESULT '' and the arrays untouched (count, names, CL = CW, associative);
#   * caller state (013-style setups) and zero forks (PATH='').

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

kt_test_section "022: clusters (10.1) and the wide fast path's table (10.12)"
unset FV_COLORS FV_ASCII

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}

# --- the wide fast path's table ----------------------------------------------------
# utf8 CP -> REPLY = the UTF-8 bytes of code point CP (any locale)
utf8() {
    local c=$1 h
    if (( c < 0x80 )); then printf -v h '\\x%02x' "$c"
    elif (( c < 0x800 )); then printf -v h '\\x%02x\\x%02x' $(( 0xc0 | c >> 6 )) $(( 0x80 | (c & 63) ))
    elif (( c < 0x10000 )); then printf -v h '\\x%02x\\x%02x\\x%02x' $(( 0xe0 | c >> 12 )) $(( 0x80 | (c >> 6 & 63) )) $(( 0x80 | (c & 63) ))
    else printf -v h '\\x%02x\\x%02x\\x%02x\\x%02x' $(( 0xf0 | c >> 18 )) $(( 0x80 | (c >> 12 & 63) )) $(( 0x80 | (c >> 6 & 63) )) $(( 0x80 | (c & 63) )); fi
    printf -v REPLY '%b' "$h"
}
# acc TEXT -> rc 0 when the wide fast path takes TEXT (C locale, as in _san2)
acc() {
    local LC_ALL=C __fvv_t=$1
    fv.video._wfb
}
# the design's runs (P3_DESIGN 10.12 + CJK punctuation U+3000-3029)
inrun() {
    local c=$1
    (( (c >= 0x3000 && c <= 0x3029) || (c >= 0x3041 && c <= 0x3096) || (c >= 0x309B && c <= 0x30FF)
       || (c >= 0x3400 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xF900 && c <= 0xFAFF)
       || (c >= 0xFF01 && c <= 0xFF60) || (c >= 0xFFE0 && c <= 0xFFE6) ))
}
# (one C-locale scope for the whole scan; the bytes from a table)
declare -a BY=()
for (( i = 128; i < 256; i++ )); do printf -v x '\\x%02x' "$i"; printf -v BY[i] '%b' "$x"; done
scan() {
    local LC_ALL=C __fvv_t cp a r x
    bad='' nacc=0
    for (( cp = 0x3000; cp <= 0xFFFF; cp++ )); do
        if (( cp >= 0xD800 && cp <= 0xDFFF )); then continue; fi
        __fvv_t="a${BY[0xe0 | cp >> 12]}${BY[0x80 | (cp >> 6 & 63)]}${BY[0x80 | (cp & 63)]} b"
        a=0; if fv.video._wfb; then a=1 nacc=$(( nacc + 1 )); fi
        r=0; if inrun "$cp"; then r=1; fi
        if (( a != r )); then printf -v x '%04X' "$cp"; bad+=" $x(acc=$a run=$r)"; continue; fi
        if (( a )); then
            fv.unicode.charClass "$cp"
            if [[ $RESULT != w ]]; then printf -v x '%04X' "$cp"; bad+=" $x(class $RESULT)"; fi
        fi
        if (( ${#bad} > 400 )); then break; fi
    done
}
scan
check "the wide fast path takes exactly the design's runs of U+3000-U+FFFF ($nacc code points), every one class w" "" "$bad"
bad=''
for cp in 0x80 0xA9 0xE9 0x416 0x5D0 0x301 0x7FF 0x800 0x1100 0x200B 0x200D 0x2500 0x2764 0x231A 0x2E80 0x2FFF \
    0xFE0F 0xFF00 0xFF61 0x1F600 0x20000 0x1F1E9 0x10FFFF; do
    utf8 $(( cp ))
    if acc "$REPLY"; then bad+=" $cp"; fi
done
check "refused: Latin-1, Cyrillic, Hebrew, a combining mark, U+0800-2FFF (Hangul jamo, ZWSP, ZWJ, box drawing, ❤, ⌚, CJK radicals), VS16, U+FF00 / U+FF61, 4-byte characters (emoji, CJK Ext B, a regional indicator)" "" "$bad"

# --- clusters = the walk's cells ---------------------------------------------------
HAN=$'\xe6\xbc\xa2' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81' ZWJ=$'\xe2\x80\x8d' VS16=$'\xef\xb8\x8f'
P=('a' 'b' 'Z' '0' ' ' '*' '?' '[' '~' '\' 'ж' 'Ё' 'λ' 'é' 'ß' '¶' "$HAN" '字' '报' '한' 'カ' 'ひ' 'Ａ' '。' '、' '「'
   "$EMO" "👨${ZWJ}👩${ZWJ}👧" "❤$VS16" "1$VS16"$'\xe2\x83\xa3' "$ACU" $'\xe3\x82\x99' '🇩🇪' $'\xf0\x9f\x87\xa9' '⌚' '👍🏽' '🏽'
   $'\xe2\x80\x8b' $'\xe1\x84\x80\xe1\x85\xa1\xe1\x86\xa8' "$ZWJ" "$VS16" $'\x01' $'\t' $'\x7f' $'\xc2\x85' $'\xff' $'\xe2\x94' $'\x80')
# words: 0 any piece, 1 CJK-ish only (the wide fast path), 2 narrow non-ASCII
WIDE=("$HAN" '字' '报' '한' 'カ' 'ひ' 'Ａ' '。' '、' '「' 'a' ' ' '1')
NARR=('ж' 'Ё' 'λ' 'é' 'ß' '¶' '─' 'a' 'b' ' ' '.')
rtext() {   # KIND LEN -> REPLY
    local i s=''
    for (( i = 0; i < $2; i++ )); do
        case $1 in
            0) s+=${P[RANDOM % ${#P[@]}]} ;;
            1) s+=${WIDE[RANDOM % ${#WIDE[@]}]} ;;
            *) s+=${NARR[RANDOM % ${#NARR[@]}]} ;;
        esac
    done
    REPLY=$s
}
# ocl TEXT -> OC / OW: the walk's cells (no fast path) decoded, an orphan's
# space dropped as clusters documents (run through fv.video._g: its guard)
ocl1() {
    local __fvv_t=$1 __fvv_w=0 __fvv_xl='' __fvv_f __fvv_a4=0 c q e i=0 n
    fv.video._san
    if (( ! __fvv_f )); then fv.video._textw; fi
    q=$__fvv_xl OC=() OW=()
    while [[ -n $__fvv_t ]]; do
        c=${__fvv_t:0:1} __fvv_t=${__fvv_t:1} n=1
        if [[ ${__fvv_t:0:1} == $'\x01' ]]; then __fvv_t=${__fvv_t:1} n=2; fi
        if [[ $c == $'\x02' ]]; then
            e=${q%%$'\x1f'*} q=${q#*$'\x1f'} c=${e#*:}
            if (( i == 0 )) && [[ $c == ' '?* && $1 != ' '* ]]; then c=${c:1}; fi
        fi
        OC[i]=$c OW[i]=$n i=$(( i + 1 ))
    done
}
ocl() { fv.video._g ocl1 "$1"; }
# oasc TEXT -> OC: ASCII mode, the sequences as _bytes takes them (C locale)
oasc() {
    local LC_ALL=C t=$1 c b n
    OC=()
    while [[ -n $t ]]; do
        c=${t:0:1}
        printf -v b '%d' "'$c"; b=$(( b & 255 ))
        if (( b >= 240 )); then n=3; elif (( b >= 224 )); then n=2; elif (( b >= 192 )); then n=1; else n=0; fi
        while (( n-- > 0 )) && [[ -n ${t:${#c}:1} ]]; do
            printf -v b '%d' "'${t:${#c}:1}"; b=$(( b & 255 ))
            if (( b < 128 || b >= 192 )); then break; fi
            c=${t:0:${#c}+1}
        done
        OC+=("$c") t=${t:${#c}}
    done
}
join() { local IFS=; REPLY="${*}"; }
clrun() {   # TITLE N (with the current switches)
    local i k len t fail='' nv=0 sum j
    for (( i = 0; i < $2; i++ )); do
        k=$(( i % 3 )) len=$(( RANDOM % 14 ))
        rtext "$k" "$len"; t=$REPLY
        CL=(junk) CW=(junk)
        fv.video.clusters "$t" CL CW; r="$?.$RESULT"
        ocl "$t"
        if [[ $r != "0.${#OC[@]}" || "${CL[*]}" != "${OC[*]}" || "${CW[*]}" != "${OW[*]}" || ${#CL[@]} != "${#OC[@]}" ]]; then
            fail+=" [$(printf %q "$t"): $r CL=$(printf '%q,' "${CL[@]}") want=$(printf '%q,' "${OC[@]}") CW=${CW[*]} want=${OW[*]}]"
            continue
        fi
        sum=0; for j in "${CW[@]}"; do sum=$(( sum + j )); done
        fv.video.strWidth "$t"
        if (( sum != RESULT )); then fail+=" [$(printf %q "$t"): widths $sum strWidth $RESULT]"; fi
        if [[ $t != *[$'\x01'-$'\x1f\x7f']* && $t != *$'\xc2'[$'\x80'-$'\x9f']* && $t != *$'\xff'* && $t != *$'\xe2\x94' && $t != *$'\xe2\x94'[!$'\x80'-$'\xbf']* && $t != *$'\x80'* ]]; then
            join "${CL[@]}"
            if [[ $REPLY != "$t" ]]; then fail+=" [$(printf %q "$t"): joined $(printf %q "$REPLY")]"; fi
            nv=$(( nv + 1 ))
        fi
        if (( ${#fail} > 600 )); then break; fi
    done
    check "$1 ($2 random texts, $nv valid ones joined back)" "" "$fail"
}
FV_SCREEN_W=40 FV_SCREEN_H=4 fv.video.initScreen
AMP0=$__FV_VS_AMP   # (1 from bash 5.2 on: put back after forcing the loops)
RANDOM=2201
clrun "clusters = the walk's cells (CL contents, CW widths), RESULT the count, widths sum to strWidth" 300
__FV_VS_AMP=0
RANDOM=2202
clrun "the same with the bash 5.1 loops (__FV_VS_AMP=0)" 120
__FV_VS_AMP=$AMP0
if shopt -q patsub_replacement 2>/dev/null; then
    shopt -u patsub_replacement
    RANDOM=2203
    clrun "the same with patsub_replacement off" 120
    shopt -s patsub_replacement
fi
__FV_VS_TC=() __FV_VS_TX=()

# ASCII mode
FV_ASCII=1 FV_SCREEN_W=40 FV_SCREEN_H=4 fv.video.initScreen
RANDOM=2204
fail='' n=0
# (fixed texts first: a \x1f in TEXT is one cluster, never a separator; critic 3a-1 M1)
FIX=($'a\x1fb' $'\x1f' $'\x1f\xd0\xb6' $'\xd0\xb6\x1f\x1f\xe4\xb8\xad' $'\x01\x7f\x1f')
for (( i = -${#FIX[@]}; i < 150; i++ )); do
    if (( i < 0 )); then t=${FIX[i + ${#FIX[@]}]}
    else rtext $(( i % 3 )) $(( RANDOM % 14 )); t=$REPLY; fi
    fv.video.clusters "$t" CL CW; r="$?.$RESULT"
    oasc "$t"
    fv.video.strWidth "$t"; sw=$RESULT
    join "${CL[@]}"
    ones=''; for j in "${CW[@]}"; do ones+=$j; done
    printf -v want1 '%*s' "${#OC[@]}" ''; want1=${want1// /1}
    n=$(( n + 1 ))
    if [[ $r != "0.${#OC[@]}" || "${CL[*]}" != "${OC[*]}" || $REPLY != "$t" || $ones != "$want1" || $sw != "${#OC[@]}" ]]; then
        fail+=" [$(printf %q "$t"): $r CL=$(printf '%q,' "${CL[@]}") want=$(printf '%q,' "${OC[@]}") strWidth=$sw]"
    fi
    if (( ${#fail} > 600 )); then break; fi
done
check "ASCII mode: one cluster of one cell per UTF-8 sequence (as the writes count them: = strWidth), TEXT's own bytes, joined = TEXT ($n random texts)" "" "$fail"
unset FV_ASCII
FV_SCREEN_W=40 FV_SCREEN_H=4 fv.video.initScreen

# --- the answers ---------------------------------------------------------------------
CL=(x y z) CW=(1 1 1)
fv.video.clusters '' CL CW; r="$?.$RESULT.${#CL[@]}.${#CW[@]}"
fv.video.clusters 'ab *?' CL CW; r+=" $?.$RESULT.$(printf '%s,' "${CL[@]}").${CW[*]}"
fv.video.clusters "a${HAN}é${EMO}e${ACU}" CL CW; r+=" $?.$RESULT.$(printf '%s,' "${CL[@]}").${CW[*]}"
check "an empty TEXT: two empty arrays; printable ASCII (the fast path); wide, narrow, a marker, a cluster" \
    "0.0.0.0 0.5.a,b, ,*,?,.1 1 1 1 1 0.5.a,${HAN},é,${EMO},e${ACU},.1 2 1 2 1" "$r"
f() { local -a lc=(old) lw=(old); fv.video.clusters "x$HAN" lc lw; REPLY="$?.$RESULT.${lc[*]}.${lw[*]}"; }
f
check "a caller's local arrays" "0.2.x ${HAN}.1 2" "$REPLY"
fv.video.clusters "${ACU}ab" CL CW; r="$?.$(printf '%q,' "${CL[@]}").${CW[*]}"
fv.video.clusters " ${ACU}ab" CL CW; r+=" $?.$(printf '%q,' "${CL[@]}").${CW[*]}"
check "a zero-width character at the start: its own cluster without the screen's space; after a space: joined to it" \
    "0.$(printf '%q,' "$ACU" a b).1 1 1 0.$(printf '%q,' " $ACU" a b).1 1 1" "$r"
r=$(__FV_VS_H=0 __FV_VS_TC=(); fv.video.clusters "ж${HAN}" CL CW; printf '%s.%s.%s' "$?" "$RESULT" "${CW[*]}")
check "no screen needed (the mode of the load)" "0.2.1 2" "$r"
declare -A MA=([0]=a)
CL=(keep) CW=(keep)
r=''
for a in "x CL" "x CL CW extra" "x '' CW" "x CL 1W" "x C-L CW" "x 'CL[0]' CW" "x __fvx CW" "x CL __FVx" "x RESULT CW" "x CL CL" "x MA CW" "x CL MA"; do
    eval "set -- $a"
    RESULT=keep; fv.video.clusters "$@" 2>/dev/null; r+="$?[$RESULT]"
done
check "refused: the count, names (empty, a digit first, '-', a subscript, __fv / __FV, RESULT), CL = CW, an associative array -> rc 2, RESULT '', the arrays untouched" \
    "2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[]2[] keep keep a" "$r ${CL[*]} ${CW[*]} ${MA[0]}"

# --- caller state ----------------------------------------------------------------------
SCENE='
r=""
for t in "plain *?[" "$p ab" "a漢字b" "e$a x" "😀|❤️" "$(printf "x\001y")"; do
    fv.video.clusters "$t" CL CW; r+="$?.$RESULT."
    for c in "${CW[@]}"; do r+="$c,"; done
    r+="|"
    for c in "${CL[@]}"; do r+="$c/"; done
done
( LC_ALL=C; printf "%q" "$r" )
'
STATE='printf "%s|%s|%s|%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
run() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
p=\$'\\xd0\\xb6' a=\$'\\xcc\\x81'
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}
run ''
ref=${OUT#*#} ref=${ref%#*}
check "caller state: the reference scene" "\$'0.9.1,1,1,1,1,1,1,1,1,|" "${ref%%p*}"
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
    'shopt -u globasciiranges' "IFS=';:0123456789aA '" 'IFS=' 'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='*?[]a'; export LC_ALL=C"; do
    kt_test_start "caller state: same clusters and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs ref [$ref]; state before [$before] after [$after]"; fi
done

# --- zero forks ------------------------------------------------------------------------
kt_test_start "PATH='': clusters (ASCII, Cyrillic, CJK, emoji, a cluster, a control; the loops; ASCII mode)"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
PATH=''
r=''
for t in 'abc' 'жук' '漢字x' 'a😀b' 'e${ACU}' \$'a\\x01b'; do fv.video.clusters \"\$t\" C W; r+=\$RESULT; done
__FV_VS_AMP=0
for t in 'abc' '漢字x'; do fv.video.clusters \"\$t\" C W; r+=\$RESULT; done
FV_ASCII=1 fv.video.initScreen
fv.video.clusters 'ж漢x' C W; r+=\$RESULT
printf '%s' \"\$r\"" 2>&1)
if [[ $out == "333313333" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out]"; fi

kt_test_log "022_Clusters.sh completed"
