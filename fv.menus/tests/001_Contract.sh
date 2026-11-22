#!/usr/bin/env bash
# 001_Contract.sh - the kcl-wide contract for fv.menus (kcl/README.md §1):
# source integrity; loads (with kklass_pascal and fv.views by name),
# re-loads and runs its main path under `set -eu` (a status line in an
# application-like tree: the constructor list, addDef / addItem, the draw,
# a key, a press, Update, cmCommandSetChanged, the destructor); `kk.unit
# --forget fv.menus` + a re-source keeps a live line (its arrays, its
# state, the elision entries); after `kk.unit --forget fv.views` + a
# re-source (fv.views merges its elision table, so TStatusLine's entries
# stay) a line still works and a new TStatusLine.new keeps the entries
# (it registers them again only when they are missing); a failing call returns to the caller from `if` /
# `||`; nothing on stdout, also inside $( ); using the unit leaves only its
# names behind (__FV_MN_*, TStatusLine's class tables, fv.menus.* /
# TStatusLine.* functions); the public API exists; TStatusLine's built-in
# virtuals are in fv.views' elision table.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVM_TESTS_DIR/.." && pwd)/fv.menus.sh"
KBOOL="$(cd "$FVM_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the public API is defined (plain functions, the class, its methods)"
miss=''
for f in addDef addItem update _register _parse _create _push _free _findItems _range _pats \
    _draw _paintSel _compose _grey _getPalette _hint _event _post _hit _track _update _changed; do
    declare -F "fv.menus.$f" >/dev/null || miss+=" fv.menus.$f"
done
declare -F TStatusLine.new >/dev/null || miss+=' TStatusLine.new'
for m in Draw HandleEvent GetPalette Hint Update AddDef AddItem; do [ "${TStatusLine_class_method_owner[$m]-}" = TStatusLine ] || miss+=" TStatusLine.$m"; done
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

kt_test_start "the menus' API (stage 3f): functions, classes, methods, elision and broadcast entries"
miss=''
for f in setHint menuBar newSubView _mregister _mparse _mlayout _mmaps _mvCreate _mvFree _barDraw _boxDraw _boxPaint     _mvGetPalette _mvGetHelpCtx _mvItemRect _barItemRect _boxItemRect _mvEvent _doSelect _mvUpdate _popEvent _mvExecute _pat1; do
    declare -F "fv.menus.$f" >/dev/null || miss+=" fv.menus.$f"
done
for c in TMenuView TMenuBar TMenuBox TMenuPopup; do declare -F "$c.new" >/dev/null || miss+=" $c.new"; done
for m in HandleEvent GetPalette GetHelpCtx Execute GetItemRect; do [ "${TMenuView_class_method_owner[$m]-}" = TMenuView ] || miss+=" TMenuView.$m"; done
for m in Draw GetItemRect; do [ "${TMenuBar_class_method_owner[$m]-}" = TMenuBar ] || miss+=" TMenuBar.$m"; [ "${TMenuBox_class_method_owner[$m]-}" = TMenuBox ] || miss+=" TMenuBox.$m"; done
[ "${TMenuPopup_class_method_owner[HandleEvent]-}" = TMenuPopup ] || miss+=' TMenuPopup.HandleEvent'
got="${__FV_VW_IMPL[TMenuView.Execute]-},${__FV_VW_IMPL[TMenuBar.Draw]-},${__FV_VW_IMPL[TMenuBox.Draw]-},${__FV_VW_IMPL[TMenuPopup.HandleEvent]-},${__FV_VW_BCAST[fv.menus._mvEvent]-}"
[ "$got" = "fv.menus._mvExecute,fv.menus._barDraw,fv.menus._boxDraw,fv.menus._popEvent,cmCommandSetChanged" ] || miss+=" entries[$got]"
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

kt_test_start "TStatusLine's built-in virtuals are in fv.views' elision table; Hint is a func there"
got=''
for m in Draw HandleEvent GetPalette Hint Update; do got+="${__FV_VW_IMPL[TStatusLine.$m]-none},"; done
got+="${__FV_VW_FUNC[Hint]-}"
if [[ $got == "fv.menus._draw,fv.menus._event,fv.menus._getPalette,fv.menus._hint,fv.menus._update,1" ]]; then kt_test_pass "ok"; else kt_test_fail "$got"; fi

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
    "source '$UNIT'; [[ -n \${__KK_UNITS[fv.views]-} && -n \${__KK_UNITS[fv.menus]-} ]]; declare -F TStatusLine.new >/dev/null"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.menus by name under set -eu" "source '$KBOOL'; kk.uses fv.menus; declare -F fv.menus.addItem >/dev/null"

MAIN="
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new app 0 0 80 24
TGroup.new desk 0 0 80 23
TView.new lf 0 0 80 23
lf_data[Options]=\$FV_OF_SELECTABLE
fv.views.insert desk lf
TStatusLine.new st 0 23 80 24 def 0 99 '~Alt+X~ Exit' kbAltX cmQuit def 100 199 '~F1~ Help' kbF1 cmHelp
fv.menus.addItem st '' kbF6 cmNext
st.AddDef 200 299; st.AddItem '~F2~ Two' kbF2 cmTwo
fv.views.insert app desk; fv.views.insert app st
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app \"\$FV_SF_FOCUSED\" 1
fv.views.drawView app
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltX; fv.views._virt app HandleEvent
[[ \$FV_EV_WHAT == evNothing && \${__FV_DR_PEND[3]} == cmQuit ]]
__FV_DR_PEND=()
q=(evMouseUp)
ge() { if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi; FV_EV_WHAT=\${q[0]} FV_EV_MOUSE_X=2 FV_EV_MOUSE_Y=23; q=(\"\${q[@]:1}\"); }
__FV_VW_GETEVENT=ge
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=2 FV_EV_MOUSE_Y=23 FV_EV_MOUSE_BUTTONS=1; fv.views._virt app HandleEvent
[[ \${__FV_DR_PEND[3]} == cmQuit ]]
lf_data[HelpCtx]=150; fv.menus.update st; [[ \${__FV_MN_CUR[st]} == 1 ]]
fv.views.disableCommands cmHelp; fv.views.message app evBroadcast cmCommandSetChanged || :
if fv.menus.addItem st x F2 cmX; then exit 9; fi
fv.menus.addDef nosuch 1 2 || :
app.delete
[[ -z \${__FV_MN_CUR[st]+x} ]]
"
expect_clean "the main path under set -eu (the list, addDef / addItem, draw, a key, a press, Update, the broadcast, refusals in if / ||, the destructor)" "source '$UNIT'
$MAIN"

expect_clean "kk.unit --forget fv.menus + re-source under set -e: a live line keeps its arrays, state and elision entries" "
source '$UNIT'
TStatusLine.new st 0 0 80 1 'a' kbF2 cmA
kk.unit --forget fv.menus
source '$UNIT'
[[ \${st_sitext[0]} == a && \${__FV_MN_CUR[st]} == 0 && \${__FV_VW_IMPL[TStatusLine.Draw]} == fv.menus._draw ]]
fv.menus.addItem st b kbF3 cmB
[[ \${st_skey[0:kbF3]} == 1 ]]
st.delete
TStatusLine.new s2 0 0 80 1 'c' kbF2 cmC
s2.delete"

expect_clean "kk.unit --forget fv.views + re-source: fv.views merges its elision table, TStatusLine's entries stay; the line works; a new .new keeps them" "
source '$UNIT'
TStatusLine.new st 0 0 80 1 'a' kbF2 cmA
kk.unit --forget fv.views
source '$FVM_TESTS_DIR/../../fv.views/fv.views.sh'
[[ \${__FV_VW_IMPL[TStatusLine.Draw]-} == fv.menus._draw ]]
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=kbF2; fv.views._virt st HandleEvent
[[ \${__FV_DR_PEND[3]} == cmA ]]
TStatusLine.new s2 0 0 80 1 'c' kbF2 cmC
[[ \${__FV_VW_IMPL[TStatusLine.Draw]} == fv.menus._draw ]]
s2.delete; st.delete"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
TStatusLine.new st 0 0 9 1
if fv.menus.addItem st x F2 cmA; then echo got; else echo none; fi
fv.menus.addDef st x 1 || echo rc\$?
fv.menus.update nosuch || echo rc\$?
TStatusLine.new bad 0 0 9 1 'x' kbF2 2>/dev/null || echo rc\$?
TStatusLine.new st 0 0 1 1 2>/dev/null || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nrc2\nrc2\nrc1\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout, also inside \$( ) (refusals and Error lines go to stderr)"
out="$(bash -c "
source '$UNIT'
x=\$( $MAIN )
y=\$( TStatusLine.new bad 0 0 9 1 'x' F2 cmA 2>/dev/null; fv.menus.update nosuch; : )
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
if [[ $out == '[][]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (__FV_MN_*, TStatusLine's class tables, fv.menus.* / TStatusLine.* functions)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
kk.uses kklass_pascal fv.views
exec {FVO}>/dev/null
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
$MAIN
unset q
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
# (MAIN's own names: FVO, q, ge; fv.views' / fv.video's / fv.drivers' state
# the main path touches: __FV_VW_*, __FV_VS_*, __FV_DR_*, FV_*)
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(__FV_MN_[A-Z]+|(TStatusLine|TMenuView|TMenuBar|TMenuBox|TMenuPopup)_[A-Za-z_]+|RESULT|REPLY|KK_UNIT_DIR|METHOD_BODY|METHOD_WRAPPER|__KK_SITE_[A-Z0-9]+|__kk_ft|FVO|__FV_(VW|VS|VI|DR|KB|MS|UN)_[A-Za-z0-9_]+|FV_[A-Z0-9_]+)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^((fv\.menus|TStatusLine|TMenuView|TMenuBar|TMenuBox|TMenuPopup)\..*|__kk[cm]\.(TStatusLine|TMenuView|TMenuBar|TMenuBox|TMenuPopup)(\..*)?|ge)$' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_log "001_Contract.sh completed"
