#!/usr/bin/env bash
# 001_Contract.sh - the kcl-wide contract for fv.histlist (kcl/README.md §1):
# source integrity; loads, re-loads, loads by name and runs its main path
# under `set -eu`; a reload (and `kk.unit --forget` + re-source) keeps the
# history (per process); the first load drops __FV_HL_* the environment
# brought; a failing call returns to the caller from `if` / `||`; using it
# leaves only FV_HISTORY_SIZE, __FV_HL_*, RESULT and fv.histlist.* behind;
# fv.dialogs loads it by name (its kk.uses line).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvh_testlib.sh"
fvh_init "$(basename "$0" .sh)" "$@"
UNIT="$(cd "$FVH_TESTS_DIR/.." && pwd)/fv.histlist.sh"
KBOOL="$(cd "$FVH_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVH_TMP

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

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
expect_clean "kk.uses fv.histlist by name under set -eu" \
    "source '$KBOOL'; kk.uses fv.histlist; declare -F fv.histlist.historyAdd >/dev/null"
expect_clean "the main path under set -eu" "
source '$UNIT'
fv.histlist.historyCount 3; [[ \$RESULT == 0 ]]
if fv.histlist.historyStr 3 0; then exit 9; fi
fv.histlist.historyAdd 3 one; fv.histlist.historyAdd 3 two; fv.histlist.historyAdd 3 ''
fv.histlist.historyCount 3; [[ \$RESULT == 2 ]]
fv.histlist.historyStr 3 0; [[ \$RESULT == two ]]
fv.histlist.historyAdd 300 x || :
fv.histlist.clearHistory
fv.histlist.historyCount 3; [[ \$RESULT == 0 ]]"
expect_clean "a re-source and kk.unit --forget + re-source keep the history" "
source '$UNIT'
fv.histlist.historyAdd 7 kept
source '$UNIT'
kk.unit --forget fv.histlist
source '$UNIT'
fv.histlist.historyStr 7 0; [[ \$RESULT == kept ]]
fv.histlist.historyAdd 7 more
fv.histlist.historyCount 7; [[ \$RESULT == 2 ]]"

kt_test_start "the first load drops __FV_HL_* from the environment (a scalar cannot pose as a list)"
out="$(__FV_HL_T4=junk __FV_HL_SEQ=99 __FV_HL_USED=x bash -c "
source '$UNIT'
fv.histlist.historyCount 4; c=\$RESULT
fv.histlist.historyAdd 4 a
fv.histlist.historyCount 4
printf '%s %s %s' \"\$c\" \"\$RESULT\" \"\$__FV_HL_USED\"" 2>&1)"
if [[ $out == '0 1 5' ]]; then kt_test_pass "$out"; else kt_test_fail "'$out'"; fi

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
if fv.histlist.historyStr 1 5; then echo got; else echo none\$?; fi
fv.histlist.historyAdd x y || echo rc\$?
fv.histlist.historyCount || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none1\nrc2\nrc2\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "using the unit leaves only FV_HISTORY_SIZE, __FV_HL_*, RESULT and fv.histlist.* behind"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
fv.histlist.historyAdd 0 a; fv.histlist.historyAdd 255 жук; fv.histlist.historyAdd 0 b; fv.histlist.historyAdd 0 a
fv.histlist.historyCount 0; fv.histlist.historyStr 255 0; fv.histlist.historyStr 0 9
fv.histlist.historyAdd 999 x
fv.histlist.clearHistory
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_HISTORY_SIZE|__FV_HL_[A-Z0-9]+|RESULT|KK_UNIT_DIR)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -v '^fv\.histlist\.' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_start "fv.dialogs loads fv.histlist by name (its kk.uses line)"
out="$(bash -c "source '$KBOOL'; kk.uses fv.dialogs >/dev/null 2>&1; declare -F fv.histlist.historyAdd >/dev/null && echo yes" 2>&1)"
if [[ $out == yes ]]; then kt_test_pass ok; else kt_test_fail "'$out'"; fi

kt_test_log "001_Contract.sh completed"
