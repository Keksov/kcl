#!/usr/bin/env bash
# 021_Rows.sh - the batch row entry of D21 stage E, headless: the friend
# entry fv.video._wrows X Y TEXTS ATTRS (fv.views.writeLines' fv.video call;
# fv.* units only):
#   * A/B: the cells, symbols, side map, wide flags, versions and damage, rc
#     and RESULT of one _wrows call equal those of one `writeBuf X Y+k
#     TEXTS[k] ATTRS[k]` per index k (rc 2 / RESULT '' when a row is
#     refused, else the widest row's RESULT) over a seeded random mix: narrow
#     and wide text, Cyrillic, box drawing, emoji, a combining mark, a control
#     character, empty rows; sparse arrays, missing ATTRS elements, ATTRS of
#     another length, bad symbols; rows with wide cells; X and Y off every
#     edge; clips; a cold and a warm text cache; ASCII mode; 30x10 and
#     200x50;
#   * the names: rc 3 (no identifier, __fv*, RESULT, associative; no key
#     evaluated); the answers: no rows (an empty array, an unset name) RESULT 0; the
#     widest row's cells; a refused row: rc 2, RESULT '', the other rows
#     written; no screen rc 1;
#   * frames through the VT model (incremental = forced);
#   * caller state (013-style) and zero forks.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "021: the batch row entry (_wrows)"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81'
for c in "$HAN" "$JI" "$EMO"; do VT_WD[$c]=2; done
VT_WD[$ACU]=0 VT_PICT[$EMO]=1

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
# snap -> S = every row's cells, symbols, damage, wide flag and version, then
# the side map in key order (sorted in bash: no fork per snapshot)
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

# scene W H ASCII WARM CLIP — a screen with wide characters, markers and a
# narrow marker on some rows, shown once; WARM 1: the pool's texts written
# once above the screen (the text cache warm); CLIP 0 none, 1 a box, 2 a
# band, 3 a single column
scene() {
    if (( $3 )); then FV_ASCII=1 FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen
    else FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; fi
    fv.video.fillRect 0 0 "$1" "$2" 1 '░'
    fv.video.writeStr 3 2 "${HAN}${JI}${HAN}${JI}${HAN}" 2
    fv.video.writeStr 0 5 "a${EMO}bc e${ACU}x${EMO}" 3
    fv.video.writeStr 6 7 "${HAN}x" 4
    fv.video.writeStr $(( $1 - 3 )) $(( $2 - 1 )) "${JI}" 4
    fv.video.updateScreen
    local t
    if (( $4 )); then for t in "${POOL[@]}"; do fv.video.writeStr 0 -1 "$t" 1; done; fi
    case $5 in
        1) fv.video.setClip 2 1 $(( $1 - 4 )) $(( $2 - 2 )) ;;
        2) fv.video.setClip 0 4 "$1" 6 ;;
        3) fv.video.setClip 5 0 6 "$2" ;;
    esac
}
POOL=('plain text' 'Привет, мир' '─┐ box ┌─' "${HAN}x${JI}" "a${EMO}b" "e${ACU}z" '' $'ctl\x01x' 'x' \
    'a much longer row of plain ASCII text that runs past the edge of the small screen' "$JI$JI$JI$JI")
SYMS=0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz

# attrs TEXT KIND -> REPLY = a symbol string for TEXT: KIND 0..6 its display
# width in random symbols, 7 one cell short, 8 one cell long, 9 a bad symbol
attrs() {
    local w i s=''
    fv.video.strWidth "$1"; w=$RESULT
    case $2 in 7) w=$(( w > 0 ? w - 1 : 1 )) ;; 8) w=$(( w + 1 )) ;; esac
    for (( i = 0; i < w; i++ )); do s+=${SYMS:RANDOM % 62:1}; done
    if (( $2 == 9 )); then s+='#'; fi
    REPLY=$s
}

# --- A/B: _wrows = writeBuf per row ------------------------------------------------
RANDOM=2111
fail='' n=0 nref=0
for (( i = 0; i < 240; i++ )); do
    if (( i % 6 == 5 )); then W=200 H=50; else W=30 H=10; fi
    ascii=$(( i % 5 == 4 )) warm=$(( RANDOM % 2 )) clip=$(( RANDOM % 4 ))
    x=$(( RANDOM % (W + 12) - 6 )) y=$(( RANDOM % (H + 6) - 4 ))
    T=() A=() K=()
    nr=$(( RANDOM % 14 )) k=$(( RANDOM % 3 ))
    for (( j = 0; j < nr; j++ )); do
        # (sparse: a gap of 0..2 rows now and then)
        k=$(( k + 1 + (RANDOM % 5 == 0 ? RANDOM % 3 : 0) ))
        T[k]=${POOL[RANDOM % ${#POOL[@]}]}
        K[k]=$(( RANDOM % 40 ))
    done
    scene "$W" "$H" "$ascii" "$warm" "$clip"
    # (the symbols by the display width in this screen's mode: ASCII mode makes wide text narrow)
    for k in "${!K[@]}"; do
        if (( K[k] < 36 )); then attrs "${T[k]}" 0; A[k]=$REPLY
        elif (( K[k] > 36 )); then attrs "${T[k]}" $(( K[k] - 30 )); A[k]=$REPLY; fi   # (36: ATTRS[k] missing)
    done
    r1=0 m=0
    for k in "${!T[@]}"; do
        if fv.video.writeBuf "$x" "$(( y + k ))" "${T[k]}" "${A[k]-}" 2>/dev/null; then
            if (( RESULT > m )); then m=$RESULT; fi
        else r1=1; fi
    done
    if (( r1 )); then want="2[]"; nref=$(( nref + 1 )); else want="0[$m]"; fi
    snap; s1=$S
    scene "$W" "$H" "$ascii" "$warm" "$clip"
    fv.video._wrows "$x" "$y" T A 2>/dev/null; got="$?[$RESULT]"
    snap
    n=$(( n + 1 ))
    if [[ $S != "$s1" || $got != "$want" ]]; then fail+=" [i=$i ${W}x$H ascii=$ascii warm=$warm clip=$clip x=$x y=$y idx=${!T[*]} got=$got want=$want]"; fi
done
check "_wrows = one writeBuf per index: $n random cases ($nref with a refused row; 30x10 and 200x50, ASCII mode, cold / warm cache, clips, sparse arrays, X / Y off every edge)" "" "$fail"

# --- the answers ---------------------------------------------------------------------
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen
fv.video.updateScreen
snap; s0=$S
T=() A=(); unset NOSUCH
fv.video._wrows 0 0 T A; r="$?[$RESULT]"
fv.video._wrows 0 0 NOSUCH NOSUCH; r+=" $?[$RESULT]"
snap
if [[ $S == "$s0" ]]; then r+=' same'; fi
check "no rows (an empty array, an unset name): rc 0, RESULT 0, nothing written" "0[0] 0[0] same" "$r"
T=(ab "$HAN$JI$HAN" 'abcdefghijklmnop') A=(12 123456 0123456789abcdef)
fv.video._wrows 1 0 T A; r="$?[$RESULT]"
check "RESULT = the widest row's cells (also past the screen's edge: writeBuf's answer)" "0[16]" "$r"
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen; fv.video.updateScreen
T=(aa bb cc dd) A=(11 2 3# 44)
fv.video._wrows 0 0 T A 2>/dev/null; r="$?[$RESULT]"
fv.video.getRow 0; r+=" $RESULT"; fv.video.getRow 1; r+="|$RESULT"; fv.video.getRow 2; r+="|$RESULT"; fv.video.getRow 3; r+="|$RESULT"
check "a refused row (ATTRS short, a bad symbol): rc 2, RESULT '', the other rows written" "2[] aa          |            |            |dd          " "$r"
RESULT=x
ok=$(__FV_VS_H=0; T=(a) A=(1); fv.video._wrows 0 0 T A 2>/dev/null; printf '%s[%s]' "$?" "$RESULT")
check "no screen: rc 1, RESULT ''" "1[]" "$ok"
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen; fv.video.updateScreen
snap; s0=$S
declare -A MI=(['INJ=1']=ab); unset INJ
T=(ab) A=(12) r=''
for n in "'' A" "T ''" '1T A' 'T A-1' 'T[0] A' '__fvv_t A' 'T __FVx' 'RESULT A' 'T RESULT' 'MI A' 'T MI'; do
    eval "set -- $n"
    RESULT=keep; fv.video._wrows 0 0 "$1" "$2"; r+="$?[$RESULT]"
done
snap
check "names checked: no identifier, a __fv / __FV prefix, RESULT, an associative array -> rc 3, RESULT '', nothing written, no key evaluated, no message" \
    "3[]3[]3[]3[]3[]3[]3[]3[]3[]3[]3[] same" "$r ${INJ-}$([[ $S == "$s0" ]] && printf same)"
FV_SCREEN_W=10 FV_SCREEN_H=3 fv.video.initScreen; fv.video.updateScreen
T=() A=(); T[1]=mid A[1]=777; T[4]=gone A[4]=1111
fv.video._wrows 2 0 T A; r="$?[$RESULT]"
fv.video.getRow 1; r+=" [$RESULT|$REPLY] ${__FV_VS_DX1[1]}-${__FV_VS_DX2[1]} [${__FV_VS_DX1[0]-}${__FV_VS_DX2[0]-}]"
check "a sparse TEXTS: element k on row Y+k, the gaps and the rows past the screen untouched; the damage of the row written only" "0[4] [  mid     |0077700000] 2-5 []" "$r"

# --- frames through the VT model -------------------------------------------------
kt_test_start "VT model: rows of narrow, Cyrillic, wide and emoji text over rows with wide cells and markers; incremental = forced"
scene 30 10 0 0 0
vt_init 30 10; frame force >/dev/null
T=('a list row        ' "${HAN}-${JI}-${EMO}" 'Привет мир' "e${ACU}e${ACU}e${ACU}" '' 'last row here') A=()
for k in "${!T[@]}"; do attrs "${T[k]}" 0; A[k]=$REPLY; done
fv.video._wrows 1 1 T A
fv.video.setClip 4 0 20 10
fv.video._wrows -1 4 T A
fv.video.resetClip
if frame && same_as_force; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "$VT_ERR"; fi

# --- caller state -------------------------------------------------------------------
SCENE='
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r=""
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen
fv.video.writeStr 0 3 "a$p b" 1
T=("*[a]?$p" "ab cd" "$p$p" "x") A=("123456" "AAAAA" "zz" "0")
fv.video._wrows 1 0 T A; r+="$?.$RESULT."
T[1]="x y"
fv.video._wrows 6 0 T A 2>/dev/null || r+="$?.$RESULT."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$TMPF" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1 2 3; do printf " [%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done
'
STATE='printf "%s|%s|%s|%s|%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}" "$(locale charmap 2>/dev/null)"'
run() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/rows.out'
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
check "caller state: the reference scene" "0.6.2..0." "${ref%% \$*}"
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' \
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
kt_test_start "PATH='': _wrows (narrow, Cyrillic, wide, a row with wide cells, a refused row), an update"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=10 FV_SCREEN_H=4
fv.video.initScreen
fv.video.writeStr 0 1 'a${HAN}b' 1
PATH=''
r=''
T=('abc' 'жук' 'x${EMO}' 'zz') A=(123 456 789 1)
fv.video._wrows 0 0 T A 2>/dev/null; r+=\$?
A[3]=11
fv.video._wrows 1 0 T A; r+=\$RESULT
fv.video.updateScreen; r+=\$?
printf '%s' \"\$r\"" 2>&1)
want="230"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

exec {nullfd}>&-
kt_test_log "021_Rows.sh completed"
