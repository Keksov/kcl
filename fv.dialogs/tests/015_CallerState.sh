#!/usr/bin/env bash
# 015_CallerState.sh - the caller's shell state neither changes what the
# unit's calls do nor is changed by them: one scripted dialog scene (two
# buttons whose names differ only in case, Ok and ok; a Cyrillic label, a
# wide static text, check boxes and radio buttons; the first draw (cells and
# patterns made under the setup), keys through the dialog's dispatch (Tab,
# Space, a radio move, Alt + a hot letter, a Cyrillic letter through its
# base key, a plain letter in post-process), a click on a check box with
# the tracking loop on a scripted source, getData / setData, the setters,
# refusals, rows read back) runs in a child shell under each setup -
# nocasematch, failglob, nullglob, noglob, extglob on and off,
# globasciiranges off, odd IFS values (digits, '-', letters, empty),
# set -eu with pipefail, a C locale, all at once - and must give the
# reference output; the setup's options, IFS and locale are the same after
# the scene. Classes and views are made before the setup (kklass's `.new`
# is not this unit's: kklass finding K-3), the calls run after it. An IFS
# holding \x01 is not among the setups (unsupported in fv.views /
# fv.dialogs, an open item): fv.views' tree and painter code (P2) misreads
# such an IFS in [[ ]] and array expansions (an insert already fails) and
# bash garbles "${@:N}" under it; fv.dialogs' own code has no "${@:N}" /
# "${*:N}" slice, but fv.views._virt, which every virtual call goes
# through, keeps one.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "015: the caller's shell state"

UNIT="$FVG_TESTS_DIR/../fv.dialogs.sh"
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
MAKE='
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=$FVO FV_SCREEN_W=60 FV_SCREEN_H=20; fv.video.initScreen
TGroup.new app 0 0 60 20
TView.new bg 0 0 60 20
TDialog.new dlg 2 2 58 18 Dlg
TStaticText.new st 2 1 30 2 "文件 text"
TLabel.new lb 2 2 20 3 "~Т~екст" cb
TCheckBoxes.new cb 2 3 26 5 "~A~lpha" "~B~eta"
TRadioButtons.new rb 28 3 50 5 "~N~orth" "~S~outh"
TButton.new Ok 2 10 12 12 "~O~k" cmOk2 0
TButton.new ok 14 10 24 12 "O~K~" cmOK 1
ge() {
    local s
    if (( ${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    if (( ! ${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    s=${q[0]}
    q=("${q[@]:1}")
    fv.drivers.clearEvent
    FV_EV_WHAT=${s%%:*} s=${s#*:}
    FV_EV_MOUSE_X=${s%%:*} FV_EV_MOUSE_Y=${s#*:}
}
cut8() { local LC_ALL=C.UTF-8; fv.video.getRow "$1"; r+="${RESULT:$2:$3}|${REPLY:$2:$3}$4"; }
key8() { fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=${3-}; fv.views._virt dlg HandleEvent; r+="$1>${__FV_DR_PEND[3]-none}:${dlg_data[Current]},"; }
'
SCENE='
r=""
for v in bg; do fv.views.insert app "$v"; done
for v in st lb cb rb Ok ok; do fv.views.insert dlg "$v"; done
fv.views.select cb
fv.views.insert app dlg
app_data[State]=$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app "$FV_SF_FOCUSED" 1
fv.views.drawView app
cut8 3 2 30 ,
cut8 4 2 22 ,
cut8 5 2 50 ,
cut8 12 2 24 ";"
key8 kbChar " "; key8 kbTab; key8 kbDown; key8 kbAltA a; key8 kbAltO o; key8 kbAltK k
key8 kbAltN т n; key8 kbChar s; key8 kbAltT е t
r+="v=${cb_data[Value]}/${rb_data[Value]};"
q=(evMouseUp:5:6)
__FV_VW_GETEVENT=ge
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=5 FV_EV_MOUSE_Y=6 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; r+="click>${cb_data[Sel]}/${cb_data[Value]}:$FV_EV_WHAT;"
D=(); fv.dialogs.getData dlg D; r+="get=${D[0]},${D[1]};"
D=(2 1); fv.dialogs.setData dlg D; r+="set=${cb_data[Value]}/${rb_data[Value]}/${rb_data[Sel]};"
fv.dialogs.setTitle Ok "~Q~uit"; fv.dialogs.setItems rb "~E~ast" "~W~est"; fv.dialogs.setLabel lb "~L~abel"
key8 kbAltQ q; key8 kbAltW w; key8 kbAltL l
fv.dialogs.setTitle cb x || r+="$?,"
fv.dialogs.getData dlg RESULT || r+="$?,"
fv.dialogs.setButtonState cb x 1 || r+="$?;"
cut8 4 2 22 ,
cut8 5 2 50 ,
cut8 12 2 24 ""
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
kt_test_start "reference run: the scene as expected (logged)"
kt_test_log "reference: $ref"
if [[ $ref == *'v='*'click>'*'get='*'set=2/1/1;'* && $ref != *rror* && $ref == *'kbAltO>cmOk2'* && $ref == *'kbAltK>cmOK'* && $ref == *',2,2,2;'* && $ref == *'kbAltN>none:cb,kbChar>none:rb,'* && $ref == *'click>1/2:evNothing;get=2,1;'* && $ref == *'kbAltQ>cmOk2:cb,kbAltW>none:rb,kbAltL>none:cb,'* ]]; then kt_test_pass "ok"
else kt_test_fail "got [$ref]"; fi

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
