#!/usr/bin/env bash
# 007_Contract.sh - the kcl-wide contract for fv.video (kcl/README.md §1):
# source integrity; loads, re-loads, loads by name (without any other fv
# unit) and runs its no-terminal path and the reader (D13, a fifo as the
# terminal) under `set -eu`; a reload after
# `kk.unit --forget` is clean and keeps the state; a failing call returns to
# the caller from `if` / `||`; nothing is printed to stdout, also inside
# $( ); using it (the screen buffer and the reader too) leaves only FV_SCREEN_W/H,
# FV_VIDEO_*, FV_TTY_FD, __FV_VI_*, __FV_VS_*, RESULT and fv.video.* behind
# (plus what the unit it loads leaves: __FV_UC_* and fv.unicode.*).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVV_TESTS_DIR/.." && pwd)/fv.video.sh"
KBOOL="$(cd "$FVV_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVV_TMP

kt_test_section "007: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then kt_test_fail "${bad//$'\n'/ | }"; else kt_test_pass "none"; fi

expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$TMP/setu.err")"; rc=$?
    err="$(<"$TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}

expect_clean "the unit loads under set -eu" "source '$UNIT'"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.video by name under set -eu, without fv.keyboard / fv.mouse" \
    "source '$KBOOL'; kk.uses fv.video; declare -F fv.video.initVideo >/dev/null; [[ -z \${__KK_UNITS[fv.keyboard]-}\${__KK_UNITS[fv.mouse]-} ]]"
expect_clean "the no-terminal path under set -eu (failing init in if / ||, done, size)" "
source '$UNIT'
if FV_TTY=/nonexistent fv.video.initVideo; then exit 9; fi
fv.video.initVideo bad || :
FV_TTY=/dev/null fv.video.initVideo || :
fv.video.doneVideo
fv.video.querySize || :
FV_VIDEO_RESIZED=1
fv.video.updateSize
[[ \$FV_VIDEO_RESIZED == 0 && \$FV_SCREEN_W -gt 0 ]]
fv.video.querySize() { RESULT='25 81'; }
fv.video.updateSize
[[ \${FV_SCREEN_W}x\$FV_SCREEN_H == 81x25 ]]"
expect_clean "kk.unit --forget + re-source under set -e is clean and keeps the state" "
source '$UNIT'
FV_SCREEN_W=132 FV_VIDEO_RESIZED=1
kk.unit --forget fv.video
source '$UNIT'
[[ \$FV_SCREEN_W == 132 && \$FV_VIDEO_RESIZED == 1 && \$FV_VIDEO_ON == 0 ]]"

expect_clean "the screen buffer under set -eu: init, writes, failing calls in if / ||, updates, resize" "
source '$UNIT'
FV_SCREEN_W=12 FV_SCREEN_H=3 fv.video.initScreen
exec {fd}>/dev/null; FV_VIDEO_OUT_FD=\$fd
fv.video.writeStr 0 0 'abc жук' 1; fv.video.writeBuf 0 1 xy AB; fv.video.writeCStr 0 2 '~a~b' 1 2
fv.video.writeChar 5 2 '#' 3 4; fv.video.fillRect 0 0 3 3 4; fv.video.clearScreen; fv.video.strWidth x
fv.video.setClip 0 0 5 5; fv.video.resetClip; fv.video.setCursorPos 1 1; fv.video.setCursorType 2
fv.video.definePalette z 1 2 1; fv.video.setColorDepth 16; fv.video.detectColorDepth
if fv.video.writeStr x 0 a 1; then exit 9; fi
fv.video.updateScreen bad || :
fv.video.updateScreen; fv.video.updateScreen force
FV_VIDEO_OUT_FD='' fv.video.updateScreen || :
FV_SCREEN_W=4 FV_SCREEN_H=2 fv.video.resizeScreen; fv.video.updateScreen
[[ \${#__FV_VS_CH[@]} == 2 && \${__FV_VS_CH[0]} == '    ' ]]"
expect_clean "a reload after kk.unit --forget keeps the screen, the palette and the depth" "
source '$UNIT'
FV_SCREEN_W=5 FV_SCREEN_H=2 fv.video.initScreen; fv.video.writeStr 0 0 hi 3; fv.video.setColorDepth 16
kk.unit --forget fv.video
source '$UNIT'
[[ \${__FV_VS_CH[0]} == 'hi   ' && \$FV_VIDEO_COLORS == 16 && \${__FV_VS_PAL[3]} == '8 7 0' && \$__FV_VS_H == 2 ]]"

rm -f "$TMP/c.fifo"; mkfifo "$TMP/c.fifo"
expect_clean "the reader (D13) under set -eu: start, a key through its pipe, stop (a fifo as the terminal)" "
source '$KBOOL'; kk.uses fv.drivers
exec {f}<>'$TMP/c.fifo'
FV_KEY_FD=\$f; __FV_VI_FD=\$f
FV_TTY_READER=1 fv.video._rstart
[[ -n \$__FV_VI_RPID && -n \$__FV_VI_WPID && -n \$__FV_VI_WFD && \$FV_KEY_FD == \"\$__FV_VI_RFD\" ]]
printf q >&\$f
fv.keyboard.getKeyEvent 2
[[ \$FV_KEY_CHAR == q ]]
fv.video._rstop
[[ -z \$__FV_VI_RPID\$__FV_VI_RFD\$__FV_VI_WPID\$__FV_VI_WFD ]]"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
if FV_TTY=/nonexistent fv.video.initVideo; then echo got; else echo none; fi
fv.video.initVideo junk || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing reaches stdout, also inside \$( ) (a TUI may run inside x=\$(...))"
out="$(bash -c "
source '$UNIT'
x=\$(FV_TTY=/nonexistent fv.video.initVideo; fv.video.initVideo bad; fv.video.updateSize; fv.video.querySize; fv.video.doneVideo
     fv.video.querySize() { RESULT='1 2'; }; fv.video.updateSize
     fv.video.initScreen; fv.video.writeStr 0 0 x 1; fv.video.updateScreen; fv.video.writeStr x; fv.video.strWidth abc
     fv.video.definePalette q 1 1; fv.video.detectColorDepth)
printf '[%s]' \"\$x\"" 2>&1)"
if [[ $out == '[]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only FV_SCREEN_W/H, FV_VIDEO_ON/RESIZED/ASCII/COLORS/OUT_FD, FV_TTY_FD, __FV_VI_*, __FV_VS_*, RESULT and fv.video.* behind (+ fv.unicode's __FV_UC_*, fv.unicode.*)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
FV_TTY=/nonexistent fv.video.initVideo
fv.video.initVideo bad
fv.video.doneVideo
fv.video.updateSize
fv.video._trap; fv.video._untrap
FV_SCREEN_W=6 FV_SCREEN_H=2 fv.video.initScreen
exec {fd}>/dev/null; FV_VIDEO_OUT_FD=\$fd
fv.video.writeStr 0 0 'жук ─' 1; fv.video.writeCStr 0 1 '~a~b' 1 2; fv.video.writeChar 0 0 x 1 2; fv.video.writeBuf 0 0 a b
fv.video.fillRect 0 0 2 2 3; fv.video.setClip 0 0 1 1; fv.video.resetClip; fv.video.setCursorPos 1 1; fv.video.setCursorType 1
fv.video.definePalette z 9 9; fv.video.setColorDepth 16; fv.video.detectColorDepth; fv.video.strWidth x
fv.video.updateScreen; fv.video.updateScreen force; fv.video.resizeScreen; fv.video.clearScreen
FV_ASCII=1 fv.video.initScreen; fv.video.writeStr 0 0 '═ж' 1; fv.video.updateScreen
exec {fd}>&-; unset fd
exec {fd}<>'$TMP/c.fifo'
__FV_VI_FD=\$fd FV_TTY_READER=1 fv.video._rstart; fv.video._rstop
exec {fd}>&-; unset fd FV_KEY_FD
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_SCREEN_[WH]|FV_VIDEO_(ON|RESIZED|ASCII|COLORS|OUT_FD)|FV_TTY_FD|__FV_VI_[A-Z]+|__FV_VS_[A-Z0-9]+|__FV_UC_[A-Z]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^fv\.(video|unicode)\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_log "007_Contract.sh completed"
