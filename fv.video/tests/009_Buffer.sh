#!/usr/bin/env bash
# 009_Buffer.sh - the screen buffer without a terminal (headless, frames to
# a file fd): initScreen / resizeScreen sizes, the writes (writeStr,
# writeChar, writeBuf, writeCStr, fillRect, clearScreen) with their RESULT,
# clipping to the screen and to setClip, bad arguments (rc 2, nothing
# written), no screen (rc 1); updateScreen: the shown copy (a damaged but
# unchanged row emits nothing), damaged columns only, SGR only on a change,
# nothing when nothing changed, force, the output fd rules (FV_VIDEO_OUT_FD
# over FV_TTY_FD, none -> rc 1 with the damage kept, a failed printf -> rc 1
# and a forced next frame), the cursor (position and ?25h/l on change only).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "009: the screen buffer"

E=$'\e'
exec {nullfd}>/dev/null
# rows -> R = every row as "chars|attrs" joined by '/'
rows() {
    local y
    R=''
    for (( y = 0; y < __FV_VS_H; y++ )); do R+="${__FV_VS_CH[y]}|${__FV_VS_AT[y]}/"; done
}
check() {   # TITLE WANT GOT
    kt_test_start "$1"
    if [[ $3 == "$2" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$3] want [$2]"; fi
}
scr() { FV_SCREEN_W=$1 FV_SCREEN_H=$2 fv.video.initScreen; }

# --- no screen -----------------------------------------------------------------
r=''
fv.video.writeStr 0 0 x 0; r+="$? "
fv.video.updateScreen; r+="$? "
fv.video.fillRect 0 0 1 1 0; r+="$? "
fv.video.resizeScreen; r+="$?"
check "no screen yet: writes, updateScreen and resizeScreen are rc 1" "1 1 1 1" "$r"

# --- allocation ----------------------------------------------------------------
scr 6 2
rows
check "initScreen: W x H blanks in the default symbol 0, the cursor hidden, all damaged" \
    "      |000000/      |000000/ 0 0 0 0,6 0,6" "$R $__FV_VS_CURT $__FV_VS_CURX $__FV_VS_CURY ${__FV_VS_DX1[0]},${__FV_VS_DX2[0]} ${__FV_VS_DX1[1]},${__FV_VS_DX2[1]}"
r=''
for s in 'abc 3' '0 5' '-2 5' 'x 4' '7 0'; do
    read -r w h <<< "$s"
    FV_SCREEN_W=$w FV_SCREEN_H=$h fv.video.initScreen
    r+="${__FV_VS_W}x$__FV_VS_H "
done
FV_SCREEN_W=2000 FV_SCREEN_H=2 fv.video.initScreen; r+="${__FV_VS_W}x$__FV_VS_H:${#__FV_VS_SP}"
check "initScreen: a bad size falls back to 80 / 24; the width is capped at 1024 (FVMaxWidth), blanks sized from W" \
    "80x3 80x5 80x5 80x4 7x24 1024x2:1024" "$r"

# --- writes and RESULT -----------------------------------------------------------
scr 8 3
r=''
fv.video.writeStr 1 0 'Hello' A; r+="$RESULT "
fv.video.writeChar 0 1 '#' B 3; r+="$RESULT "
fv.video.writeChar 6 1 '' C; r+="$RESULT "
fv.video.writeBuf 3 2 'xyz' 'abc'; r+="$RESULT "
fv.video.writeCStr 4 1 '~Q~u' D E; r+="$RESULT"
rows
check "writeStr / writeChar / writeBuf / writeCStr: cells and symbols; RESULT = cells advanced" \
    "5 3 1 3 2 ' Hello  |0AAAAA00/### Qu  |BBB0EDC0/   xyz  |000abc00/'" "$r '$R'"

scr 8 2
fv.video.fillRect 1 0 3 2 F '*'; r="$RESULT "
fv.video.fillRect 6 0 1 1 G; r+="$RESULT "
fv.video.fillRect 0 0 -3 2 H; r+="$RESULT"
rows
check "fillRect: the rectangle in ATTR with CH (default blank); RESULT = W, a negative W draws nothing" \
    "3 1 0 ' ***    |0FFF00G0/ ***    |0FFF0000/'" "$r '$R'"

fv.video.clearScreen K; r="$? $RESULT"
rows
check "clearScreen ATTR: everything blank in ATTR" "0  '        |KKKKKKKK/        |KKKKKKKK/'" "$r '$R'"
fv.video.setClip 2 0 4 1
fv.video.clearScreen; rows
check "clearScreen ignores the clip; no ATTR = the default symbol" "'        |00000000/        |00000000/'" "'$R'"

# --- clipping -----------------------------------------------------------------------
scr 6 3
fv.video.writeStr -2 0 'abcdefgh' 1; r="$RESULT "
fv.video.writeStr 4 1 'XYZ' 2; r+="$RESULT "
fv.video.writeStr 0 3 'nope' 3; r+="$RESULT "
fv.video.writeStr 0 -1 'nope' 3; r+="$RESULT "
fv.video.writeStr 9 2 'far' 3; r+="$RESULT "
fv.video.writeChar -3 2 '=' 4 5; r+="$RESULT"
rows
check "clipped to the screen; RESULT stays the unclipped advance" "8 3 4 4 3 5 'cdefgh|111111/    XY|000022/==    |440000/'" "$r '$R'"

scr 6 4
fv.video.setClip 1 1 4 3
fv.video.fillRect 0 0 6 4 5 '.'
fv.video.writeStr 0 2 'abcdef' 6
fv.video.writeBuf 2 1 'pqrs' '1234'
rows
check "setClip X1 Y1 X2 Y2 (exclusive): fillRect, writeStr, writeBuf stay inside" \
    "'      |000000/ .pq  |051200/ bcd  |066600/      |000000/'" "'$R'"
kt_test_start "setClip is intersected with the screen; resetClip; an empty clip writes nothing"
r=''
fv.video.setClip -5 -5 99 99; r+="$__FV_VS_CX1,$__FV_VS_CY1,$__FV_VS_CX2,$__FV_VS_CY2 "
fv.video.setClip 3 3 1 1; fv.video.writeStr 0 0 'zzzzzz' 9; fv.video.fillRect 0 0 6 4 9; rows; r+="${R//[!9]/}. "
fv.video.resetClip; r+="$__FV_VS_CX1,$__FV_VS_CY1,$__FV_VS_CX2,$__FV_VS_CY2"
if [[ $r == '0,0,6,4 . 0,0,6,4' ]]; then kt_test_pass "ok"; else kt_test_fail "$r"; fi
fv.video.setClip 0 0 2 2
FV_SCREEN_W=5 FV_SCREEN_H=2 fv.video.resizeScreen
check "resizeScreen: reallocated at FV_SCREEN_W x H, cleared, the clip reset, all damaged" \
    "5x2 0,0,5,2 0,5 0,5" "${__FV_VS_W}x$__FV_VS_H $__FV_VS_CX1,$__FV_VS_CY1,$__FV_VS_CX2,$__FV_VS_CY2 ${__FV_VS_DX1[0]},${__FV_VS_DX2[0]} ${__FV_VS_DX1[1]},${__FV_VS_DX2[1]}"

# --- bad arguments -------------------------------------------------------------------
scr 4 2
rows; before=$R
r=''
for call in 'writeStr x 0 a 1' 'writeStr 0 0 a' 'writeStr 0 0 a ab' 'writeStr 0 0 a %' 'writeStr 0 0 a ж' \
    'writeStr 1.5 0 a 1' 'writeStr 0 --1 a 1' 'writeStr 0 12345678 a 1' 'writeBuf 0 0 ab a' 'writeBuf 0 0 ab a-' \
    'writeChar 0 0 x 1 -1' 'writeChar 0 0 x 1 z' 'writeCStr 0 0 a 1' 'fillRect 0 0 x 1 1' "fillRect 0 0 1 1 '*'" \
    'clearScreen ..' 'setClip 0 0 1' 'setCursorPos -1 0' 'setCursorPos 0' 'setCursorType 4' 'setCursorType ""' \
    'setColorDepth 8' 'definePalette 0 256 0' 'definePalette 00 1 1' "definePalette '*' 1 1" 'definePalette 1 1 1 2' \
    'definePalette 1 -1 1' 'updateScreen now'; do
    eval "fv.video.$call"; r+="$?"
done
rows
check "bad arguments: rc 2, RESULT '', nothing written" "2222222222222222222222222222 '' $before" "$r '$RESULT' $R"
r=''
fv.video.writeStr 001 -0 'ab' 7; r+="$? "
fv.video.writeStr ' 1' 0 a 1; r+="$? "
rows
check "coordinates are decimal integers: leading zeros and -0 are fine, blanks are not" "0 2  ' ab |0770/    |0000/'" "$r '$R'"

kt_test_start "the bad-argument debug line joins the arguments with spaces, whatever IFS is"
out=$( { IFS=, VERBOSE_KKLASS=debug fv.video.writeStr x 0 'a b' 1; } 2>&1 ) || :
if [[ $out == 'Error: fv.video.writeStr: bad arguments (X Y TEXT ATTR): x 0 a b 1' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

# --- updateScreen: the copy, damage, SGR ------------------------------------------
scr 6 2
fv.video.definePalette a 1 2
fv.video.definePalette b 3 4 1
vt_capture fv.video.updateScreen
check "first frame: every row in full, one CUP per row, one SGR per look, then ?25l" \
    "0 ${E}[1;1H${E}[0;38;5;7;48;5;0m      ${E}[2;1H      ${E}[?25l" "$VT_RC $VT_OUT"
vt_capture fv.video.updateScreen
check "nothing damaged, cursor unchanged: nothing printed (rc 0)" "0 ''" "$VT_RC '$VT_OUT'"
fv.video.writeStr 2 1 '  ' 0
fv.video.writeStr 0 0 '  ' 0
vt_capture fv.video.updateScreen
check "damaged rows equal to the shown copy emit nothing; damage is cleared" "0 '' 0" "$VT_RC '$VT_OUT' ${#__FV_VS_DX1[@]}"
fv.video.writeStr 3 0 'xy' a
fv.video.writeStr 2 1 'Q' b
fv.video.writeStr 4 1 'R' b
vt_capture fv.video.updateScreen
check "only the damaged columns [DX1,DX2) of a changed row; SGR at each change of look; the frame starts with SGR unknown" \
    "${E}[1;4H${E}[0;38;5;1;48;5;2mxy${E}[2;3H${E}[0;1;38;5;3;48;5;4mQ${E}[0;38;5;7;48;5;0m ${E}[0;1;38;5;3;48;5;4mR" "$VT_OUT"
fv.video.definePalette c 1 2
fv.video.writeBuf 0 0 'pq' 'ac'
vt_capture fv.video.updateScreen
check "two symbols with the same look: one SGR" "${E}[1;1H${E}[0;38;5;1;48;5;2mpq" "$VT_OUT"
vt_capture fv.video.updateScreen force
check "force: every cell of every row, no ESC[2J, the cursor state re-sent" \
    "${E}[1;1H${E}[0;38;5;1;48;5;2mpq${E}[0;38;5;7;48;5;0m ${E}[0;38;5;1;48;5;2mxy${E}[0;38;5;7;48;5;0m ${E}[2;1H  ${E}[0;1;38;5;3;48;5;4mQ${E}[0;38;5;7;48;5;0m ${E}[0;1;38;5;3;48;5;4mR${E}[0;38;5;7;48;5;0m ${E}[?25l" "$VT_OUT"
fv.video.writeStr 1 1 'Z' z
vt_capture fv.video.updateScreen
check "an undefined symbol shows in the default look" "${E}[2;2H${E}[0;38;5;7;48;5;0mZ" "$VT_OUT"

# --- the cursor ----------------------------------------------------------------------
fv.video.setCursorPos 3 1
vt_capture fv.video.updateScreen
check "a hidden cursor: a move sends nothing" "''" "'$VT_OUT'"
fv.video.setCursorType 2
vt_capture fv.video.updateScreen
check "shown: its position, then ?25h" "${E}[2;4H${E}[?25h" "$VT_OUT"
vt_capture fv.video.updateScreen
check "shown, unchanged, no text: nothing" "''" "'$VT_OUT'"
fv.video.writeStr 0 0 'k' 0
vt_capture fv.video.updateScreen
check "text written: the cursor position is sent again, ?25h is not" "${E}[1;1H${E}[0;38;5;7;48;5;0mk${E}[2;4H" "$VT_OUT"
fv.video.setCursorPos 50 70
vt_capture fv.video.updateScreen
check "a position off the screen is clamped to the last cell" "${E}[2;6H" "$VT_OUT"
fv.video.setCursorType 1
vt_capture fv.video.updateScreen
check "another visible type (1..3): no shape sequence, nothing sent" "''" "'$VT_OUT'"
fv.video.setCursorType 0
vt_capture fv.video.updateScreen
check "hidden again: ?25l only" "${E}[?25l" "$VT_OUT"

# --- output fd rules ------------------------------------------------------------------
scr 3 1
saved_tty=$FV_TTY_FD
FV_TTY_FD='' FV_VIDEO_OUT_FD=''
fv.video.updateScreen; r="$? ${#__FV_VS_DX1[@]}"
check "no FV_VIDEO_OUT_FD and no FV_TTY_FD: rc 1, nothing emitted, the damage kept" "1 1" "$r"
exec {ttyfd}>"$FVV_TMP/tty.out"
exec {outfd}>"$FVV_TMP/out.out"
FV_TTY_FD=$ttyfd FV_VIDEO_OUT_FD=$outfd fv.video.updateScreen; r=$?
exec {ttyfd}>&- {outfd}>&-
IFS= read -r -d '' a < "$FVV_TMP/tty.out" || :
IFS= read -r -d '' b < "$FVV_TMP/out.out" || :
check "FV_VIDEO_OUT_FD wins over FV_TTY_FD" "0 0 1" "$r ${#a} $(( ${#b} > 0 ))"
exec {ttyfd}>"$FVV_TMP/tty.out"
fv.video.writeStr 0 0 q 0
FV_TTY_FD=$ttyfd fv.video.updateScreen; r=$?
exec {ttyfd}>&-
IFS= read -r -d '' a < "$FVV_TMP/tty.out" || :
check "FV_TTY_FD when FV_VIDEO_OUT_FD is empty" "0 ${E}[1;1H${E}[0;38;5;7;48;5;0mq" "$r $a"
FV_TTY_FD=$saved_tty
exec {bad}>"$FVV_TMP/ro"; exec {bad}<"$FVV_TMP/ro"
fv.video.writeStr 1 0 w 0
FV_VIDEO_OUT_FD=$bad fv.video.updateScreen 2>"$FVV_TMP/err"; r="$? $__FV_VS_FORCE"
err=$(<"$FVV_TMP/err")
vt_capture fv.video.updateScreen
check "a failed printf (a read-only fd): rc 1, silent, and the next frame repaints everything" \
    "1 1 '' ${E}[1;1H${E}[0;38;5;7;48;5;0mqw ${E}[?25l" "$r '$err' $VT_OUT"
kt_test_start "updateScreen prints nothing to stdout or stderr"
out=$( { fv.video.writeStr 0 0 abc 1; FV_VIDEO_OUT_FD=$nullfd fv.video.updateScreen force; } 2>&1 ) 2>&1 || :
if [[ -z $out ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_log "009_Buffer.sh completed"
