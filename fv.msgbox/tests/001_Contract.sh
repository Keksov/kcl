#!/usr/bin/env bash
# 001_Contract.sh - fv.msgbox follows the kcl contract (kcl README §1): the
# source parses; the API (four functions), the readonly FV_MF_* constants
# with FV's values, the translation arrays with FV's texts; fv.dialogs
# loaded by name (its kk.uses line); the unit loads under set -eu (twice;
# by name); the main path (a message box and an input box in a headless
# application, refusals in if / ||) under set -eu; a re-source and
# `kk.unit --forget fv.msgbox` + a re-source keep the constants and a
# replaced translation, and boxes still work; a failing call returns under
# set -e; nothing on stdout; no stray globals or functions after the main
# path; the refusals: argument counts, OPTIONS, `--`, the rectangle,
# VARNAME (RESULT, _fv* / __fv*, not an identifier, readonly, an
# associative array), LIMIT, no application (FV_DESKTOP / FV_APP not live
# groups) — each rc 2, RESULT '', a debug line, nothing drawn, the
# variable kept.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvx_testlib.sh"
fvx_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVX_TESTS_DIR/.." && pwd)/fv.msgbox.sh"
APPU="$(cd "$FVX_TESTS_DIR/../../fv.app" && pwd)/fv.app.sh"
KBOOL="$(cd "$FVX_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the API, the readonly constants (FV's values), the translations (FV's texts), fv.dialogs loaded"
miss=''
for f in messageBox messageBoxRect inputBox inputBoxRect; do declare -F "fv.msgbox.$f" >/dev/null || miss+=" fv.msgbox.$f"; done
declare -A want=([FV_MF_WARNING]=0 [FV_MF_ERROR]=1 [FV_MF_INFORMATION]=2 [FV_MF_CONFIRMATION]=3 [FV_MF_INSERTINAPP]=128
    [FV_MF_YESBUTTON]=256 [FV_MF_NOBUTTON]=512 [FV_MF_OKBUTTON]=1024 [FV_MF_CANCELBUTTON]=2048 [FV_MF_YESNOCANCEL]=2816 [FV_MF_OKCANCEL]=3072)
for v in "${!want[@]}"; do
    [[ ${!v@a} == *r* && ${!v} == "${want[$v]}" ]] || miss+=" $v(${!v-unset})"
done
[[ "${FV_MSGBOX_TITLES[*]}" == 'Warning Error Information Confirm' ]] || miss+=" FV_MSGBOX_TITLES(${FV_MSGBOX_TITLES[*]})"
[[ "${FV_MSGBOX_BUTTONS[*]}" == '~Y~es ~N~o O~k~ Cancel O~K~ Cancel' ]] || miss+=" FV_MSGBOX_BUTTONS(${FV_MSGBOX_BUTTONS[*]})"
declare -F TDialog.new >/dev/null && declare -F fv.dialogs.getText >/dev/null || miss+=' fv.dialogs(kk.uses)'
if [[ -z $miss ]]; then kt_test_pass ok; else kt_test_fail "missing / wrong:$miss"; fi

expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$TMP/setu.err")"; rc=$?
    err="$(<"$TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}
# the main path: a headless application, a scripted source, a message box,
# an input box, refusals in if / ||
MAIN="
exec {FVO}>/dev/null
FV_VIDEO_OUT_FD=\$FVO FV_APP_HEADLESS=1 FV_SCREEN_W=80 FV_SCREEN_H=24
TApplication.new app
q=()
ge() { if (( \${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
       if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
       fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=\${q[0]}; q=(\"\${q[@]:1}\"); }
fv.app._getEvent() { ge; }
q=(kbTab kbEnter)
fv.msgbox.messageBox 'Save %s?' \$(( FV_MF_CONFIRMATION | FV_MF_YESNOCANCEL )) -- f.txt
[[ \$RESULT == cmNo ]]
v=old
q=(kbEnd kbEnter)
fv.msgbox.inputBox 'T' '~N~ame' v 10
[[ \$RESULT == cmOK && \$v == old ]]
if fv.msgbox.messageBox x 70000; then exit 9; fi
fv.msgbox.inputBox T L RESULT 5 || :
app.delete
unset q v"

expect_clean "the unit loads under set -eu" "source '$UNIT'"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.msgbox by name under set -eu (fv.dialogs with it)" \
    "source '$KBOOL'; kk.uses fv.msgbox; declare -F fv.msgbox.messageBox >/dev/null; declare -F TDialog.new >/dev/null"
expect_clean "the main path under set -eu" "source '$UNIT'; source '$APPU'
$MAIN"
expect_clean "a re-source and kk.unit --forget + re-source keep the constants and a replaced translation; boxes still work" "
source '$UNIT'; source '$APPU'
FV_MSGBOX_BUTTONS[3]='Отмена'
source '$UNIT'
kk.unit --forget fv.msgbox
source '$UNIT'
[[ \${FV_MSGBOX_BUTTONS[3]} == Отмена && \${FV_MSGBOX_BUTTONS[0]} == '~Y~es' && \$FV_MF_OKCANCEL == 3072 ]]
$MAIN"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
if fv.msgbox.messageBox x 1; then echo got; else echo none\$?; fi
fv.msgbox.inputBox x || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none2\nrc2\nend' ]]; then kt_test_pass ok; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout, also inside \$( ) (refusals go to stderr)"
out="$(bash -c "
source '$UNIT'; source '$APPU'
x=\$( $MAIN )
y=\$( fv.msgbox.messageBox x 1 2>/dev/null; : )
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
if [[ $out == '[][]' ]]; then kt_test_pass ok; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (FV_MF_*, FV_MSGBOX_*, __FV_MB_*, fv.msgbox.*)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
kk.uses fv.app fv.dialogs
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
$MAIN
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_MF_[A-Z]+|FV_MSGBOX_[A-Z]+|__FV_MB_[A-Z]+|RESULT|REPLY|KK_UNIT_DIR|FVO|__FV_(VW|VS|VI|DR|KB|MS|UN|HL|DG|AP)_[A-Za-z0-9_]+|FV_[A-Z0-9_]+|__KK_SITE_[A-Z0-9]+|__kk_ft)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^(fv\.msgbox\..*|ge|fv\.app\._getEvent)$' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass ok; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_section "001: the refusals"
fvx_app 80 24
fvw_outsize; s0=$REPLY
v='kept'
declare -r ro=1
declare -A as=([k]=1)
# refused CALL... : rc 2, RESULT '', one debug line naming the function
refused() {
    local e
    RESULT=x
    VERBOSE_KKLASS=debug "$@" 2>"$TMP/ref.err"; local rc=$? r=$RESULT
    mapfile -t e < "$TMP/ref.err"
    kt_test_start "refused: ${*:1:9}"
    if (( rc == 2 )) && [[ -z $r && ${#e[@]} == 1 && ${e[0]} == "Error: $1: "* ]]; then kt_test_pass "${e[0]:0:90}"
    else kt_test_fail "rc $rc RESULT [$r] err [${e[*]}]"; fi
}
refused fv.msgbox.messageBox
refused fv.msgbox.messageBox 'x'
refused fv.msgbox.messageBox 'x' ''
refused fv.msgbox.messageBox 'x' abc
refused fv.msgbox.messageBox 'x' -1
refused fv.msgbox.messageBox 'x' 65536
refused fv.msgbox.messageBox 'x' 0x400
refused fv.msgbox.messageBox 'x' '1 | 2'
refused fv.msgbox.messageBox 'x' 1024 a b
refused fv.msgbox.messageBoxRect 1 2 3 'x' 1024
refused fv.msgbox.messageBoxRect a 2 30 12 'x' 1024
refused fv.msgbox.messageBoxRect 1 2 30 1.5 'x' 1024
refused fv.msgbox.messageBoxRect 1 2 30 12 'x' 1024 -x
refused fv.msgbox.messageBoxRect 1 2 30 12 'x' x
refused fv.msgbox.inputBox 'T' 'L' v
refused fv.msgbox.inputBox -p 'T' 'L' v 10 extra
refused fv.msgbox.inputBox 'T' 'L' RESULT 10
refused fv.msgbox.inputBox 'T' 'L' __fvx_v 10
refused fv.msgbox.inputBox 'T' 'L' _FVthing 10
refused fv.msgbox.inputBox 'T' 'L' 1abc 10
refused fv.msgbox.inputBox 'T' 'L' 'a-b' 10
refused fv.msgbox.inputBox 'T' 'L' '' 10
refused fv.msgbox.inputBox 'T' 'L' ro 10
refused fv.msgbox.inputBox 'T' 'L' as 10
refused fv.msgbox.inputBox 'T' 'L' v ''
refused fv.msgbox.inputBox 'T' 'L' v -1
refused fv.msgbox.inputBox 'T' 'L' v 1x
refused fv.msgbox.inputBox -P 'T' 'L' v 10
refused fv.msgbox.inputBoxRect 'T' 'L' v 10
refused fv.msgbox.inputBoxRect 1 2 x 4 'T' 'L' v 10
refused fv.msgbox.inputBoxRect -p 1 2 61 10 'T' 'L' RESULT 10
d=$FV_DESKTOP a=$FV_APP
FV_DESKTOP=''
refused fv.msgbox.messageBox 'x' 1024
refused fv.msgbox.inputBox 'T' 'L' v 10
FV_DESKTOP=nosuch
refused fv.msgbox.messageBoxRect 1 1 41 10 'x' 1024
refused fv.msgbox.inputBoxRect 1 1 61 9 'T' 'L' v 10
FV_DESKTOP=w1l
refused fv.msgbox.messageBox 'x' 1024
FV_DESKTOP=$d FV_APP=''
refused fv.msgbox.messageBox 'x' $(( FV_MF_OKBUTTON | FV_MF_INSERTINAPP ))
FV_APP=$a
kt_test_start "the refusals drew nothing, made nothing, kept the variable; without FV_MF_INSERTINAPP FV_APP is not needed"
fvw_outsize; s1=$REPLY
fvx_live; l=$REPLY
FV_APP=''
fvx_events 'key kbEnter'
fv.msgbox.messageBox 'x' "$FV_MF_OKBUTTON"; r=$RESULT
fva_noevents
FV_APP=$a
if [[ $s1 == "$s0" && -z $l && $v == kept && $r == cmOK ]]; then kt_test_pass ok; else kt_test_fail "out $s0 -> $s1, live [$l], v $v, $r"; fi
fvx_unapp

kt_test_log "001_Contract.sh completed"
