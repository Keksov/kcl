#!/usr/bin/env bash
# 009_Commands.sh - command sets of stage 2c-3 (design §1.8; FV
# EnableCommands / DisableCommands / CommandEnabled / GetCommands /
# SetCommands, CommandSetChanged, TWindow.SetState's window commands):
#   * FV's default at load: cmZoom cmClose cmResize cmNext cmPrev disabled,
#     everything else (any name) enabled; FV_COMMANDSETCHANGED 0;
#   * enable / disable / commandEnabled; the changed flag only on a real
#     change; getCommands (the disabled names, sorted) and setCommands
#     (exactly these disabled) as a save / restore pair;
#   * a selected TWindow enables cmNext cmPrev, cmResize (wfGrow or wfMove),
#     cmClose (wfClose), cmZoom (wfZoom), and disables them when deselected;
#   * execView restores the command set its modal view changed;
#   * refusals: names with other characters, argument counts (rc 2).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "009: commands"

kt_test_start "FV's default at load: cmClose cmNext cmPrev cmResize cmZoom disabled, any other name enabled; the flag 0"
out=$("$BASH" -c "source '$FVW_TESTS_DIR/../fv.views.sh'
fv.views.getCommands; r=\"\$RESULT|\$FV_COMMANDSETCHANGED|\"
fv.views.commandEnabled cmQuit && r+=on, || r+=off,
fv.views.commandEnabled cmMyOwn_2 && r+=on, || r+=off,
fv.views.commandEnabled cmClose && r+=on || r+=off
printf '%s' \"\$r\"" 2>&1)
if [[ $out == 'cmClose cmNext cmPrev cmResize cmZoom|0|on,on,off' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "the default survives kk.unit --forget + a re-source (the set is kept, not re-applied)"
out=$("$BASH" -c "source '$FVW_TESTS_DIR/../fv.views.sh'
fv.views.enableCommands cmClose; kk.unit --forget fv.views; source '$FVW_TESTS_DIR/../fv.views.sh'
fv.views.getCommands; printf '%s' \"\$RESULT\"" 2>&1)
if [[ $out == 'cmNext cmPrev cmResize cmZoom' ]]; then kt_test_pass "ok"; else kt_test_fail "[$out]"; fi

kt_test_start "enable / disable / commandEnabled; FV_COMMANDSETCHANGED set only by a real change"
fv.views.setCommands cmZoom cmClose cmResize cmNext cmPrev
FV_COMMANDSETCHANGED=0
fv.views.disableCommands cmClose cmZoom; f1=$FV_COMMANDSETCHANGED
fv.views.enableCommands cmQuit; f2=$FV_COMMANDSETCHANGED
fv.views.disableCommands cmQuit cmSave; f3=$FV_COMMANDSETCHANGED
fv.views.commandEnabled cmQuit; e1=$?
FV_COMMANDSETCHANGED=0
fv.views.enableCommands cmQuit cmClose; f4=$FV_COMMANDSETCHANGED
fv.views.commandEnabled cmQuit; e2=$?
fv.views.commandEnabled cmSave; e3=$?
fv.views.getCommands
if [[ "$f1$f2$f3$f4|$e1$e2$e3|$RESULT" == '0011|101|cmNext cmPrev cmResize cmSave cmZoom' ]]; then kt_test_pass "ok"
else kt_test_fail "flags $f1$f2$f3$f4 enabled $e1$e2$e3 set [$RESULT]"; fi

kt_test_start "getCommands / setCommands save and restore a set; setCommands with nothing enables everything; RESULT of the procedures kept"
fv.views.getCommands; saved=$RESULT
fv.views.setCommands cmA cmB; fv.views.getCommands; s1=$RESULT
fv.views.setCommands; fv.views.getCommands; s2=$RESULT
fv.views.setCommands $saved; fv.views.getCommands; s3=$RESULT
RESULT=keep; fv.views.disableCommands cmX; fv.views.enableCommands cmX; fv.views.setCommands $saved; r=$RESULT
if [[ $s1 == 'cmA cmB' && -z $s2 && $s3 == "$saved" && $r == keep ]]; then kt_test_pass "ok"; else kt_test_fail "[$s1] [$s2] [$s3] vs [$saved] RESULT [$r]"; fi

kt_test_start "a selected TWindow enables its window commands, deselected disables them (by Flags)"
fv.views.setCommands cmZoom cmClose cmResize cmNext cmPrev
fvw_screen
TGroup.new root 0 0 80 24; fvw_root root
TWindow.new wa 0 0 20 10 'A' 1
TWindow.new wb 20 0 40 10 'B' 2
wb_data[Flags]=$FV_WF_MOVE
fv.views.insert root wa; fv.views.getCommands; c1=$RESULT
FV_COMMANDSETCHANGED=0
fv.views.insert root wb; fv.views.getCommands; c2="$RESULT|$FV_COMMANDSETCHANGED"
wb_data[Flags]=0
fv.views.select wa; fv.views.select wb; fv.views.getCommands; c3=$RESULT
fv.views.delete root wb; fv.views.getCommands; c4=$RESULT
if [[ -z $c1 && $c2 == 'cmClose cmZoom|1' && $c3 == 'cmClose cmResize cmZoom' && -z $c4 ]]; then kt_test_pass "ok"
else kt_test_fail "wa [$c1] wb (move only) [$c2] wb (no flags) [$c3] wb deleted [$c4]"; fi

kt_test_start "destroying a group deselects its Current first (FV TGroup.Done hides its subviews): the window commands are disabled again"
fv.views.setCommands cmZoom cmClose cmResize cmNext cmPrev
TGroup.new dg 0 0 80 24; fvw_root dg
TWindow.new dw 0 0 20 10 'D' 1; fv.views.insert dg dw
fv.views.getCommands; c1=$RESULT
dg.delete
fv.views.getCommands; c2=$RESULT
if [[ -z $c1 && $c2 == 'cmClose cmNext cmPrev cmResize cmZoom' ]] && ! fv.views.isView dw; then kt_test_pass "ok"; else kt_test_fail "selected [$c1] after delete [$c2]"; fi

kt_test_start "execView restores the command set the modal view changed"
class TCmdDlg : TWindow
    public
        override proc HandleEvent
end
TCmdDlg.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmGo ]; then
        fv.views.disableCommands cmQuit cmGo; fv.views.enableCommands cmHelpMe
        fv.views.getCommands; INSIDE=$RESULT
        fv.views.endModal "$this" cmOK; fv.views.clearEvent "$this"
    fi
}
build TCmdDlg
TCmdDlg.new dlg 5 2 30 8 'Cmd' 0
fv.views.disableCommands cmHelpMe
fv.views.getCommands; before=$RESULT
fvw_events 'cmd cmGo'
fv.views.execView root dlg; r=$RESULT
fv.views.getCommands; after=$RESULT
fvw_noevents
dlg.delete
if [[ $r == cmOK && $INSIDE == *cmQuit* && $INSIDE != *cmHelpMe* && $after == "$before" ]]; then kt_test_pass "ok"; else kt_test_fail "result $r inside [$INSIDE] before [$before] after [$after]"; fi
root.delete

kt_test_start "refusals (rc 2, RESULT ''): a name with other characters, argument counts; nothing changed"
fv.views.getCommands; before=$RESULT
r=''
RESULT=x; fv.views.disableCommands 'cm Bad' || r+="$?[$RESULT],"
fv.views.enableCommands cmOk 'cm-x' || r+="$?,"
fv.views.disableCommands '' || r+="$?,"
fv.views.commandEnabled || r+="$?,"
fv.views.commandEnabled a b || r+="$?,"
fv.views.getCommands x || r+="$?,"
fv.views.setCommands 'a*' || r+="$?"
fv.views.getCommands
if [[ $r == '2[],2,2,2,2,2,2' && $RESULT == "$before" ]]; then kt_test_pass "ok"; else kt_test_fail "[$r] set [$RESULT] vs [$before]"; fi

kt_test_log "009_Commands.sh completed"
