#!/usr/bin/env bash
# 008_CallerState.sh - the caller's shell state neither changes what the
# unit's calls do nor is changed by them: one scripted scene (two status
# lines whose names differ only in case, St and st, one with a Hint
# override and `~` marks, one with a wide label; key names that differ only
# in case; the first draw (the cell patterns are made under the setup),
# keys through the application's dispatch, a press with the tracking loop
# on a scripted event source, Update to another def, cmCommandSetChanged,
# addItem / addDef, refusals, the rows read back) runs in a child shell
# under each setup - nocasematch, failglob, nullglob, noglob, extglob on
# and off, globasciiranges off, odd IFS values (digits, '-', letters,
# empty), set -eu with pipefail, a C locale, all at once - and must give
# the reference output; the setup's options, IFS and locale are the same
# after the scene as before. The views and classes are made before the
# setup (kklass's `.new` and `build` are not this unit's: under an IFS of
# letters `.new` crashes bash, kklass finding K-3), the calls run after it.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: the caller's shell state"

UNIT="$FVM_TESTS_DIR/../fv.menus.sh"
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
MAKE='
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=$FVO FV_SCREEN_W=60 FV_SCREEN_H=20; fv.video.initScreen
class TSH : TStatusLine
    public
        override func Hint
end
TSH.Hint() { if [ "$1" = 150 ]; then RESULT="Hilfe Ä"; else RESULT=""; fi; }
build TSH
TGroup.new app 0 0 60 20
TGroup.new desk 0 0 60 18
TView.new lf 0 0 60 18
TSH.new St 0 18 60 19 def 0 99 "~Alt+X~ Exit" kbAltX cmQuit "~F2~ Up" kbF2 cmUp def 100 199 "~F1~ Hilfe" kbF1 cmHelp
TStatusLine.new st 0 19 60 20 "~F3~ 帮助" kbF3 cmLow "Lower" kbf3 cmLower "" kbF4 cmFour
ge() {
    local s
    if (( ! ${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    s=${q[0]}
    q=("${q[@]:1}")
    FV_EV_WHAT=${s%%:*} s=${s#*:}
    FV_EV_MOUSE_X=${s%%:*} FV_EV_MOUSE_Y=${s#*:}
}
cut8() { local LC_ALL=C.UTF-8; fv.video.getRow "$1"; r+="${RESULT:$2:$3}|${REPLY:$2:$3}$4"; }
key8() { fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=$1; fv.views._virt app HandleEvent; r+="$1>${__FV_DR_PEND[3]-none},"; }
'
SCENE='
r=""
lf_data[Options]=$FV_OF_SELECTABLE
fv.views.insert desk lf
fv.views.insert app desk; fv.views.insert app St; fv.views.insert app st
app_data[State]=$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app "$FV_SF_FOCUSED" 1
fv.views.drawView app
cut8 18 0 22 ,
cut8 19 0 18 ";"
key8 kbF2; key8 kbF3; key8 kbf3; key8 KBF2; key8 kbF4; key8 kbAltX
r+=";"
q=(evMouseMove:9:19 evMouseUp:9:19)
__FV_VW_GETEVENT=ge
fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=2 FV_EV_MOUSE_Y=19 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; r+="press>${__FV_DR_PEND[3]-none}:$FV_EV_WHAT:$FV_EV_INFO;"
lf_data[HelpCtx]=150
fv.menus.update St; fv.menus.update st
r+="cur=${__FV_MN_CUR[St]}${__FV_MN_CUR[st]};"
fv.views.disableCommands cmLow; fv.views.message app evBroadcast cmCommandSetChanged || :
fv.menus.addItem St "z" "" cmZ; fv.menus.addDef st 5 6
fv.menus.addItem St x F2 cmA || r+="$?,"
fv.menus.addDef st 1 x || r+="$?,"
fv.menus.update nosuch || r+="$?;"
cut8 18 0 28 ,
cut8 19 0 18 ""
fv.views.enableCommands cmLow
printf "%s" "$r"
'
run() {   # SETUP -> OUT = before-state # scene output # after-state
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
source '$UNIT'
$MAKE
$1
$STATE
printf '#'
$SCENE
printf '#'
$STATE" 2>&1)
}

run ''
ref=${OUT#*#} ref=${ref%#*}
kt_test_start "reference run: the scene as expected"
# row 18 (St, def 0): ' Alt+X Exit ' ' F2 Up ' in 2 / 4; row 19 (st): ' F3 帮助 ' (1+2+1+4+1
# cells) ' Lower '; keys: kbF2 -> St's cmUp, kbF3 -> st's cmLow (st is in
# front: its pre-process turn comes first), kbf3 -> st's cmLower, KBF2 /
# kbAltX case-exact, kbF4 key-only; the press at 2 then 9 (Lower) -> cmLower;
# HelpCtx 150 -> St def 1 (its Hint shown), st keeps its implicit def;
# cmLow disabled -> st greyed (3); then addItem z to St's last def (shown),
# addDef on st (not shown), three refusals
want=' Alt+X Exit  F2 Up    |2444442222222442222222, F3 帮助  Lower     |244222222222222222;'
want+='kbF2>cmUp,kbF3>cmLow,kbf3>cmLower,KBF2>none,kbF4>cmFour,kbAltX>cmQuit,;press>cmLower:evNothing:st;cur=10;2,2,2;'
want+=' F1 Hilfe  z │ Hilfe Ä      |2442222222222222222222222222, F3 帮助  Lower     |333333333222222222'
if [[ $ref == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$ref] want [$want]"; fi

for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS='0123456789 '" "IFS='-'" "IFS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.'" 'IFS=' \
    'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='-0123456789Ww'; export LC_ALL=C"; do
    kt_test_start "same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    if [[ $got == "$ref" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs [$ref]; state before [$before] after [$after]"; fi
done

kt_test_log "008_CallerState.sh completed"
