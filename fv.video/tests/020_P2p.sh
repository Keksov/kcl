#!/usr/bin/env bash
# 020_P2p.sh - the fv.video additions of the P2 performance pass (stage
# 2c-p), headless:
#   * fillColumns Y H ATTR CH X...: the same cells, symbols, side map, wide
#     flags, versions and damage as one `fillRect X Y 1 H ATTR CH` per column
#     (a seeded random mix of narrow / wide / marker units, rows holding wide
#     cells, clips, negative and out-of-screen columns and rows, duplicates,
#     any order); RESULT 1; bad arguments rc 2 with nothing written; no
#     screen rc 1; frames through the VT model (incremental = forced);
#   * the friend entries (fv.* units only): _clipf = setClip on integers
#     (negative, past the screen); _shadef = shadeRect in the shadow symbol;
#     _wstr = writeStr; _wbf = writeBuf (a bad ATTRS length still rc 2);
#     _fcf = fillColumns for one or two ascending columns - each compared
#     with its public twin over a random mix, also over rows with wide cells;
#   * writeBuf with a repeat count (the narrow rows spliced in place since
#     2c-p) = H single-row writes, over rows with and without wide cells and
#     under clips;
#   * caller state (013-style) and zero forks for the new entries.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "020: fv.video for the P2 performance pass"
unset FV_COLORS FV_ASCII

HAN=$'\xe6\xbc\xa2' JI=$'\xe5\xad\x97' EMO=$'\xf0\x9f\x98\x80' ACU=$'\xcc\x81'
for c in "$HAN" "$JI" "$EMO"; do VT_WD[$c]=2; done
VT_WD[$ACU]=0 VT_PICT[$EMO]=1

check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
scr() { FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; }
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

# a scene with wide characters, markers and a narrow marker on some rows
scene() {
    scr 30 10
    fv.video.fillRect 0 0 30 10 1 '░'
    fv.video.writeStr 3 2 "${HAN}${JI}${HAN}${JI}${HAN}" 2
    fv.video.writeStr 0 5 "a${EMO}bc e${ACU}x${EMO}" 3
    fv.video.writeStr 6 7 "${HAN}x" 4
    fv.video.updateScreen
}

# --- fillColumns = fillRect per column -------------------------------------------
RANDOM=2025
units=('│' '' 'x' "$HAN" "$EMO" "e${ACU}" '║' ' ')
fail='' n=0
for (( i = 0; i < 150; i++ )); do
    y=$(( RANDOM % 14 - 2 )) h=$(( RANDOM % 14 - 2 )) u=${units[RANDOM % ${#units[@]}]} a=$(( RANDOM % 5 ))
    nc=$(( RANDOM % 4 + 1 )) cols=()
    for (( j = 0; j < nc; j++ )); do cols+=("$(( RANDOM % 36 - 3 ))"); done
    clip=$(( RANDOM % 3 ))
    scene; if (( clip == 1 )); then fv.video.setClip 2 1 20 8; elif (( clip == 2 )); then fv.video.setClip 5 3 6 9; fi
    for c in "${cols[@]}"; do fv.video.fillRect "$c" "$y" 1 "$h" "$a" "$u"; done
    snap; s1=$S
    scene; if (( clip == 1 )); then fv.video.setClip 2 1 20 8; elif (( clip == 2 )); then fv.video.setClip 5 3 6 9; fi
    fv.video.fillColumns "$y" "$h" "$a" "$u" "${cols[@]}"; rc=$? r=$RESULT
    snap
    n=$(( n + 1 ))
    if [[ $S != "$s1" || $rc != 0 || $r != 1 ]]; then fail+=" [y=$y h=$h u=$u a=$a cols=${cols[*]} clip=$clip rc=$rc R=$r]"; fi
done
check "fillColumns = one fillRect X Y 1 H per column: $n random cases (units narrow / wide / marker, rows with wide cells, clips, columns and rows off the screen, duplicates, any order)" "" "$fail"

scr 8 3
fv.video.updateScreen
fv.video.fillColumns 0 3 2 '#' 6 1 6 3; r="$? $RESULT"
snap
check "fillColumns: columns given in any order and twice, RESULT 1, the damage from the first to the last column" \
    "0 1| # #  # |02020020|1-7|0|" "$r|${S%%$'\n'*}"
fv.video.updateScreen
fv.video.fillColumns 1 1 4 '' 7 0; snap
check "fillColumns: CH '' is a blank" " # #  # |42020024|0-8|0|" "$(sed -n 2p <<< "$S")"

scr 8 3
r=''
for a in '' '0' '0 1' '0 1 2' '0 1 2 x' 'x 1 2 x 3' '0 x 2 x 3' '0 1 * x 3' '0 1 22 x 3' '0 1 2 x y' '0 1 2 x 1.5' '0 1 2 x 12345678'; do
    read -r -a args <<< "$a"
    fv.video.fillColumns "${args[@]}"; r+="$?[$RESULT] "
done
snap
check "fillColumns: bad arguments are rc 2, RESULT '', nothing written" \
    "2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] 2[] |        |00000000|0-8|0|" "$r|$(sed -n 1p <<< "$S")"
fv.video.fillColumns -1 003 2 x -0 002 0; snap
check "fillColumns: signs and leading zeros are decimal (rows -1..1, columns 0 and 2)" "x x     |20200000|0-8|0||x x     |20200000|0-8|0|" "$(sed -n 1p <<< "$S")|$(sed -n 2p <<< "$S")"

ok=$(__FV_VS_H=0 __FV_VS_PAL=(); fv.video.fillColumns 0 1 1 x 0; printf '%s[%s]' "$?" "$RESULT")
check "fillColumns: no screen is rc 1" "1[]" "$ok"

# frames through the VT model
kt_test_start "VT model: a frame's sides by fillColumns over text, wide characters and markers; incremental = forced"
scene
vt_init 30 10; frame force >/dev/null
fv.video.fillColumns 1 8 5 '║' 2 20
fv.video.fillColumns 0 10 6 "$HAN" 7 11
fv.video.fillColumns 4 3 7 "$EMO" 0 4 28
if frame && same_as_force; then kt_test_pass "ok (${#VT_OUT} chars)"; else kt_test_fail "$VT_ERR"; fi

# --- the friend entries = their public twins ----------------------------------
fail=''
for (( i = 0; i < 80; i++ )); do
    a=$(( RANDOM % 40 - 5 )) b=$(( RANDOM % 14 - 2 )) c=$(( RANDOM % 40 - 5 )) d=$(( RANDOM % 14 - 2 ))
    scene; fv.video.setClip "$a" "$b" "$c" "$d"; fv.video.getClip; g1=$RESULT
    scene; fv.video._clipf "$a" "$b" "$c" "$d"; fv.video.getClip; g2=$RESULT
    [[ $g1 == "$g2" ]] || fail+=" clip[$a $b $c $d: $g1 / $g2]"
done
check "_clipf X1 Y1 X2 Y2 = setClip (integers, negative and past the screen)" "" "$fail"

texts=('plain text' "${HAN}x${JI}" "a${EMO}b" "e${ACU}z" 'Привет ─┐' '' "$(printf 'ctl\x01x')")
fail=''
for (( i = 0; i < 80; i++ )); do
    x=$(( RANDOM % 36 - 4 )) y=$(( RANDOM % 12 - 1 )) w=$(( RANDOM % 8 - 1 )) h=$(( RANDOM % 6 - 1 )) t=${texts[RANDOM % ${#texts[@]}]}
    clip=$(( RANDOM % 2 ))
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video.shadeRect "$x" "$y" "$w" "$h"; snap; s1=$S
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video._shadef "$x" "$y" "$w" "$h"; snap
    [[ $S == "$s1" ]] || fail+=" shade[$x $y $w $h $clip]"
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video.writeStr "$x" "$y" "$t" 3; r1="$?$RESULT"; snap; s1=$S
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video._wstr "$x" "$y" "$t" 3; r2="$?$RESULT"; snap
    [[ $S == "$s1" && $r1 == "$r2" ]] || fail+=" wstr[$x $y ${t@Q} $clip]"
    fv.video.strWidth "$t"; printf -v at '%*s' "$RESULT" ''; at=${at// /4}
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video.writeBuf "$x" "$y" "$t" "$at" "$(( h + 1 ))"; r1="$?$RESULT"; snap; s1=$S
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video._wbf "$x" "$y" "$t" "$at" "$(( h + 1 ))"; r2="$?$RESULT"; snap
    [[ $S == "$s1" && $r1 == "$r2" ]] || fail+=" wbf[$x $y ${t@Q} $h $clip]"
    c1=$(( RANDOM % 36 - 3 )) c2=$(( c1 + 1 + RANDOM % 20 ))
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video.fillColumns "$y" "$h" 5 '│' "$c1" "$c2"; snap; s1=$S
    scene; (( clip )) && fv.video.setClip 2 1 20 8; fv.video._fcf "$y" "$h" 5 '│' "$c1" "$c2"; snap
    [[ $S == "$s1" ]] || fail+=" fcf[$y $h $c1 $c2 $clip]"
done
check "_shadef = shadeRect, _wstr = writeStr, _wbf = writeBuf (H too), _fcf = fillColumns: 80 random cases each, rows with wide cells included" "" "$fail"
scr 6 2
fv.video._wbf 0 0 ab 1 2; r="$?[$RESULT]"
check "_wbf: ATTRS of another length is still rc 2" "2[]" "$r"

# --- writeBuf H = H single-row writes -------------------------------------------
fail=''
for (( i = 0; i < 80; i++ )); do
    x=$(( RANDOM % 36 - 4 )) y=$(( RANDOM % 12 - 2 )) h=$(( RANDOM % 12 )) t=${texts[RANDOM % 5]}
    clip=$(( RANDOM % 3 ))
    fv.video.strWidth "$t"; printf -v at '%*s' "$RESULT" ''; at=${at// /6}
    scene; if (( clip == 1 )); then fv.video.setClip 2 1 20 8; elif (( clip == 2 )); then fv.video.setClip 0 4 30 6; fi
    for (( k = 0; k < h; k++ )); do fv.video.writeBuf "$x" "$(( y + k ))" "$t" "$at"; done; snap; s1=$S
    scene; if (( clip == 1 )); then fv.video.setClip 2 1 20 8; elif (( clip == 2 )); then fv.video.setClip 0 4 30 6; fi
    fv.video.writeBuf "$x" "$y" "$t" "$at" "$h"; snap
    [[ $S == "$s1" ]] || fail+=" [$x $y ${t@Q} $h $clip]"
done
check "writeBuf X Y TEXT ATTRS H = H single-row writes: 80 random cases (narrow and wide text, rows with wide cells, clips)" "" "$fail"

# --- caller state -------------------------------------------------------------------
SCENE='
exec {fd}>"$TMPF"
FV_VIDEO_OUT_FD=$fd
r=""
FV_SCREEN_W=12 FV_SCREEN_H=4 fv.video.initScreen
fv.video.writeStr 0 1 "a$p b" 1
fv.video.fillColumns 0 4 2 "║" 0 3 11; r+="$RESULT."
fv.video._fcf 1 2 3 "│" 5 7
fv.video._clipf -1 0 9 3; fv.video.getClip; r+="$RESULT."
fv.video._wstr 2 2 "*[a]?$p" 4; r+="$RESULT."
fv.video._wbf 1 3 "$p?" "aA" 2; r+="$RESULT."
fv.video._shadef 4 0 3 2; fv.video.resetClip
fv.video.fillColumns 0 1 "*" x 1 || r+="$?."
fv.video.updateScreen; r+="$?."
exec {fd}>&-
IFS= read -r -d "" frame < "$TMPF" || :
( LC_ALL=C; printf "%s %q" "$r" "$frame" )
for y in 0 1 2 3; do printf " [%s|%s]" "${__FV_VS_CH[y]}" "${__FV_VS_AT[y]}"; done
'
STATE='printf "%s|%s|%s|%s|%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}" "$(locale charmap 2>/dev/null)"'
run() {
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
TMPF='$FVV_TMP/p2p.out'
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
check "caller state: the reference scene" "1.0 0 9 3.6.2.2.0." "${ref%% \$*}"
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
kt_test_start "PATH='': fillColumns (narrow, wide unit, rows with wide cells) and the friend entries, an update"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=10 FV_SCREEN_H=4
fv.video.initScreen
fv.video.writeStr 0 1 'a${HAN}b' 1
PATH=''
r=''
fv.video.fillColumns 0 4 2 '│' 0 9; r+=\$RESULT
fv.video.fillColumns 0 4 2 '${HAN}' 4; r+=\$RESULT
fv.video._fcf 0 2 3 '║' 1 2
fv.video._clipf 0 0 9 4; fv.video.getClip; r+=\"[\$RESULT]\"
fv.video._wstr 0 3 'x${EMO}' 4; r+=\$RESULT
fv.video._wbf 0 2 'ab' '56' 2; r+=\$RESULT
fv.video._shadef 0 0 3 2
fv.video.updateScreen; r+=\$?
printf '%s' \"\$r\"" 2>&1)
want="11[0 0 9 4]320"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

# --- critic round (stage 2c-p) ------------------------------------------------------
# a column repeated after a larger one, the clip leaving two equal columns, _fcf X X:
# the row stays the screen's width and equals one fillRect per column; RESULT = 1
# on a cache miss of the text walk (a fresh process); _clipf leaves RESULT '' as setClip
kt_test_start "fillColumns: duplicates after a larger column, _fcf X X, RESULT on a fresh wide CH, _clipf RESULT"
out=$("$BASH" -c "
export LC_ALL=C.UTF-8
source '$FVV_TESTS_DIR/../fv.video.sh'
exec {fd}>/dev/null
FV_VIDEO_OUT_FD=\$fd FV_SCREEN_W=30 FV_SCREEN_H=8
fv.video.initScreen
row() { fv.video.getRow 4; printf '%s|%s|%s;' \"\${#__FV_VS_CH[4]}\" \"\$RESULT\" \"\$REPLY\"; }
for cols in '19 1 3 3' '19 3 3' '5 3 3' '3 3'; do
    fv.video.resetClip; fv.video.clearScreen; fv.video.writeStr 0 4 'abcdefghijklmnopqrstuvwxyz0123' 1
    fv.video.setClip 9 4 28 8; fv.video.fillColumns 4 1 E x \$cols; a=\$(row)
    fv.video.resetClip; fv.video.clearScreen; fv.video.writeStr 0 4 'abcdefghijklmnopqrstuvwxyz0123' 1
    fv.video.setClip 9 4 28 8; for c in \$cols; do fv.video.fillRect \"\$c\" 4 1 1 E x; done; b=\$(row)
    [[ \$a == \"\$b\" ]] || printf 'DIFF %s: %s / %s\n' \"\$cols\" \"\$a\" \"\$b\"
done
fv.video.resetClip; fv.video.clearScreen; fv.video.writeStr 0 4 'abcdefghijklmnopqrstuvwxyz0123' 1
fv.video._fcf 4 1 2 x 5 5; a=\$(row)
fv.video.clearScreen; fv.video.writeStr 0 4 'abcdefghijklmnopqrstuvwxyz0123' 1
fv.video.fillRect 5 4 1 1 2 x; b=\$(row)
[[ \$a == \"\$b\" ]] || printf 'DIFF _fcf 5 5: %s / %s\n' \"\$a\" \"\$b\"
r=''
fv.video.fillColumns 2 3 1 '龍' 4 9; r+=\$RESULT
fv.video._fcf 2 3 1 '🐉' 4 9; r+=\$RESULT
RESULT=keep; fv.video._clipf 0 0 30 8; r+=\"[\$RESULT]\"
printf '%s' \"\$r\"" 2>&1)
want="11[]"
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

exec {nullfd}>&-
kt_test_log "020_P2p.sh completed"
