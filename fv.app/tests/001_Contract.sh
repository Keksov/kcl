#!/usr/bin/env bash
# 001_Contract.sh - the kcl-wide contract for fv.app (kcl/README.md §1):
# source integrity; the public API, the classes and their built-in virtuals
# in fv.views' elision tables (the handlers in QGRP); the
# default app palette string is fv.views' and 127 symbols long; loads (with
# kklass_pascal, fv.views, fv.menus, fv.drivers by name), re-loads and runs
# its main path under `set -eu` (a headless application: Init, windows, Run
# with keys from a file through fv.drivers until Alt+X, tile / cascade,
# setAppPalette, a resize, Done); `kk.unit --forget fv.app` + a re-source
# keeps a live application working (its hooks, the elision entries); a
# failing call returns to the caller from `if` / `||`; nothing on stdout,
# also inside $( ); using the unit leaves only its names behind.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fva_testlib.sh"
fva_init "$(basename "$0" .sh)" "$@"

UNIT="$(cd "$FVA_TESTS_DIR/.." && pwd)/fv.app.sh"
KBOOL="$(cd "$FVA_TESTS_DIR/../../.." && pwd)/kbool.sh"
TMP=$FVW_TMP

kt_test_section "001: the kcl contract"

kt_test_start "the unit source parses"
if err="$(bash -n "$UNIT" 2>&1)"; then kt_test_pass "bash -n clean"; else kt_test_fail "bash -n: $err"; fi

kt_test_start "the public API is defined (plain functions, the classes, their methods)"
miss=''
for f in tile cascade setAppPalette _register _getEvent _putEvent _run _progCreate _progDone _appDone _release \
    _bgDraw _bgGetPalette _deskEvent _deskInitBackground _deskTileError _progEvent _progGetPalette _progGetEvent \
    _progPutEvent _progIdle _progInitScreen _progInitStatusLine _progInitMenuBar _progInitDesktop _appEvent \
    _appGetTileRect _resize _free _layout _tile _cascade; do
    declare -F "fv.app.$f" >/dev/null || miss+=" fv.app.$f"
done
for c in TBackground TDesktop TProgram TApplication; do declare -F "$c.new" >/dev/null || miss+=" $c.new"; done
for m in Draw GetPalette; do [ "${TBackground_class_method_owner[$m]-}" = TBackground ] || miss+=" TBackground.$m"; done
for m in HandleEvent InitBackground TileError Tile Cascade; do [ "${TDesktop_class_method_owner[$m]-}" = TDesktop ] || miss+=" TDesktop.$m"; done
for m in HandleEvent GetPalette Run GetEvent PutEvent Idle InitScreen InitStatusLine InitMenuBar InitDesktop; do
    [ "${TProgram_class_method_owner[$m]-}" = TProgram ] || miss+=" TProgram.$m"
done
for m in HandleEvent GetTileRect Tile Cascade; do [ "${TApplication_class_method_owner[$m]-}" = TApplication ] || miss+=" TApplication.$m"; done
if [[ -z $miss ]]; then kt_test_pass "ok"; else kt_test_fail "missing:$miss"; fi

kt_test_start "the built-in virtuals are in fv.views' elision table; the three handlers are in QGRP"
got=''
for k in TBackground.Draw TBackground.GetPalette TDesktop.HandleEvent TDesktop.InitBackground TDesktop.TileError \
    TProgram.HandleEvent TProgram.GetPalette TProgram.Run TProgram.GetEvent TProgram.PutEvent TProgram.Idle \
    TProgram.InitScreen TProgram.InitStatusLine TProgram.InitMenuBar TProgram.InitDesktop TApplication.HandleEvent \
    TApplication.GetTileRect; do
    [[ -n ${__FV_VW_IMPL[$k]-} ]] && declare -F "${__FV_VW_IMPL[$k]}" >/dev/null || got+=" $k"
done
got+="|${__FV_VW_FUNC[GetEvent]-}|${__FV_VW_QGRP[fv.app._deskEvent]-}${__FV_VW_QGRP[fv.app._progEvent]-}${__FV_VW_QGRP[fv.app._appEvent]-}"
if [[ $got == "|1|111" ]]; then kt_test_pass "ok"; else kt_test_fail "[$got]"; fi

kt_test_start "the default app palette is fv.views' CAppColor string (127 symbols, no 0, no V)"
p=$__FV_AP_DEFPAL
if [[ $p == "$__FV_VW_APAL" && ${#p} == 127 && $p != *0* && $p != *V* ]]; then kt_test_pass "ok"; else kt_test_fail "[$p] vs [$__FV_VW_APAL]"; fi

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
    "source '$UNIT'; [[ -n \${__KK_UNITS[fv.views]-} && -n \${__KK_UNITS[fv.menus]-} && -n \${__KK_UNITS[fv.app]-} ]]; declare -F TApplication.new >/dev/null"
expect_clean "loading it twice under set -eu is a no-op" "source '$UNIT'; source '$UNIT'"
expect_clean "kk.uses fv.app by name under set -eu" "source '$KBOOL'; kk.uses fv.app; declare -F fv.app.tile >/dev/null"

MAIN="
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_SCREEN_W=80 FV_SCREEN_H=24 FV_APP_HEADLESS=1
printf '\\033x' > '$TMP/keys'
exec {FVK}<'$TMP/keys'; FV_KEY_FD=\$FVK
TApplication.new app
[[ \$FV_APP == app && \$FV_DESKTOP == app__fvdesktop && \$FV_STATUSLINE == app__fvstatus && -z \$FV_MENUBAR ]]
TWindow.new w1 2 1 40 20 One 1; TWindow.new w2 30 5 70 22 Two 2
w1_data[Options]=\$(( w1_data[Options] | FV_OF_TILEABLE )); w2_data[Options]=\$(( w2_data[Options] | FV_OF_TILEABLE ))
fv.views.insert \"\$FV_DESKTOP\" w1; fv.views.insert \"\$FV_DESKTOP\" w2
app.Run
[[ \$__FV_VW_EOF == 0 && -z \${app_data[EndState]} ]]
fv.app.tile app; fv.app.cascade app; app__fvdesktop.Tile 0 0 80 23
fv.app.setAppPalette 2 1 2 1
fv.app._resize app 100 30
[[ \${app__fvdesktop_data[SizeX]} == 100 ]]
if fv.app.tile nosuch; then exit 9; fi
fv.app.setAppPalette 0 1 1 || :
app.delete
[[ -z \$FV_APP && \$__FV_VW_GETEVENT == fv.drivers.getEvent && -z \${__FV_VW_LIVE[w1]-} ]]
exec {FVK}<&-
"
expect_clean "the main path under set -eu (Init, windows, Run with keys from a file until Alt+X, tile / cascade, setAppPalette, a resize, refusals in if / ||, Done)" "source '$UNIT'
$MAIN"

expect_clean "kk.unit --forget fv.app + re-source under set -e: a live application keeps working (hooks, elision entries), Done puts the hooks back" "
source '$UNIT'
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_APP_HEADLESS=1
TApplication.new app
kk.unit --forget fv.app
source '$UNIT'
[[ \${__FV_VW_IMPL[TProgram.Run]} == fv.app._run && \$__FV_VW_GETEVENT == fv.app._getEvent && \$FV_APP == app ]]
__FV_DR_PEND=(); FV_EV_WHAT=evCommand FV_EV_COMMAND=cmQuit; fv.drivers.putEvent
exec {FVK}</dev/null; FV_KEY_FD=\$FVK
app.Run; [[ \$__FV_VW_EOF == 0 ]]
app.delete
[[ \$__FV_VW_GETEVENT == fv.drivers.getEvent ]]"

expect_clean "kk.unit --forget fv.views + re-source: the merged tables keep fv.app's entries (IMPL, QGRP)" "
source '$UNIT'
kk.unit --forget fv.views
source '$FVA_TESTS_DIR/../../fv.views/fv.views.sh'
[[ \${__FV_VW_IMPL[TDesktop.HandleEvent]-} == fv.app._deskEvent && \${__FV_VW_QGRP[fv.app._appEvent]-} == 1 ]]"

kt_test_start "a failing call returns to the caller under set -e"
out="$(bash -c "set -e
source '$UNIT'
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_APP_HEADLESS=1
TApplication.new app
if fv.app.tile app 1 2; then echo got; else echo none; fi
fv.app.cascade nosuch || echo rc\$?
fv.app.setAppPalette 128 1 1 || echo rc\$?
TApplication.new app2 2>/dev/null || echo rc\$?
TApplication.new app 2>/dev/null || echo rc\$?
x=\$(app.Run) || echo rc\$?
echo end" 2>&1)"
if [[ $out == $'none\nrc2\nrc2\nrc1\nrc1\nrc2\nend' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "nothing on stdout, also inside \$( ) (refusals and Error lines go to stderr)"
out="$(bash -c "
source '$UNIT'
x=\$( $MAIN )
y=\$( exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_APP_HEADLESS=1; TApplication.new a; TApplication.new b 2>/dev/null; fv.app.tile nosuch; : )
printf '[%s][%s]' \"\$x\" \"\$y\"" 2>/dev/null)"
if [[ $out == '[][]' ]]; then kt_test_pass "ok"; else kt_test_fail "out='$out'"; fi

kt_test_start "loading and using the unit leaves only its names behind (__FV_AP_*, FV_APP..., the classes' tables, fv.app.* / class functions)"
out="$(bash -c "
export LC_ALL=C.UTF-8
source '$KBOOL'
kk.uses kklass_pascal fv.views fv.menus
exec {FVO}>/dev/null
compgen -v | LC_ALL=C sort > '$TMP/v0'
compgen -A function | LC_ALL=C sort > '$TMP/f0'
source '$UNIT'
$MAIN
compgen -v | LC_ALL=C sort > '$TMP/v1'
compgen -A function | LC_ALL=C sort > '$TMP/f1'
" 2>&1)"
newv="$(comm -13 "$TMP/v0" "$TMP/v1" | grep -vE '^(__FV_AP_[A-Z]+|(TBackground|TDesktop|TProgram|TApplication|TWindow|TFrame|TStatusLine)_[A-Za-z_]+|(w1|w2|app|app__fv[a-z]+|app__fvdesktop__fvbg|w1__fvframe|w2__fvframe)_[A-Za-z_]+|RESULT|REPLY|KK_UNIT_DIR|METHOD_BODY|METHOD_WRAPPER|__KK_SITE_[A-Z0-9]+|__kk_ft|FVO|FVK|__FV_(VW|VS|VI|DR|KB|MS|UN|MN)_[A-Za-z0-9_]+|FV_[A-Z0-9_]+)$' | tr '\n' ' ')"
newf="$(comm -13 "$TMP/f0" "$TMP/f1" | grep -vE '^((fv\.app|TBackground|TDesktop|TProgram|TApplication)\..*|__kk[cm]\.(TBackground|TDesktop|TProgram|TApplication)(\..*)?)$' | tr '\n' ' ')"
if [[ -z $out && -z $newv && -z $newf ]]; then kt_test_pass "ok"; else kt_test_fail "stray vars: [$newv] functions: [$newf] output: [$out]"; fi

kt_test_log "001_Contract.sh completed"
