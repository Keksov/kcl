#!/usr/bin/env bash
# 007_Contract.sh - the kcl-wide contract for fv.video (kcl/README.md §1):
# source integrity; loads, re-loads, loads by name (without any other fv
# unit) and runs its no-terminal path under `set -eu`; a reload after
# `kk.unit --forget` is clean and keeps the state; a failing call returns to
# the caller from `if` / `||`; nothing is printed to stdout, also inside
# $( ); using it leaves only FV_SCREEN_W/H, FV_VIDEO_*, FV_TTY_FD,
# __FV_VI_*, RESULT and fv.video.* behind.

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
     fv.video.querySize() { RESULT='1 2'; }; fv.video.updateSize)
printf '[%s]' \"\$x\"" 2>&1)"
if [[ $out == '[]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only FV_SCREEN_W/H, FV_VIDEO_ON/RESIZED, FV_TTY_FD, __FV_VI_*, RESULT and fv.video.* behind"
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
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_SCREEN_[WH]|FV_VIDEO_(ON|RESIZED)|FV_TTY_FD|__FV_VI_[A-Z]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -v '^fv\.video\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_log "007_Contract.sh completed"
