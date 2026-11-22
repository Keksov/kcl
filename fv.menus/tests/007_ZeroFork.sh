#!/usr/bin/env bash
# 007_ZeroFork.sh - fv.menus never forks (PLAN.md rule 1):
#   * with PATH='' (no external command can run): a status line made from
#     the constructor list, addDef / addItem, its draw with a Hint override
#     and a wide label, a key through the application's dispatch, a press
#     with the tracking loop on a scripted event source (also one ended by
#     the end of input), Update (no change, another def, through a modal
#     dialog), cmCommandSetChanged, the destructor and the re-creation guard
#     work and print no "command not found";
#   * the static scan (fv.video's 006 scanner, through fv.views' test lib):
#     no $( ), backtick, process substitution, pipe, ( ) subshell, & or
#     coproc on any code line of fv.menus.sh;
#   * (P3 3f) the menus' path with PATH='' too: a bar, Alt+F, a nested
#     drop, F3, a press + release, a popup, the hint table,
#     cmCommandSetChanged, the destructors.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: no forks"

kt_test_start "PATH='': the unit's whole path works, no external command is looked for"
out=$("$BASH" -c "
source '$FVM_TESTS_DIR/../fv.menus.sh'
class TZH : TStatusLine
    public
        override func Hint
end
TZH.Hint() { RESULT=\"hint \$1\"; }
build TZH
PATH=''
r=''
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new app 0 0 80 24; TGroup.new desk 0 0 80 23; TView.new lf 0 0 80 23
lf_data[Options]=\$FV_OF_SELECTABLE
fv.views.insert desk lf
TZH.new st 0 23 80 24 def 0 99 '~Alt+X~ Exit' kbAltX cmQuit '~F1~ 帮助' kbF1 cmHelp def 100 199 'b' kbF2 cmB; r+=\$?
fv.menus.addItem st '' kbF6 cmNext; st.AddDef 200 299; st.AddItem 'c' kbF3 cmC
fv.views.insert app desk; fv.views.insert app st
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app \"\$FV_SF_FOCUSED\" 1
fv.views.drawView app
fv.video.getRow 23; r+=\"|\${RESULT:0:24}\"
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbAltX; fv.views._virt app HandleEvent; r+=\"|\$FV_EV_WHAT:\${__FV_DR_PEND[3]}\"
__FV_DR_PEND=()
q=(evMouseMove:15 evMouseUp:15)
ge() {
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    if [[ \${q[0]} == upd:0 ]]; then fv.menus.update st; U=\${__FV_MN_CUR[st]}; fi
    FV_EV_WHAT=\${q[0]%%:*} FV_EV_MOUSE_X=\${q[0]#*:} FV_EV_MOUSE_Y=23
    q=(\"\${q[@]:1}\")
}
__FV_VW_GETEVENT=ge
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=2 FV_EV_MOUSE_Y=23 FV_EV_MOUSE_BUTTONS=1; fv.views._virt app HandleEvent
r+=\"|\${__FV_DR_PEND[3]}\"
q=()
fv.drivers.clearEvent; FV_EV_WHAT=evMouseDown FV_EV_MOUSE_X=2 FV_EV_MOUSE_Y=23 FV_EV_MOUSE_BUTTONS=1; fv.views._virt app HandleEvent
r+=\"|eof\$__FV_VW_EOF\"; __FV_VW_EOF=0
fv.menus.update st; lf_data[HelpCtx]=150; fv.menus.update st; r+=\"|\${__FV_MN_CUR[st]}\"
TWindow.new dlg 10 5 50 15 Dlg 0; dlg_data[HelpCtx]=250
q=(upd:0)
fv.views.execView desk dlg; r+=\"|\$RESULT:\$U\"; __FV_VW_EOF=0; fv.menus.update st
fv.views.disableCommands cmB; fv.views.message app evBroadcast cmCommandSetChanged || :
fv.video.getRow 23; r+=\"|\${REPLY:0:3}\"
TStatusLine.new st 0 0 1 1 2>/dev/null || r+=\"|guard\$?\"
st.delete; dlg.delete; app.delete
printf '%s' \"\$r\"" 2>&1)
want='0| Alt+X Exit  F1 帮助 │ hin|evNothing:cmQuit|cmHelp|eof1|1|cmCancel:2|333|guard1'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "PATH='': the menus' whole path (a bar, Alt+F, a nested drop, F3, a press + release, a popup, the hint table, cmCommandSetChanged, the destructors)"
out=$("$BASH" -c "
source '$FVM_TESTS_DIR/../fv.menus.sh'
exec {o}>/dev/null; FV_VIDEO_OUT_FD=\$o FV_SCREEN_W=60 FV_SCREEN_H=20; fv.video.initScreen
TGroup.new app 0 0 60 20; TGroup.new desk 0 1 60 19; TView.new lf 0 0 60 18
TMenuBar.new mb 0 0 60 1 sub '~F~ile' item '~O~pen' F3 kbF3 cmOpen 5 sub '~M~ore' item '~Ф~орма' '' '' cmForm 6 end end
TMenuPopup.new pp 10 5 40 12 item '~C~opy' '' '' cmCopy 0
TStatusLine.new st 0 19 60 20 'x' kbF9 cmX
PATH=''
r=''
lf_data[Options]=\$FV_OF_SELECTABLE
fv.views.insert desk lf; fv.views.insert app desk; fv.views.insert app mb; fv.views.insert app st
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app \"\$FV_SF_FOCUSED\" 1
fv.views.drawView app
ge() {
    local s
    if (( \${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    s=\${q[0]}; q=(\"\${q[@]:1}\")
    fv.drivers.clearEvent
    FV_EV_WHAT=\${s%%/*} s=\${s#*/}
    if [ \"\$FV_EV_WHAT\" = evKeyDown ]; then FV_EV_KEY=\${s%%/*} FV_EV_CHAR=\${s#*/}
    else FV_EV_MOUSE_X=\${s%%/*} FV_EV_MOUSE_Y=\${s#*/} FV_EV_MOUSE_BUTTONS=1; fi
}
__FV_VW_GETEVENT=ge
ev() { fv.drivers.clearEvent; __FV_DR_PEND=(); FV_EV_WHAT=\$1 FV_EV_KEY=\$2 FV_EV_CHAR=\$3 FV_EV_MOUSE_X=\$4 FV_EV_MOUSE_Y=\$5 FV_EV_MOUSE_BUTTONS=1; fv.views._virt app HandleEvent; r+=\"\${__FV_DR_PEND[3]-none},\"; }
q=(evKeyDown/kbChar/m evKeyDown/kbChar/ф)
ev evKeyDown kbAltF f 0 0
q=(evKeyDown/kbF3/)
ev evKeyDown kbAltF f 0 0
q=(evMouseUp/3/2)
ev evMouseDown '' '' 2 0
q=()
ev evKeyDown kbAltF f 0 0
r+=\"eof\$__FV_VW_EOF,\"; __FV_VW_EOF=0
__FV_DR_PEND=(); q=(evKeyDown/kbChar/c)
fv.views.execView desk pp; r+=\"\$RESULT,\"
fv.menus.setHint st 0 'Hi'; fv.video.getRow 19; r+=\"\${RESULT:0:7},\"
fv.views.disableCommands cmOpen; fv.views.message app evBroadcast cmCommandSetChanged || :; r+=\"\${mb_mdis[1]},\"
pp.delete; app.delete
r+=\"\${#__FV_MN_MV[@]}\"
printf '%s' \"\$r\"" 2>&1)
want='cmForm,cmOpen,cmOpen,none,eof1,cmCopy, x │ Hi,1,0'
if [[ $out == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$out] want [$want]"; fi

kt_test_start "fv.menus.sh: no fork construct on any code line"
bad='' n=0 fn=''
while IFS= read -r l || [[ -n $l ]]; do
    n=$(( n + 1 ))
    if [[ $l =~ ^([A-Za-z_][A-Za-z0-9_.]*)\(\)\ \{ ]]; then fn=${BASH_REMATCH[1]}; fi
    if fvw_forks "$l"; then bad+=" $n(${fn:-file}):[$l]"; fi
done < "$FVM_TESTS_DIR/../fv.menus.sh"
if [[ -z $bad ]] && (( n > 300 )); then kt_test_pass "$n lines clean"; else kt_test_fail "${bad:-only $n lines}"; fi

kt_test_log "007_ZeroFork.sh completed"
