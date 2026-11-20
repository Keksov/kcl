#!/usr/bin/env bash
# 008_Contract.sh - the kcl-wide contract for fv.keyboard (kcl/README.md §1):
#   source integrity  bash -n, no single-quoted format string left open;
#   set -eu (1.4)      loads, re-loads, loads by name and runs its main path
#                      under `set -eu`; a reload after `kk.unit --forget` is
#                      clean and keeps FV_KEY_FD; a failing call returns to
#                      the caller from `if` / `||`;
#   no stray names     loading and using the unit leaves only its documented
#                      globals (FV_KEY*, __FV_KB_*, the layout tables'
#                      __FV_KL_*, RESULT; KK_UNIT_DIR is the loader's) and
#                      fv.keyboard.* functions behind.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvk_testlib.sh"
fvk_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVK_TESTS_DIR/.." && pwd)/fv.keyboard.sh"
KBOOL="$(cd "$FVK_TESTS_DIR/../../.." && pwd)/kbool.sh"

kt_test_section "008: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "no single-quoted string is left open at end of line"
if bad="$(grep -nE "printf '[^']*\$" "$UNIT")"; then kt_test_fail "${bad//$'\n'/ | }"; else kt_test_pass "none"; fi

# expect_clean TITLE SNIPPET — a child `bash -c` under set -eu: rc 0, prints OK only
expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$FVK_TMP/setu.err")"; rc=$?
    err="$(<"$FVK_TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}

expect_clean "the unit loads under set -eu" "source '$UNIT'"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.keyboard by name under set -eu" "source '$KBOOL'; kk.uses fv.keyboard; declare -F fv.keyboard.getKeyEvent >/dev/null"
printf '[Ax\0\xd0\xb6' > "$FVK_TMP/main.bin"
expect_clean "the main path under set -eu (decode, feed, poll, get, NUL, EOF in if, rc 1/2 in ||)" "
source '$UNIT'
fv.keyboard.decode \$'\\e[1;5D'; [[ \$FV_KEY == kbCtrlLeft ]]
fv.keyboard.decode \$'\\e[99~';  [[ \$FV_KEY == kbUnknown ]]
fv.keyboard.decode \$'\\e[<0;1;1M'; [[ \$FV_KEY == kbMouse ]]
fv.keyboard.decode \$'\\e\\e';  [[ \$FV_KEY == kbAltEsc ]]
fv.keyboard.decode '' || :
fv.keyboard.getKeyEvent junk || :
exec {fd}<'$FVK_TMP/main.bin'
FV_KEY_FD=\$fd
fv.keyboard.feed \$'\\e'
fv.keyboard.pollKeyEvent; [[ \$FV_KEY == kbUp ]]
fv.keyboard.getKeyEvent;  [[ \$FV_KEY == kbUp ]]
fv.keyboard.getKeyEvent 0; [[ \$FV_KEY == kbChar ]]
fv.keyboard.getKeyEvent 1; [[ \$FV_KEY == kbCtrlSpace ]]
fv.keyboard.getKeyEvent;  [[ \$FV_KEY_CHAR == ж ]]
if fv.keyboard.getKeyEvent; then exit 9; fi
[[ \$FV_KEY_EOF == 1 ]]"
expect_clean "kk.unit --forget + re-source under set -e is clean and keeps FV_KEY_FD" "
source '$UNIT'
FV_KEY_FD=7
kk.unit --forget fv.keyboard
source '$UNIT'
[[ \$FV_KEY_FD == 7 ]]
fv.keyboard.decode \$'\\eOP' >/dev/null
[[ \$FV_KEY == kbF1 ]]"

kt_test_start "a failing call returns to the caller under set -e (if and ||)"
out="$(bash -c "set -e
source '$UNIT'
exec {fd}</dev/null
FV_KEY_FD=\$fd
if fv.keyboard.getKeyEvent; then echo got; else echo none; fi
fv.keyboard.getKeyEvent x || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

# --- no stray names ---------------------------------------------------------------
kt_test_start "loading and using the unit (incl. the layout tables and their variants) leaves only FV_KEY*, __FV_KB_*, the tables' __FV_KL_*, RESULT and fv.keyboard.* behind"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$FVK_TMP/v0'
compgen -A function | LC_ALL=C sort > '$FVK_TMP/f0'
source '$UNIT'
exec 8<'$FVK_TMP/main.bin'
FV_KEY_FD=8
fv.keyboard.feed \$'\\e\\e[A\\e[?5u\\e[1072::102;3u'
fv.keyboard.decode \$'\\e[M\\xc3\\xa9!' >/dev/null
fv.keyboard.decode \$'\\xf0\\x9f\\x98\\x80' >/dev/null
fv.keyboard.decode \$'\\e\\xd0\\xb6' >/dev/null
FV_KBD_LAYOUT=bg_phonetic,nosuch fv.keyboard.layoutBase \$'\\xd1\\x84' >/dev/null
while fv.keyboard.getKeyEvent 0; do :; done
fv.keyboard.pollKeyEvent
fv.keyboard.getKeyEvent bad
FV_ESC_TIMEOUT=x fv.keyboard.getKeyEvent 0
fv.keyboard.flush
exec 8<&-
unset FV_KEY_FD
compgen -v | LC_ALL=C sort > '$FVK_TMP/v1'
compgen -A function | LC_ALL=C sort > '$FVK_TMP/f1'
" 2>&1)"
newv="$(comm -13 "$FVK_TMP/v0" "$FVK_TMP/v1" | grep -vE '^(FV_KEY|FV_KEY_CHAR|FV_KEY_SEQ|FV_KEY_LEN|FV_KEY_EOF|FV_KEY_BASE|__FV_KB_[A-Z0-9]+|__FV_KL_[A-Z]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$FVK_TMP/f0" "$FVK_TMP/f1" | grep -v '^fv\.keyboard\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"
fi

kt_test_log "008_Contract.sh completed"
