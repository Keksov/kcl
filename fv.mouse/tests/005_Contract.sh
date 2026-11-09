#!/usr/bin/env bash
# 005_Contract.sh - the kcl-wide contract for fv.mouse (kcl/README.md §1):
# source integrity; loads, re-loads, loads by name and runs its main path
# under `set -eu`; a reload after `kk.unit --forget` is clean; a failing call
# returns to the caller from `if` / `||`; using it leaves only FV_MOUSE_*, __FV_MS_ORD,
# RESULT and fv.mouse.* behind (and does not need fv.keyboard).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../ktests/ktest.sh"
kt_test_init "$(basename "$0" .sh)" "$SCRIPT_DIR" "$@"
TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
UNIT="$(cd "$SCRIPT_DIR/.." && pwd)/fv.mouse.sh"
KBOOL="$(cd "$SCRIPT_DIR/../../.." && pwd)/kbool.sh"

kt_test_section "005: the kcl contract"

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
expect_clean "kk.uses fv.mouse by name under set -eu, without fv.keyboard" \
    "source '$KBOOL'; kk.uses fv.mouse; declare -F fv.mouse.decode >/dev/null; [[ -z \${__KK_UNITS[fv.keyboard]-} ]]"
expect_clean "the main path under set -eu" "
source '$UNIT'
fv.mouse.decode \$'\\e[<0;10;5M'; [[ \$FV_MOUSE_WHAT == down ]]
fv.mouse.decode \$'\\e[<65;1;1M'; [[ \$FV_MOUSE_WHAT == wheel ]]
fv.mouse.decode \$'\\e[M#!!';     [[ \$FV_MOUSE_WHAT == up ]]
fv.mouse.decode junk || :
if fv.mouse.decode ''; then exit 9; fi
fv.mouse.enable 1 >/dev/null
fv.mouse.enable 1 any >/dev/null
fv.mouse.disable >/dev/null
fv.mouse.enable x || :"
expect_clean "kk.unit --forget + re-source under set -e is clean" "
source '$UNIT'
kk.unit --forget fv.mouse
source '$UNIT'
fv.mouse.decode \$'\\e[<2;3;4m'; [[ \$FV_MOUSE_WHAT\$FV_MOUSE_BUTTON == up3 ]]"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
if fv.mouse.decode x; then echo got; else echo none; fi
fv.mouse.enable '' any0 >/dev/null || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only FV_MOUSE_*, __FV_MS_ORD, RESULT and fv.mouse.* behind"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
fv.mouse.decode \$'\\e[<0;10;5M'
fv.mouse.decode \$'\\e[M\\xc0\\xff\\xff'
fv.mouse.decode bad
fv.mouse.enable 1 any >/dev/null
fv.mouse.disable >/dev/null
fv.mouse.enable x
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_MOUSE_(WHAT|BUTTON|X|Y|MODS)|__FV_MS_ORD|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -v '^fv\.mouse\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_start "the caller's locale and nocasematch are back after every entry point (\${#ж} stays 1)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$UNIT'
w=ж r=''
fv.mouse.decode \$'\\e[M \\xff\\xff'; r+=\${#w}
fv.mouse.decode \$'\\e[<0;1;1M'; r+=\${#w}
fv.mouse.decode bad; r+=\${#w}
fv.mouse.enable 1 >/dev/null; r+=\${#w}
fv.mouse.disable 1 >/dev/null; r+=\${#w}
shopt -s nocasematch; fv.mouse.decode bad; r+=\${#w}; shopt -q nocasematch && r+=on
printf '%s|%s' \"\$r\" \"\$LC_ALL\"" 2>&1)"
if [[ $out == '111111on|C.UTF-8' ]]; then kt_test_pass "$out"; else kt_test_fail "'$out'"; fi

kt_test_log "005_Contract.sh completed"
