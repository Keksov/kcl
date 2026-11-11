#!/usr/bin/env bash
# 017_Wide.sh - wide characters, emoji and clusters in the screen buffer
# (decision D5, P1b; frames without the resync, which is P1c):
#   * the fast path: every code point its byte patterns accept has class n or
#     x in fv.unicode (and the zero-width / wide ones are refused);
#   * the cell grammar: a wide character = its character + \x01, a cell that
#     is not one BMP character (a cluster, an orphan zero-width character,
#     anything past U+FFFF, on every runtime) = \x02 + its content in
#     __FV_VS_X["Y X"]; RESULT and strWidth = display cells;
#   * the cluster rules (VS16 after an Extended_Pictographic or keycap base 2
#     wide - D14 -, ZWJ sequences, modifiers, regional-indicator pairs from
#     the left, orphans, also across calls);
#   * every write rule: edges of the screen and the clip, half-overwrites
#     (also of a half outside the clip), writeBuf's ATTRS per display cell
#     and the lead's symbol, writeCStr's ~, writeChar / fillRect units;
#   * the side map stays exact (no stale entry, flags, versions) through
#     overwrites, clearScreen, resizeScreen, fillRect, setColorDepth, force;
#   * the frames send a marker's content and never \x01; a changed cluster in
#     the same cell is sent; the damage covers whole wide characters;
#   * the cursor on a placeholder stays where it was set; ASCII mode; a C
#     caller; nocasematch (classes x and y); set -eu.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "017: wide characters"
unset FV_COLORS FV_ASCII

# the characters, by their UTF-8 bytes (independent of the table)
HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97'                  # 漢 字, wide
EMO=$'\xf0\x9f\x98\x80' TADA=$'\xf0\x9f\x8e\x89'        # 😀 🎉, wide, past U+FFFF
ACU=$'\xcc\x81' DIA=$'\xcc\x88'                         # U+0301 U+0308, marks
ZWJ=$'\xe2\x80\x8d' VS16=$'\xef\xb8\x8f' KEYC=$'\xe2\x83\xa3'
COPY=$'\xc2\xa9' HEART=$'\xe2\x9d\xa4' WATCH=$'\xe2\x8c\x9a'   # © ❤ (class x), ⌚ (class y)
MAN=$'\xf0\x9f\x91\xa8' WOMAN=$'\xf0\x9f\x91\xa9' GIRL=$'\xf0\x9f\x91\xa7'
THUMB=$'\xf0\x9f\x91\x8d' TONE=$'\xf0\x9f\x8f\xbd'      # 👍 🏽
RID=$'\xf0\x9f\x87\xa9' RIE=$'\xf0\x9f\x87\xaa'         # regional indicators D, E
HI=$'\xf4\x8f\xbf\xbf'                                  # U+10FFFF, narrow, past U+FFFF
L1=$'\xe1\x84\x80' V1=$'\xe1\x85\xa1' T1=$'\xe1\x86\xa8'   # Hangul jamo L V T

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
scr() { FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; }
# row Y -> ROW = the cells with \x01 as '<' and \x02 as '#'
row() { ROW=${__FV_VS_CH[$1]}; ROW=${ROW//$'\x01'/'<'}; ROW=${ROW//$'\x02'/'#'}; }
# xs -> XS = the side map, "Y X=content" sorted, ';'-joined
xs() {
    local k
    XS=''
    while IFS= read -r k; do [[ -n $k ]] && XS+="$k=${__FV_VS_X[$k]};"; done < <(printf '%s\n' "${!__FV_VS_X[@]}" | sort -t' ' -k1,1n -k2,2n)
}
# inv -> INV = '' when the buffer keeps the grammar: rows W long, no \x01 at
# column 0 or after \x01, a \x01's symbol = its lead's, every \x02 has a side
# entry and every entry a \x02, the flags exact
inv() {
    local y x c a f n=0 k e=''
    for (( y = 0; y < __FV_VS_H; y++ )); do
        c=${__FV_VS_CH[y]} a=${__FV_VS_AT[y]}
        (( ${#c} == __FV_VS_W && ${#a} == __FV_VS_W )) || e+=" row $y length ${#c}/${#a}"
        [[ ${c:0:1} == $'\x01' ]] && e+=" row $y starts with a continuation"
        for (( x = 1; x < ${#c}; x++ )); do
            if [[ ${c:x:1} == $'\x01' ]]; then
                [[ ${c:x-1:1} == $'\x01' ]] && e+=" $y,$x continuation after a continuation"
                [[ ${a:x:1} == "${a:x-1:1}" ]] || e+=" $y,$x continuation symbol ${a:x:1} != lead ${a:x-1:1}"
            fi
        done
        for (( x = 0; x < ${#c}; x++ )); do
            if [[ ${c:x:1} == $'\x02' ]]; then
                n=$(( n + 1 ))
                [[ -n ${__FV_VS_X["$y $x"]+x} ]] || e+=" $y,$x marker without content"
            fi
        done
        f=0
        [[ $c == *$'\x01'* ]] && f=1
        [[ $c == *$'\x02'* ]] && f=$(( f + 2 ))
        [[ ${__FV_VS_WIDE[y]} == "$f" ]] || e+=" row $y flag ${__FV_VS_WIDE[y]} != $f"
    done
    for k in "${!__FV_VS_X[@]}"; do
        y=${k% *} x=${k#* }
        [[ ${__FV_VS_CH[y]:x:1} == $'\x02' ]] || e+=" stale entry [$k]"
    done
    (( n == ${#__FV_VS_X[@]} )) || e+=" $n markers, ${#__FV_VS_X[@]} entries"
    # per row: the markers = the entries of that row
    for (( y = 0; y < __FV_VS_H; y++ )); do
        c=${__FV_VS_CH[y]} c=${c//[!$'\x02']/} n=0
        for k in "${!__FV_VS_X[@]}"; do [[ ${k% *} == "$y" ]] && n=$(( n + 1 )); done
        (( ${#c} == n )) || e+=" row $y: ${#c} markers, $n entries"
    done
    INV=$e
}
FVW_RE=$'\e\\[[0-9;?]*[A-Za-z]'
# frame [force] -> FR = the text of the frame (CUP / SGR / ?25 stripped), FO = all of it
frame() {
    local s
    vt_capture fv.video.updateScreen "$@"
    FO=$VT_OUT s=$VT_OUT
    while [[ $s =~ $FVW_RE ]]; do s=${s/"${BASH_REMATCH[0]}"/}; done
    FR=$s
}
# cls CP -> the class letter (fv.unicode)
cls() { fv.unicode.charClass "$1"; CL=$RESULT; }

# --- the fast path -----------------------------------------------------------------
kt_test_start "fast path: every code point its byte patterns accept has class n or x (U+00A0-02FF, 0370-053F, 2000-207F, 2180-21FF, 2500-25FF)"
fast_ok() { local LC_ALL=C; fv.video._fast "$1"; }
bad='' acc=0
for r in 160:767 880:1343 8192:8319 8576:8703 9472:9727; do
    for (( cp = ${r%:*}; cp <= ${r#*:}; cp++ )); do
        printf -v h '%08x' "$cp"; printf -v ch "\\U$h"
        if fast_ok "$ch"; then
            acc=$(( acc + 1 ))
            cls "$cp"
            [[ $CL == n || $CL == x ]] || bad+=" U+$(printf %04X "$cp")=$CL"
        fi
    done
done
if [[ -z $bad ]] && (( acc == 1511 )); then kt_test_pass "$acc accepted, all n/x"; else kt_test_fail "accepted $acc;$bad"; fi

r=''
for cp in 173 1155 1161 8203 8205 8207 8232 8239 8288 8303 9724 9725 9726 9727 768 1425 12354 19968 128512; do
    printf -v h '%08x' "$cp"; printf -v ch "\\U$h"
    if fast_ok "$ch"; then r+=" U+$(printf %04X "$cp")"; fi
done
check "fast path refuses U+00AD, U+0483/0489, ZWSP/ZWJ/RLM, U+2028/202F, U+2060/206F, U+25FC-25FF, marks, CJK, emoji" "" "$r"

r=''
fast_ok 'Привет, мир! ╔══╗ │ ├─┤ «ёлка» — 5‰ ← → ■ ▲ ½ ÷' && r+=fast
fast_ok "a${ACU}" || r+=' mark-slow'
fast_ok "x${HAN}" || r+=' cjk-slow'
check "fast path: Cyrillic, box drawing, punctuation, arrows, shapes in one text; a mark or CJK sends it to the walk" "fast mark-slow cjk-slow" "$r"

# --- the cell grammar and the cluster rules ------------------------------------------
scr 16 3
fv.video.writeStr 0 0 "a${HAN}${JI}b" 1; r="$RESULT "
row 0; r+="[$ROW] ${__FV_VS_WIDE[0]} "
fv.video.strWidth "a${HAN}${JI}b"; r+=$RESULT
check "CJK: each character + its continuation, RESULT and strWidth = display cells, the row flagged 1" "6 [a漢<字<b          ] 1 6" "$r"

scr 16 3
fv.video.writeStr 0 0 "${EMO}x${HI}y" 1; r="$RESULT "
row 0; xs; r+="[$ROW] ${__FV_VS_WIDE[0]} $XS"
check "past U+FFFF (every runtime): a marker cell, its content in the side map; wide emoji 2, U+10FFFF 1" \
    "5 [#<x#y           ] 3 0 0=$EMO;0 3=$HI;" "$r"

kt_test_start "the cluster rules: the display width of each text (strWidth)"
bad=''
for e in "e${ACU}:1" "e${ACU}${DIA}:1" "${MAN}${ZWJ}${WOMAN}${ZWJ}${GIRL}:2" "${RID}${RIE}:2" "${RID}:1" "${RID}${RIE}${RID}:3" \
    "${THUMB}${TONE}:2" "a${TONE}:3" "1${VS16}${KEYC}:2" "#${VS16}:2" "${COPY}:1" "${COPY}${VS16}:2" "${HEART}${VS16}:2" \
    "a${VS16}:1" "${WATCH}:2" "${WATCH}${VS16}:2" "${HAN}${VS16}:2" "x${ZWJ}a:2" "${MAN}${ZWJ}${HAN}:4" "${HEART}${ZWJ}${EMO}:2" \
    "${L1}${V1}${T1}:2" "${ACU}:1" "${ACU}${ACU}x:2" "${ZWJ}${EMO}:3"; do
    fv.video.strWidth "${e%:*}"
    [[ $RESULT == "${e##*:}" ]] || bad+=" [${e%:*}]=$RESULT(want ${e##*:})"
done
if [[ -z $bad ]]; then kt_test_pass "24 texts"; else kt_test_fail "$bad"; fi

scr 20 2
fv.video.writeStr 0 0 "e${ACU}${MAN}${ZWJ}${WOMAN}${RID}${RIE}${RID}1${VS16}${KEYC}a${TONE}" 1; r="$RESULT "
row 0; xs; r+="[$ROW] $XS"
check "clusters as cells: e+mark, a ZWJ pair, a flag + a lone indicator, a keycap, a + a modifier on its own" \
    "11 [##<#<##<a#<         ] 0 0=e$ACU;0 1=$MAN$ZWJ$WOMAN;0 3=$RID$RIE;0 5=$RID;0 6=1$VS16$KEYC;0 9=$TONE;" "$r"

scr 10 2
fv.video.writeStr 0 0 "${ACU}x" 1; r="$RESULT "
fv.video.writeStr 3 0 'e' 2; fv.video.writeStr 4 0 "${ACU}" 2; r+="$RESULT "
row 0; xs; r+="[$ROW] $XS"
check "an orphan zero-width character: a cell of its own (space + it, 1 wide), also when the cell before it was written by another call" \
    "2 1 [#x e#     ] 0 0= $ACU;0 4= $ACU;" "$r"

# --- the edges of the screen and the clip ---------------------------------------------
scr 6 1
fv.video.writeStr 0 0 abcdef 2; fv.video.writeStr 5 0 "$HAN" 1; r="$RESULT "
row 0; inv; r+="[$ROW|${__FV_VS_AT[0]}]$INV"
check "a wide character cut by the right screen edge: a space in its visible half (the write's symbol), RESULT unclipped" "2 [abcde |222221]" "$r"

scr 6 1
fv.video.writeStr 0 0 abcdef 2; fv.video.setClip 0 0 4 1; fv.video.writeStr 3 0 "$HAN" 1; fv.video.resetClip
row 0; inv; check "a wide character cut by the clip's right edge: a space, the cell past the clip untouched" "[abc ef|222122]" "[$ROW|${__FV_VS_AT[0]}]$INV"

scr 6 1
fv.video.writeStr 0 0 abcdef 2; fv.video.setClip 2 0 6 1; fv.video.writeStr 1 0 "${HAN}x" 1; r="$RESULT "; fv.video.resetClip
row 0; inv; check "a wide character cut by the clip's left edge: a space in its visible half" "3 [ab xef|221122]" "$r[$ROW|${__FV_VS_AT[0]}]$INV"

# --- half-overwrites ------------------------------------------------------------------
scr 8 1
fv.video.writeStr 0 0 "a${HAN}b" 2; fv.video.writeStr 1 0 X 1
row 0; inv; check "a write over the first half of a wide character: the second half becomes a space in its old symbol" "[aX b    |2122    ]" "[$ROW|${__FV_VS_AT[0]:0:4}    ]$INV"

scr 8 1
fv.video.writeStr 0 0 "a${HAN}b" 2; frame; fv.video.writeStr 2 0 Y 1
row 0; inv; r="[$ROW|${__FV_VS_AT[0]:0:4}] ${__FV_VS_DX1[0]},${__FV_VS_DX2[0]}"
frame; r+=" [$FR]"
check "a write over the second half: the first half becomes a space; the damage covers it, the frame sends both cells" "[a Yb    |2212] 1,3 [ Y]" "$r$INV"

scr 8 1
fv.video.writeStr 0 0 "a${HAN}b" 2; fv.video.setClip 2 0 8 1; fv.video.writeStr 2 0 Z 1; fv.video.resetClip
row 0; inv; check "the uncovered half outside the clip is blanked anyway (no half character remains)" "[a Zb    ]" "[$ROW]$INV"

scr 8 1
fv.video.writeStr 0 0 "${HAN}${JI}" 2; fv.video.writeStr 1 0 "$JI" 1
row 0; inv; check "a wide write across two wide characters: both cut ones lose their other halves" "[ 字<     |21120000]" "[$ROW|${__FV_VS_AT[0]}]$INV"

scr 8 1
fv.video.writeStr 0 0 "${EMO}${HI}e${ACU}" 2; fv.video.writeStr 0 0 q 1; fv.video.writeStr 3 0 r 1
row 0; xs; inv; check "overwriting markers removes their side entries; the uncut ones stay" "[q #r    ] 0 2=$HI;" "[$ROW] $XS$INV"

# --- writeBuf, writeCStr, writeChar, fillRect --------------------------------------
scr 8 1
r=''
fv.video.writeBuf 0 0 "${HAN}a" 12; r+="$? "
fv.video.writeBuf 0 0 "${HAN}a" 123; r+="$RESULT "
row 0; inv; r+="[$ROW|${__FV_VS_AT[0]:0:3}]$INV"
check "writeBuf: ATTRS one symbol per display cell (else rc 2); the second half takes its lead's symbol" "2 3 [漢<a     |113]" "$r"

scr 8 2
fv.video.writeCStr 0 0 "~${HAN}~x" 1 2; r="$RESULT "
fv.video.writeCStr 0 1 "e~${ACU}~x" 1 2; r+="$RESULT "
fv.video.writeCStr 0 1 "e~${ACU}~x" 1 2; r+="$RESULT "
row 0; r+="[$ROW|${__FV_VS_AT[0]:0:3}] "; row 1; xs; inv; r+="[$ROW|${__FV_VS_AT[1]:0:2}] $XS$INV"
check "writeCStr: ~ takes no cell and splits no cluster (a mark after it joins the cell before it); a cell takes its base's symbol (cached: the same twice)" \
    "3 2 2 [漢<x     |221] [#x      |11] 1 0=e$ACU;" "$r"

scr 8 2
fv.video.writeChar 0 0 "$HAN" 1 3; r="$RESULT "
fv.video.writeChar 0 1 "${THUMB}${TONE}abc" 2 2; r+="$RESULT "
row 0; r+="[$ROW] "; row 1; xs; inv; r+="[$ROW] $XS$INV"
check "writeChar: the first cluster COUNT times, RESULT = its width x COUNT" "6 4 [漢<漢<漢<  ] [#<#<    ] 1 0=$THUMB$TONE;1 2=$THUMB$TONE;" "$r"

scr 8 1
fv.video.setClip 0 0 5 1; fv.video.writeChar 0 0 "$HAN" 1 3; fv.video.resetClip
row 0; inv; check "writeChar of a wide character cut by the clip: a space in the visible half" "[漢<漢<    ]" "[$ROW]$INV"

scr 8 2
fv.video.fillRect 0 0 5 2 1 "$HAN"; r="$RESULT "
row 0; r+="[$ROW] "; row 1; inv; r+="[$ROW]$INV"
check "fillRect with a wide character: whole pairs and a space for an odd width, RESULT = W" "5 [漢<漢<    ] [漢<漢<    ]" "$r"

scr 8 1
fv.video.writeStr 0 0 "a${HAN}b" 2; fv.video.fillRect 2 0 2 1 3 x
row 0; inv; check "fillRect starting inside a wide character blanks its first half" "[a xx    |2233    ]" "[$ROW|${__FV_VS_AT[0]:0:4}    ]$INV"

scr 8 1
fv.video.setClip 1 0 6 1; fv.video.fillRect 0 0 6 1 1 "$HAN"; fv.video.resetClip
row 0; inv; check "fillRect cut by the clip's left edge: a space in the visible half of the first pair" "[  漢<漢<  ]" "[$ROW]$INV"

scr 8 1
fv.video.fillRect 0 0 5 1 1 "$EMO"; r="$RESULT "
row 0; xs; inv; check "fillRect with an emoji (a marker): every pair has its side entry" "5 [#<#<    ] 0 0=$EMO;0 2=$EMO;" "$r[$ROW] $XS$INV"

# --- frames ----------------------------------------------------------------------------
scr 8 1
fv.video.writeStr 0 0 "a${HAN}${EMO}b" 1; frame
r="[$FR] "; [[ $FO == *$'\x01'* || $FO == *$'\x02'* ]] && r+=placeholder-sent
check "a frame sends a wide character once, a marker's content (a wide one after its pre-blank space), never a placeholder" "[a${HAN} ${EMO}b  ] " "$r"

scr 4 1
fv.video.writeStr 0 0 "e${ACU}" 1; frame; r="[$FR] "
fv.video.writeStr 0 0 "e${DIA}" 1; frame; r+="[$FR] "
frame; r+="[$FR]"
check "cluster A -> update -> cluster B in the same cell -> update: the frame has B (the row strings are equal, the side map's version is not) and the cell after the narrow marker; then nothing" \
    "[e${ACU}   ] [e${DIA} ] []" "$r"

scr 6 2
fv.video.writeStr 0 0 "${EMO}${HAN}" 1; fv.video.writeStr 0 1 "x${HI}" 2; frame
frame force; r="[$FR] "
fv.video.setColorDepth 16; frame; r+="[$FR] "
fv.video.definePalette 1 3 4; frame; r+="[$FR]"
check "force, setColorDepth and a palette change repaint the marker contents too" \
    "[ ${EMO}${HAN}  x${HI}    ] [ ${EMO}${HAN}  x${HI}    ] [ ${EMO}${HAN}  ]" "$r"

scr 6 1
fv.video.writeStr 0 0 "a${HAN}" 1; fv.video.setCursorPos 2 0; fv.video.setCursorType 1; frame
r=${FO: -12}; check "the cursor on the second half of a wide character stays where it was set" $'\e[1;3H\e[?25h' "$r"

# --- the side map through clear, resize, fill ----------------------------------------
scr 8 3
fv.video.writeStr 0 0 "${EMO}e${ACU}${HAN}" 1; fv.video.writeStr 0 1 "${HI}${RID}${RIE}" 1; frame
r="${#__FV_VS_X[@]} "
fv.video.fillRect 0 1 8 1 2; inv; r+="${#__FV_VS_X[@]}$INV "
fv.video.clearScreen; inv; r+="${#__FV_VS_X[@]} ${__FV_VS_WIDE[*]}$INV "
frame; r+="[$FR] "
fv.video.writeStr 0 2 "${EMO}" 1; FV_SCREEN_W=5 FV_SCREEN_H=2 fv.video.resizeScreen; inv; r+="${#__FV_VS_X[@]} ${__FV_VS_WIDE[*]}$INV"
printf -v sp '%16s' ''
check "no stale side entries: fillRect, clearScreen (and its frame: the two changed rows blank), resizeScreen" "4 2 0 0 0 0 [$sp] 0 0 0" "$r"

kt_test_start "a random mix of writes keeps the grammar exact after every operation (250 operations, a 16-wide screen, fills and units up to 12 wide)"
scr 16 4
POOLW=(a b ' ' ж ─ "$HAN" "$JI" "$EMO" "$HI" "e${ACU}" "$ACU" "${RID}${RIE}" "$RID" "${COPY}${VS16}" "$TONE" "${MAN}${ZWJ}${WOMAN}" '~')
RANDOM=20261111
bad=''
for (( i = 0; i < 250 && -z $bad; i++ )); do
    t=''
    for (( j = RANDOM % 5; j >= 0; j-- )); do t+=${POOLW[RANDOM % ${#POOLW[@]}]}; done
    x=$(( RANDOM % 19 - 2 )) y=$(( RANDOM % 5 - 1 ))
    case $(( RANDOM % 8 )) in
        0|1) last="writeStr $x $y"; fv.video.writeStr "$x" "$y" "$t" 1 ;;
        2) last="writeCStr $x $y"; fv.video.writeCStr "$x" "$y" "$t" 1 2 ;;
        3) last="writeChar $x $y"; fv.video.writeChar "$x" "$y" "$t" 3 $(( RANDOM % 7 )) ;;
        4) last="fillRect $x $y"; fv.video.fillRect "$x" "$y" $(( RANDOM % 13 )) 2 4 "$t" ;;
        5) last="setClip"; fv.video.setClip $(( RANDOM % 5 )) 0 $(( RANDOM % 6 + 6 )) 4 ;;
        6) last="resetClip"; fv.video.resetClip ;;
        7) last="update"; frame ;;
    esac
    inv
    if [[ -n $INV ]]; then bad="after op $i ($last [${t@Q}]): $INV"; fi
    if [[ $FO == *$'\x01'* || $FO == *$'\x02'* ]]; then bad="after op $i: a placeholder in the frame"; fi
done
if [[ -z $bad ]]; then kt_test_pass "ok"; else kt_test_fail "$bad"; fi

# --- the text cache ----------------------------------------------------------------------
scr 8 1
fv.video.writeStr 0 0 "${EMO}${HAN}" 1; a=${__FV_VS_CH[0]}
fv.video.writeStr 0 0 "${EMO}${HAN}" 1; b=${__FV_VS_CH[0]}
r=''; [[ $a == "$b" && -n ${__FV_VS_TC["${EMO}${HAN}"]+x} && -n ${__FV_VS_TX["${EMO}${HAN}"]+x} ]] && r=ok
xs; check "the text cache: a wide text's cells and markers are cached and give the same row" "ok 0 0=$EMO;" "$r $XS"

# --- modes and caller state (child shells) -----------------------------------------------
child() { "$BASH" -c "$1
source '$FVV_TESTS_DIR/../fv.video.sh'
$2" 2>&1; }
r=$(child 'export LC_ALL=C.UTF-8 FV_ASCII=1' "fv.unicode.charClass() { RESULT=''; return 9; }
FV_SCREEN_W=8 FV_SCREEN_H=1 fv.video.initScreen
fv.video.writeStr 0 0 \$'${HAN}${EMO}e${ACU}' 1; printf '%s ' \"\$RESULT\"
fv.video.strWidth \$'${HAN}${EMO}e${ACU}'; printf '%s [%s] %s %s' \"\$RESULT\" \"\${__FV_VS_CH[0]}\" \"\${#__FV_VS_X[@]}\" \"\${__FV_VS_WIDE[0]}\"")
check "ASCII mode: one '?' per non-ASCII sequence, width 1, no marker, the table never consulted" "4 4 [??e?    ] 0 0" "$r"

r=$(child 'export LC_ALL=C' "FV_SCREEN_W=8 FV_SCREEN_H=1 fv.video.initScreen
fv.video.writeStr 0 0 \$'${HAN}${EMO}x' 1; c=\${__FV_VS_CH[0]}; c=\${c//\$'\x01'/'<'}; c=\${c//\$'\x02'/'#'}
printf '%s [%s] %s' \"\$RESULT\" \"\$c\" \"\$LC_ALL\"")
check "a C caller: the walk runs in the unit's UTF-8 locale; the caller's locale back" "5 [漢<#<x   ] C" "$r"

r=$(child 'export LC_ALL=C.UTF-8; shopt -s nocasematch' "FV_SCREEN_W=8 FV_SCREEN_H=1 fv.video.initScreen
fv.video.writeStr 0 0 \$'${COPY}${WATCH}${HEART}' 1; printf '%s ' \"\$RESULT\"
fv.video.strWidth \$'${COPY}'; printf '%s ' \"\$RESULT\"
fv.video.strWidth \$'${COPY}${VS16}'; printf '%s ' \"\$RESULT\"
fv.video.strWidth \$'${HEART}'; printf '%s ' \"\$RESULT\"; shopt -q nocasematch && printf on")
check "nocasematch: class x (© ❤) stays 1 wide and class y (⌚) 2; VS16 widens ©; the option back" "4 1 2 1 on" "$r"

r=$(child 'set -eu; export LC_ALL=C.UTF-8' "exec {fd}>/dev/null; FV_VIDEO_OUT_FD=\$fd
FV_SCREEN_W=10 FV_SCREEN_H=2 fv.video.initScreen
fv.video.writeStr 0 0 \$'a${HAN}${EMO}e${ACU}${ACU}' 1
fv.video.writeBuf 0 1 \$'${HAN}x' 112
fv.video.writeCStr 3 1 \$'~${EMO}~e${ACU}' 1 2
fv.video.writeChar 1 0 \$'${JI}' 2 2
fv.video.fillRect 0 0 3 2 3 \$'${EMO}'
fv.video.strWidth \$'${MAN}${ZWJ}${WOMAN}'
fv.video.updateScreen; fv.video.updateScreen force
fv.video.clearScreen; FV_SCREEN_W=4 FV_SCREEN_H=1 fv.video.resizeScreen; fv.video.updateScreen
printf OK")
check "set -eu: every write with wide text, updates, clear and resize" "OK" "$r"

# --- units of every width (fillRect W, writeChar COUNT) -------------------------------
MATHA=$'\xf0\x9d\x90\x80'                               # U+1D400, narrow, past U+FFFF
kt_test_start "fillRect W = 1..12 and writeChar COUNT = 1..6 with a narrow cluster, a narrow astral character, CJK and an emoji: every cell, the symbols, one side entry per marker"
bad=''
for u in "e${ACU}:#:1" "${MATHA}:#:1" "${HAN}:漢<:2" "${EMO}:#<:2"; do
    ch=${u%%:*} pat=${u#*:} wd=${pat##*:} pat=${pat%:*}
    for (( W = 1; W <= 12; W++ )); do
        scr 14 2
        fv.video.fillRect 0 0 "$W" 1 1 "$ch"; res=$RESULT
        want=''
        if (( wd == 1 )); then for (( i = 0; i < W; i++ )); do want+=$pat; done
        else for (( i = 0; i < W / 2; i++ )); do want+=$pat; done; (( W % 2 )) && want+=' '; fi
        printf -v pad '%*s' $(( 14 - W )) ''; want+=$pad
        printf -v at '%*s' "$W" ''; at=${at// /1}; printf -v pad '%*s' $(( 14 - W )) ''; at+=${pad// /0}
        row 0; inv
        m=${want//[!#]/}
        [[ $res == "$W" && $ROW == "$want" && ${__FV_VS_AT[0]} == "$at" && ${#__FV_VS_X[@]} == "${#m}" && -z $INV ]] \
            || bad+=" fill[$ch W=$W]: R=$res [$ROW|${__FV_VS_AT[0]}] X=${#__FV_VS_X[@]}$INV"
        if (( W <= 6 )); then
            scr 14 2
            fv.video.writeChar 0 1 "$ch" 1 "$W"; res=$RESULT
            want=''; for (( i = 0; i < W; i++ )); do want+=$pat; done
            printf -v pad '%*s' $(( 14 - W * wd )) ''; want+=$pad
            row 1; inv; m=${want//[!#]/}
            [[ $res == $(( W * wd )) && $ROW == "$want" && ${#__FV_VS_X[@]} == "${#m}" && -z $INV ]] \
                || bad+=" char[$ch C=$W]: R=$res [$ROW] X=${#__FV_VS_X[@]}$INV"
        fi
    done
done
if [[ -z $bad ]]; then kt_test_pass "4 units x 12 widths + 6 counts"; else kt_test_fail "$bad"; fi

# --- the text caches do not collide (writeCStr has its own) ----------------------------
scr 10 3
fv.video.writeStr 0 0 $'\x05abc' 1; r="$RESULT "
fv.video.writeCStr 0 1 'abc' 1 2; r+="$RESULT [${__FV_VS_CH[1]}|${__FV_VS_AT[1]}] "
scr 10 3
fv.video.writeCStr 0 0 'xyz' 1 2
fv.video.strWidth $'\x05xyz'; r+="$RESULT "
fv.video.writeCStr 0 1 '' 1 2
fv.video.strWidth $'\x05'; r+="$RESULT "
fv.video.writeStr 0 2 $'\x05xyz' 1; r+="[${__FV_VS_CH[2]}]"
check "a text starting with \\x05 and writeCStr of the same text without it: separate caches, both orders" \
    "4 3 [abc       |1110000000] 4 1 [?xyz      ]" "$r"
r=$(child 'set -u; export LC_ALL=C.UTF-8' "FV_SCREEN_W=8 FV_SCREEN_H=2 fv.video.initScreen
fv.video.writeStr 0 0 \$'\\x05q' 1; fv.video.writeCStr 0 1 q 1 2; fv.video.writeCStr 0 1 q 1 2
printf '%s [%s]' \"\$RESULT\" \"\${__FV_VS_AT[1]}\"")
check "set -u: writeCStr after a writeStr of \\x05 + the same text" "1 [10000000]" "$r"

# --- the screen's mode is decided once (F3: no named UTF-8 locale at load) ---------------
r=$(child 'export LC_ALL=C.UTF-8' "__FV_VS_LOC=''
FV_SCREEN_W=8 FV_SCREEN_H=2 fv.video.initScreen
printf '%s %s ' \"\$FV_VIDEO_ASCII\" \"\$__FV_VS_LOC\"
cw() { local LC_ALL=C; fv.video.writeStr 0 0 'жé' 1; }
cw
fv.video.strWidth 'жé'; printf '%s [%s]' \"\$RESULT\" \"\${__FV_VS_CH[0]}\"")
check "a UTF-8 caller's initScreen names its locale when the load found none; a later C call runs in it (no ASCII form cached)" \
    "0 C.UTF-8 2 [жé      ]" "$r"
r=$(child 'export LC_ALL=C' "__FV_VS_LOC=''
FV_SCREEN_W=8 FV_SCREEN_H=2 fv.video.initScreen
printf '%s ' \"\$FV_VIDEO_ASCII\"
fv.video.writeStr 0 0 'жé' 1; printf '[%s]' \"\${__FV_VS_CH[0]}\"")
check "no UTF-8 locale at all: ASCII mode for the screen" "1 [??      ]" "$r"

kt_test_log "017_Wide.sh completed"
