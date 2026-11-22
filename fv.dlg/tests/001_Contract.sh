#!/usr/bin/env bash
# 001_Contract.sh - fv.dlg follows the kcl contract (kcl README §1): the
# source parses; the API (fv.dlg.main, fv.dlg.run), the readonly exit-code
# constants (dialog's DIALOG_OK / _CANCEL / _ESC values), the classes
# (TDlgApp, TDlgTitle), fv.app and fv.dialogs loaded by name; the unit
# loads under set -eu (twice; by name); the main path (each widget of the
# stage headless, the keys from a file through the real fv.drivers, a
# refusal in if / ||) under set -eu; a re-source and `kk.unit --forget
# fv.dlg` + a re-source keep the constants and the boxes still work; a
# failing call returns under set -e; nothing on stdout from the bash face
# (also inside $( )); no stray globals or functions after the main path;
# fork-free: PATH='' over the main path and the static scan (the only
# forking lines are P4-6's buffer, marked `# fork: P4-6`); the refusals'
# words (one line on stderr, rc 255, nothing made).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVDL_TESTS_DIR/.." && pwd)/fv.dlg.sh"
KBOOL="$(cd "$FVDL_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP
printf '\r' > "$TMP/enter.keys"
printf '\t\r' > "$TMP/tab.keys"
printf 'abc\r' > "$TMP/abc.keys"
printf 'x' > "$TMP/x.keys"

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the API, the readonly constants, the classes, fv.app and fv.dialogs loaded"
miss=''
for f in fv.dlg.main fv.dlg.run TDlgApp.new TDlgTitle.new TApplication.new TDialog.new TInputLine.new; do
    declare -F "$f" >/dev/null || miss+=" $f"
done
declare -A want=([FV_DLG_OK]=0 [FV_DLG_CANCEL]=1 [FV_DLG_ESC]=255)
for v in "${!want[@]}"; do
    [[ ${!v@a} == *r* && ${!v} == "${want[$v]}" ]] || miss+=" $v(${!v-unset})"
done
[[ -n ${FV_DLG_CMD+x} ]] || miss+=' FV_DLG_CMD'
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
# the main path: every widget headless, keys from files (the real
# fv.drivers), refusals in if / ||
MAIN="
fv.dlg.run --fv-headless --fv-keys '$TMP/enter.keys' --title T --msgbox 'Hello\\nworld' 0 0
[[ \$RESULT == '' && \$FV_DLG_CMD == cmOK ]]
rc=0; fv.dlg.run --fv-headless --fv-keys '$TMP/tab.keys' --yesno 'Sure?' 0 0 || rc=\$?
[[ \$rc == 1 && \$FV_DLG_CMD == cmNo ]]
fv.dlg.run --fv-headless --fv-keys '$TMP/abc.keys' --inputbox 'Name:' 0 0 old
[[ \$RESULT == abc ]]
fv.dlg.run --fv-headless --fv-keys '$TMP/abc.keys' --passwordbox 'Pass:' 0 0
[[ \$RESULT == abc ]]
fv.dlg.run --fv-headless --backtitle B --infobox 'Wait' 0 0
rc=0; fv.dlg.run --fv-headless --fv-keys '$TMP/x.keys' --msgbox 'eof' 0 0 || rc=\$?
[[ \$rc == 255 ]]
if fv.dlg.run --bogus --msgbox x 0 0 2>/dev/null; then exit 9; fi
fv.dlg.run --msgbox x 0 2>/dev/null || :
unset rc"

expect_clean "the unit loads under set -eu" "source '$UNIT'"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.dlg by name under set -eu (fv.app, fv.dialogs with it)" \
    "source '$KBOOL'; kk.uses fv.dlg; declare -F fv.dlg.run >/dev/null; declare -F TDialog.new >/dev/null; declare -F TApplication.new >/dev/null"
expect_clean "the main path under set -eu" "source '$UNIT'
$MAIN"
expect_clean "a re-source and kk.unit --forget + re-source keep the constants; boxes still work" "
source '$UNIT'
source '$UNIT'
kk.unit --forget fv.dlg
source '$UNIT'
[[ \$FV_DLG_ESC == 255 && \${FV_DLG_OK@a} == *r* ]]
$MAIN"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
if fv.dlg.run --nosuch 2>/dev/null; then echo got; else echo none\$?; fi
fv.dlg.run 2>/dev/null || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none255\nrc255\nend' ]]; then kt_test_pass ok; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout from the bash face, also inside \$( ) (refusals go to stderr)"
out="$(bash -c "
source '$UNIT'
x=\$( $MAIN )
y=\$( fv.dlg.run --bogus 2>/dev/null; : )
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
if [[ $out == '[][]' ]]; then kt_test_pass ok; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (FV_DLG_*, __FV_DL_*, fv.dlg.*, TDlg*)"
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
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(FV_DLG_[A-Z]+|__FV_DL_[A-Z]+|TDlg(App|Title)_[A-Za-z_]+|RESULT|REPLY|KK_UNIT_DIR|__FV_(VW|VS|VI|DR|KB|KL|MS|UN|UC|HL|DG|AP|MN)_[A-Za-z0-9_]+|FV_[A-Z0-9_]+|__KK_SITE_[A-Z0-9]+|__kk_ft|__kk_[a-z_]+)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^(fv\.dlg\..*|TDlg(App|Title)\..*|__kk[cm]\.TDlg(App|Title).*)$' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass ok; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_section "001: fork-free"
kt_test_start "PATH='': the main path, no external command"
out="$(bash -c "
source '$UNIT'
PATH=''
$MAIN
printf done" 2>&1)"
if [[ $out == done ]]; then kt_test_pass ok; else kt_test_fail "out='$out'"; fi

kt_test_start "the static scan: no forking construct on a code line of fv.dlg.sh but P4-6's (marked)"
bad='' n=0 fn='' marked=0
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if [[ $l == *'# fork: P4-6'* ]]; then marked=$(( marked + 1 )); continue; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$UNIT"
if [[ -z $bad ]] && (( n > 300 && marked >= 1 )); then kt_test_pass "$n lines clean, $marked marked"; else kt_test_fail "${bad:-only $n lines, $marked marked}"; fi

kt_test_section "001: the refusals' words"
# refused WANT ARG... : rc 255, exactly one stderr line WANT, RESULT '', no view made
refused() {
    local want=$1 e rc r
    shift
    RESULT=x
    fv.dlg.run "$@" 2>"$TMP/ref.err"; rc=$? r=$RESULT
    mapfile -t e < "$TMP/ref.err"
    fvdl_live
    kt_test_start "refused: ${*:1:8}"
    if (( rc == 255 )) && [[ -z $r && ${#e[@]} == 1 && ${e[0]} == "fv.dlg.run: $want" && -z $REPLY ]]; then kt_test_pass "${e[0]:0:100}"
    else kt_test_fail "rc $rc RESULT [$r] err [${e[*]}] live [$REPLY]"; fi
}
refused "no widget (--msgbox, --yesno, --infobox, --inputbox, --passwordbox)"
refused "unknown option '--bogus'" --bogus --msgbox x 0 0
refused "unexpected argument 'hello'" hello --msgbox x 0 0
refused "'--msgbox' needs TEXT HEIGHT WIDTH (got 2 of 3)" --msgbox x 0
refused "HEIGHT must be an integer (got 'x')" --msgbox t x 10
refused "WIDTH must be an integer (got '1.5')" --msgbox t 10 1.5
refused "unexpected argument 'extra'" --msgbox t 0 0 extra
refused "one widget per call ('--yesno' after '--msgbox'); --and-widget is not supported" --msgbox a 0 0 --yesno b 0 0
refused "'--menu' is not supported yet" --menu t 0 0 0 a A
refused "option '--help-button' is not supported (outside fvdlg's whiptail / dialog subset)" --help-button --msgbox t 0 0
refused "option '--title' needs a value" --msgbox t 0 0 --title
refused "option '--defaultno' takes no value" --defaultno=1 --yesno t 0 0
refused "--output-fd needs a file descriptor number (got 'x')" --output-fd x --msgbox t 0 0
refused "--fv-palette must be gray | blue | cyan (got 'red')" --fv-palette red --msgbox t 0 0
refused "--fv-size must be WxH, 1..1000 each (got '80')" --fv-headless --fv-size 80 --msgbox t 0 0
refused "--fv-keys, --fv-size and --fv-out are for --fv-headless" --fv-keys f --msgbox t 0 0
refused "'--help' is for the command (fvdlg)" --help
refused "cannot read the key file '$TMP/none.keys'" --fv-headless --fv-keys "$TMP/none.keys" --msgbox t 0 0

kt_test_start "the command's face says 'fvdlg:'; --version and --help answer on stdout, rc 0"
out=$(fv.dlg.main --bogus 2>&1 >/dev/null); rc=$?
v=$(fv.dlg.main --version); rv=$?
h=$(fv.dlg.main --title x --help); rh=$?
if (( rc == 255 && rv == 0 && rh == 0 )) && [[ $out == "fvdlg: unknown option '--bogus'" && $v == 'fvdlg '*' (kbool fv.dlg)' && $h == 'Usage: fvdlg '* ]]; then kt_test_pass ok
else kt_test_fail "rc $rc [$out] rv $rv [$v] rh $rh [${h:0:40}]"; fi

kt_test_log "001_Contract.sh completed"
