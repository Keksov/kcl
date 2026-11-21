#!/usr/bin/env bash
# 001_Contract.sh - fv.dialogs follows the kcl contract (kcl README §1) as
# fv.views does: the source parses; the public API exists (plain functions,
# the classes, their methods; every built-in virtual in fv.views' elision
# table, the funcs marked, the broadcast rows, the hot-key texts and the
# cluster's item test); the unit loads under set -eu (twice; by name through kk.uses); the main path (a
# dialog with every widget, drawn, run modally to the default button, the
# data, the setters, refusals in if / ||, the destructors) under set -eu;
# `kk.unit --forget fv.dialogs` + a re-source keeps live widgets and the
# table entries; after `kk.unit --forget fv.views` + a re-source fv.views
# merges its tables, fv.dialogs' entries stay and a dialog still runs; a
# failing call returns under set -e; nothing on stdout; no stray globals or
# functions after the main path.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVG_TESTS_DIR/.." && pwd)/fv.dialogs.sh"
KBOOL="$(cd "$FVG_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP
CLASSES='TDialog TButton TStaticText TParamText TLabel TCluster TCheckBoxes TRadioButtons TInputLine TListBox'

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the public API is defined (plain functions, the classes, their methods)"
miss=''
for f in getData setData dataSize setTitle setLabel setItems setButtonState makeDefault newButton newLabel getText setText selectAll newList _register; do
    declare -F "fv.dialogs.$f" >/dev/null || miss+=" fv.dialogs.$f"
done
for c in $CLASSES; do declare -F "$c.new" >/dev/null || miss+=" $c.new"; done
for m in HandleEvent GetPalette Valid CalcBounds; do [ "${TDialog_class_method_owner[$m]-}" = TDialog ] || miss+=" TDialog.$m"; done
for m in Draw HandleEvent GetPalette SetState Press; do [ "${TButton_class_method_owner[$m]-}" = TButton ] || miss+=" TButton.$m"; done
for m in Draw GetPalette GetText; do [ "${TStaticText_class_method_owner[$m]-}" = TStaticText ] || miss+=" TStaticText.$m"; done
for m in GetText DataSize GetData SetData; do [ "${TParamText_class_method_owner[$m]-}" = TParamText ] || miss+=" TParamText.$m"; done
for m in Draw GetPalette HandleEvent; do [ "${TLabel_class_method_owner[$m]-}" = TLabel ] || miss+=" TLabel.$m"; done
for m in Draw HandleEvent GetPalette SetState GetHelpCtx Mark Press MovedTo DataSize GetData SetData; do [ "${TCluster_class_method_owner[$m]-}" = TCluster ] || miss+=" TCluster.$m"; done
for m in Draw Mark Press; do [ "${TCheckBoxes_class_method_owner[$m]-}" = TCheckBoxes ] || miss+=" TCheckBoxes.$m"; done
for m in Draw Mark Press MovedTo SetData; do [ "${TRadioButtons_class_method_owner[$m]-}" = TRadioButtons ] || miss+=" TRadioButtons.$m"; done
for m in Draw HandleEvent GetPalette SetState Valid DataSize GetData SetData SelectAll; do [ "${TInputLine_class_method_owner[$m]-}" = TInputLine ] || miss+=" TInputLine.$m"; done
for m in DataSize GetData SetData NewList; do [ "${TListBox_class_method_owner[$m]-}" = TListBox ] || miss+=" TListBox.$m"; done
[ "${TListBox_class_method_owner[HandleEvent]-}" = TListViewer ] || miss+=' TListBox.HandleEvent(TListViewer)'
for v in FV_BF_NORMAL FV_BF_DEFAULT FV_BF_LEFTJUST FV_BF_BROADCAST FV_BF_GRABFOCUS FV_DP_BLUEDIALOG FV_DP_CYANDIALOG FV_DP_GRAYDIALOG; do
    [[ ${!v@a} == *r* ]] || miss+=" $v(readonly)"
done
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

kt_test_start "every built-in virtual is in fv.views' elision table (a body of this unit); the tables' rows"
bad=''
for c in $CLASSES; do
    declare -n __o=${c}_class_method_owner
    for m in "${!__o[@]}"; do
        [ "${__o[$m]}" = "$c" ] || continue
        # (the thin aliases SelectAll / NewList call the plain functions: no elision entry)
        case $m in Create|Done|SelectAll|NewList) continue ;; esac
        b=${__FV_VW_IMPL[$c.$m]-}
        [[ $b == fv.dialogs._* ]] && declare -F "$b" >/dev/null || bad+=" $c.$m"
    done
    unset -n __o
done
t="${__FV_VW_FUNC[GetText]-}${__FV_VW_FUNC[Mark]-}${__FV_VW_FUNC[DataSize]-}|${__FV_VW_BCAST[fv.dialogs._btnEvent]-}|${__FV_VW_BCAST[fv.dialogs._lblEvent]-}|${__FV_VW_HKS[fv.dialogs._btnEvent]-}${__FV_VW_HKS[fv.dialogs._lblEvent]-}${__FV_VW_HKS[fv.dialogs._clEvent]-}|${__FV_VW_HKE[fv.dialogs._clEvent]-}|${__FV_VW_BCAST[fv.dialogs._ilEvent]+set}"
if [[ -z $bad && $t == '111|cmDefault cmGrabDefault cmReleaseDefault cmCommandSetChanged|cmReceivedFocus cmReleasedFocus|_data[Title]_data[Text]_items[@]|fv.dialogs._clOn|set' ]]; then kt_test_pass ok
else kt_test_fail "missing:$bad tables [$t]"; fi

expect_clean() {
    local out rc err
    kt_test_start "$1"
    out="$(bash -c "set -eu
$2
printf OK" 2>"$TMP/setu.err")"; rc=$?
    err="$(<"$TMP/setu.err")"
    if [[ $rc -eq 0 && $out == OK && -z $err ]]; then kt_test_pass "clean under set -eu"; else kt_test_fail "rc=$rc out='$out' stderr='$err'"; fi
}

expect_clean "the unit loads under set -eu, with its dependencies" \
    "source '$UNIT'; [[ -n \${__KK_UNITS[fv.views]-} && -n \${__KK_UNITS[fv.dialogs]-} ]]; declare -F TDialog.new >/dev/null"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.dialogs by name under set -eu" "source '$KBOOL'; kk.uses fv.dialogs; declare -F fv.dialogs.getData >/dev/null"

MAIN="
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new app 0 0 80 24
TView.new bg 0 0 80 24
fv.views.insert app bg
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app \"\$FV_SF_FOCUSED\" 1
TDialog.new dlg 10 4 70 18 Find
TStaticText.new st 2 1 50 2 \$'\\x03Options'
TParamText.new pt 2 2 50 3 '%s' 1
TLabel.new lb 2 3 20 4 '~T~ext' cb
TCheckBoxes.new cb 2 4 30 6 '~A~lpha' '~B~eta'
TRadioButtons.new rb 32 4 50 6 '~N~orth' '~S~outh'
TButton.new ok 2 10 12 12 'O~K~' cmOK \"\$FV_BF_DEFAULT\"
TButton.new cn 14 10 26 12 Cancel cmCancel
TInputLine.new il 2 7 30 8 20
TListBox.new lbx 32 7 50 9 1
L=(one two three); fv.dialogs.newList lbx L
for v in st pt lb cb rb ok cn il lbx; do fv.views.insert dlg \$v; done
fv.views.select cb
q=(kbTab kbDown kbEnter)
ge() {
    if (( \${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=\${q[0]}; q=(\"\${q[@]:1}\")
}
__FV_VW_GETEVENT=ge
fv.views.execView app dlg
[[ \$RESULT == cmOK && \${rb_data[Value]} == 1 ]]
D=(x 3 1 hello 2); fv.dialogs.setData dlg D; D=(); fv.dialogs.getData dlg D
[[ \${D[*]} == 'x 3 1 hello 2' ]]
fv.dialogs.setText il 'ab жи'; fv.dialogs.getText il; [[ \$RESULT == 'ab жи' ]]; fv.dialogs.selectAll il 0
fv.dialogs.setTitle ok '~Y~es'; fv.dialogs.setLabel lb '~L~'; fv.dialogs.setItems cb a b
fv.dialogs.setButtonState cb 1 0; fv.dialogs.makeDefault cn 1
if fv.dialogs.setTitle cb x; then exit 9; fi
fv.dialogs.getData nosuch D || :
fv.views.insert app dlg; fv.views.drawView app
dlg.delete; app.delete
[[ -z \${__FV_DG_KIND[ok]+x} && -z \${cb_items+x} && -z \${il_cl+x} && -z \${__FV_DG_KIND[lbx]+x} ]]
"
expect_clean "the main path under set -eu (every widget, drawn, run to the default button, data, setters, refusals, destructors)" "source '$UNIT'
$MAIN"

expect_clean "kk.unit --forget fv.dialogs + re-source under set -e: live widgets keep their state and the table entries" "
source '$UNIT'
TCheckBoxes.new cb 0 0 20 2 a b
kk.unit --forget fv.dialogs
source '$UNIT'
[[ \${cb_items[1]} == b && \${__FV_DG_KIND[cb]} == cl && \${__FV_VW_IMPL[TCheckBoxes.Draw]} == fv.dialogs._cbDraw ]]
fv.dialogs.setItems cb x y z
cb.delete
TButton.new b2 0 0 9 2 X cmX
b2.delete"

expect_clean "kk.unit --forget fv.views + re-source: fv.views merges its tables, fv.dialogs' entries stay; a dialog runs" "
source '$UNIT'
kk.unit --forget fv.views
source '$FVG_TESTS_DIR/../../fv.views/fv.views.sh'
[[ \${__FV_VW_IMPL[TButton.Draw]-} == fv.dialogs._btnDraw && \${__FV_VW_HKS[fv.dialogs._btnEvent]-} == '_data[Title]' && -n \${__FV_VW_BCAST[fv.dialogs._btnEvent]-} ]]
$MAIN"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
TButton.new b 0 0 9 2 X cmX
if fv.dialogs.setItems b x; then echo got; else echo none; fi
fv.dialogs.makeDefault b 7 || echo rc\$?
fv.dialogs.getData nosuch A || echo rc\$?
TButton.new bad 0 0 9 2 X 2>/dev/null || echo rc\$?
TCheckBoxes.new b 0 0 1 1 2>/dev/null || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nrc2\nrc2\nrc1\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout, also inside \$( ) (refusals and Error lines go to stderr)"
out="$(bash -c "
source '$UNIT'
x=\$( $MAIN )
y=\$( TButton.new bad 0 0 9 1 'x' 2>/dev/null; fv.dialogs.setTitle nosuch x; : )
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
if [[ $out == '[][]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (__FV_DG_*, the classes' tables, fv.dialogs.* / class functions)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
kk.uses kklass_pascal fv.views
exec {FVO}>/dev/null
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
$MAIN
unset q D v L
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
cl='TDialog|TButton|TStaticText|TParamText|TLabel|TCluster|TCheckBoxes|TRadioButtons|TInputLine|TListBox'
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE "^(__FV_DG_[A-Z]+|($cl)_[A-Za-z_]+|RESULT|REPLY|KK_UNIT_DIR|METHOD_BODY|METHOD_WRAPPER|__KK_SITE_[A-Z0-9]+|__kk_ft|FVO|__FV_(VW|VS|VI|DR|KB|MS|UN)_[A-Za-z0-9_]+|FV_[A-Z0-9_]+)\$" | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE "^((fv\\.dialogs|$cl)\\..*|__kk[cm]\\.($cl)(\\..*)?|ge)\$" | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi
