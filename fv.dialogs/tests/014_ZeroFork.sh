#!/usr/bin/env bash
# 014_ZeroFork.sh - fv.dialogs never forks (PLAN.md rule 1):
#   * with PATH='' (no external command can run): every class made, the
#     dialog drawn (a wide static text, a Cyrillic label, clusters, buttons),
#     keys through the modal loop (Tab, Space, arrows, hot letters in Latin
#     and through a base key, Enter -> the default button), a click on a
#     button and on a check box with the tracking loops, getData / setData /
#     dataSize, the setters, newButton / newLabel, a TParamText, CalcBounds,
#     destruction: no "command not found";
#   * the static scan (fv.video's 006 scanner, through fv.views' test lib):
#     no $( ), backtick, process substitution, pipe, ( ) subshell, & or
#     coproc on any code line of fv.dialogs.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "014: no forks"

kt_test_start "PATH='': the unit's whole path works, no external command is looked for"
out=$("$BASH" -c "
source '$FVG_TESTS_DIR/../fv.dialogs.sh'
PATH=''
r=''
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new app 0 0 80 24; TGroup.new desk 0 0 80 24; TView.new bg 0 0 80 24
fv.views.insert desk bg; fv.views.insert app desk
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app \"\$FV_SF_FOCUSED\" 1
TDialog.new dlg 10 4 70 18 Find
TStaticText.new st 2 1 40 3 '文件 wide text that wraps around'
TLabel.new lb 2 3 20 4 '~Т~екст' cb
TCheckBoxes.new cb 2 4 30 6 '~A~lpha' '~B~eta'
TRadioButtons.new rb 32 4 50 6 '~N~orth' '~S~outh'
TParamText.new pt 2 7 40 8 '%s=%d' 2
TButton.new ok 2 10 12 12 'O~K~' cmOK 1
TButton.new cn 14 10 26 12 Cancel cmCancel
for v in st lb cb rb pt ok cn; do fv.views.insert dlg \$v; done
fv.views.select cb
q=('key:kbTab' 'char: ' 'key:kbDown' 'alt:a:' 'alt:s:' 'alt:n:т' 'key:kbShiftTab' 'key:kbEnter')
ge() {
    local s
    if (( \${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    s=\${q[0]}; q=(\"\${q[@]:1}\")
    fv.drivers.clearEvent
    case \${s%%:*} in
        key) FV_EV_WHAT=evKeyDown FV_EV_KEY=\${s#*:} ;;
        char) FV_EV_WHAT=evKeyDown FV_EV_KEY=kbChar FV_EV_CHAR=\${s#*:} ;;
        alt) s=\${s#*:}; FV_EV_WHAT=evKeyDown FV_EV_CHAR=\${s%%:*} FV_EV_BASE=\${s#*:}; FV_EV_KEY=kbAltX ;;
        up) FV_EV_WHAT=evMouseUp FV_EV_MOUSE_X=\${s#*:} FV_EV_MOUSE_Y=14 ;;
        up2) FV_EV_WHAT=evMouseUp FV_EV_MOUSE_X=\${s#*:} FV_EV_MOUSE_Y=9 ;;
    esac
}
__FV_VW_GETEVENT=ge
fv.views.execView desk dlg; r+=\"\$RESULT:\${cb_data[Value]}:\${rb_data[Value]}|\"
fv.views.insert desk dlg; fv.views.select dlg
q=('up:16')
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=16 FV_EV_MOUSE_Y=14 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; r+=\"\${__FV_DR_PEND[3]-none}|\"; __FV_DR_PEND=()
q=('up2:14')
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=14 FV_EV_MOUSE_Y=9 FV_EV_MOUSE_BUTTONS=1
fv.views._virt app HandleEvent; r+=\"\${cb_data[Value]}|\"
D=(x 7 1 0); fv.dialogs.setData dlg D; D=(); fv.dialogs.getData dlg D; fv.dialogs.dataSize dlg; r+=\"\${D[*]}:\$RESULT|\"
fv.dialogs.setTitle ok '~Y~es'; fv.dialogs.setLabel lb '~L~abel'; fv.dialogs.setItems cb '~X~' '~Y~' '~Z~'
fv.dialogs.setButtonState cb 2 0; fv.dialogs.makeDefault cn 1
fv.dialogs.newButton dlg 30 10 40 2 '~H~elp' cmHelp 5 0; r+=\"\$RESULT|\"
fv.dialogs.newLabel dlg 30 8 '~Q~' cn; r+=\"\$RESULT|\"
fv.views.changeBounds desk 0 0 100 30; fv.views.getBounds dlg; r+=\"\$RESULT|\"
fv.views.drawView app
dlg.delete; app.delete
printf '%s' \"\$r\"" 2>&1)
want='cmOK:1:0|cmOK|3|0 7 1 0:4|dlg__fvbtn1|dlg__fvlbl1|20 6 80 20|'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "fv.dialogs.sh: no fork construct on any code line"
bad='' n=0 fn=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$FVG_TESTS_DIR/../fv.dialogs.sh"
if [[ -z $bad ]] && (( n > 1000 )); then kt_test_pass "$n lines clean"; else kt_test_fail "${bad:-only $n lines}"; fi
