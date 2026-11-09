#!/usr/bin/env bash
# 007_Contract.sh - the kcl-wide contract for fv.drivers (kcl/README.md §1):
# source integrity; loads (with fv.keyboard, fv.mouse and fv.video by name),
# re-loads and runs its main path under `set -eu`; a reload after
# `kk.unit --forget` is clean; a failing call returns to the caller from
# `if` / `||`; getEvent never prints, also inside $( ) and a pipeline; using it
# leaves only FV_EV_*, __FV_DR_*, its dependencies' globals, RESULT and
# fv.drivers.* (plus the dependencies' functions) behind.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvd_testlib.sh"
fvd_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVD_TESTS_DIR/.." && pwd)/fv.drivers.sh"
KBOOL="$(cd "$FVD_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVD_TMP

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

printf '%s' $'a\e[<0;2;2M\e[<0;2;2m\e[<64;1;1M' > "$TMP/main.bin"
expect_clean "the unit loads under set -eu, with its three dependencies" \
    "source '$UNIT'; [[ -n \${__KK_UNITS[fv.keyboard]-} && -n \${__KK_UNITS[fv.mouse]-} && -n \${__KK_UNITS[fv.video]-} ]]"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.drivers by name under set -eu" "source '$KBOOL'; kk.uses fv.drivers; declare -F fv.drivers.getEvent >/dev/null"
expect_clean "the main path under set -eu (keys, mouse, wheel, put, clear, resize, timeout, end of input in if, rc 2 in ||)" "
source '$UNIT'
exec {fd}<'$TMP/main.bin'
FV_KEY_FD=\$fd
fv.drivers.getEvent; [[ \$FV_EV_WHAT == evKeyDown ]]
fv.drivers.getEvent; [[ \$FV_EV_WHAT == evMouseDown ]]
fv.drivers.getEvent; [[ \$FV_EV_WHAT == evMouseUp ]]
fv.drivers.getEvent; [[ \$FV_EV_WHAT == evMouseWheel ]]
fv.drivers.putEvent
fv.drivers.clearEvent
fv.drivers.getEvent; [[ \$FV_EV_WHAT == evMouseWheel ]]
fv.video.querySize() { RESULT='10 20'; }
FV_VIDEO_RESIZED=1
fv.drivers.getEvent; [[ \$FV_EV_COMMAND == cmResizeApp ]]
if fv.drivers.getEvent; then exit 9; fi
[[ \$FV_EV_EOF == 1 ]]
fv.drivers.getEvent junk || :
fv.drivers.initEvents || :
fv.drivers.doneEvents"
expect_clean "kk.unit --forget + re-source under set -e is clean" "
source '$UNIT'
kk.unit --forget fv.drivers
source '$UNIT'
exec {fd}<'$TMP/main.bin'
FV_KEY_FD=\$fd
fv.drivers.getEvent; [[ \$FV_EV_CHAR == a ]]"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
exec {fd}</dev/null
FV_KEY_FD=\$fd
if fv.drivers.getEvent; then echo got; else echo none; fi
fv.drivers.getEvent x || echo rc\$?
fv.drivers.initEvents || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nrc1\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "getEvent never prints, also inside \$( ) and a pipeline (mouse events included)"
out="$(bash -c "
source '$UNIT'
exec {fd}<'$TMP/main.bin'
FV_KEY_FD=\$fd
x=\$(while fv.drivers.getEvent; do :; done; fv.drivers.putEvent; fv.drivers.clearEvent)
y=\$(true | while fv.drivers.getEvent 0; do :; done)
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>&1)"
if [[ $out == '[][]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only FV_EV_*, __FV_DR_*, its dependencies' names, RESULT and fv.* functions behind"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
exec 8<'$TMP/main.bin'
FV_KEY_FD=8
while fv.drivers.getEvent 0; do :; done
fv.drivers.putEvent; fv.drivers.clearEvent
fv.video.querySize() { RESULT='10 20'; }
FV_VIDEO_RESIZED=1; fv.drivers.getEvent
FV_IDLE_TIMEOUT=x FV_DOUBLE_DELAY=y fv.drivers.getEvent bad
fv.drivers.initEvents; fv.drivers.doneEvents
exec 8<&-
unset FV_KEY_FD FV_IDLE_TIMEOUT FV_DOUBLE_DELAY
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_EV_[A-Z_]+|__FV_DR_[A-Z]+|FV_KEY|FV_KEY_[A-Z]+|__FV_KB_[A-Z0-9]+|FV_MOUSE_[A-Z]+|__FV_MS_ORD|FV_SCREEN_[WH]|FV_VIDEO_(ON|RESIZED|ASCII|COLORS|OUT_FD)|FV_TTY_FD|__FV_VI_[A-Z]+|__FV_VS_[A-Z0-9]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^fv\.(drivers|keyboard|mouse|video)\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_log "007_Contract.sh completed"
