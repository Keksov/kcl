#!/usr/bin/env bash
# 023_HistoryState.sh - the input history (P3 stage 3h) under the unit-wide
# rules:
#   * PATH='' (no external command can run): a dialog with two history
#     lines run modally with Down, Down, Enter, Tab, Down + Esc on the second
#     line, a click on the history view + a double click on a row, Enter on
#     the default button (cmRecordHistory) — the window made and destroyed on
#     the way: the same answers, no "command not found" (the static scan of
#     fv.dialogs.sh is 014's);
#   * the caller's state: the same scene under IFS ' \t\n' / $'\x1f' / '',
#     nocasematch, extglob, a C locale, set -u gives the reference answers
#     and leaves the state as it was (the views are made before the setup,
#     as in 015; the history windows are made during the scene, under it);
#   * 100 open / close cycles leave no view, array or function behind and
#     no table grows (every global array's size equal before and after);
#   * a THistory subclass overriding every virtual with `inherited` gives the
#     built-in's results; overrides of InitHistoryWindow (a window class of
#     yours) and RecordHistory (a text of yours) are used.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "023: the history under the unit's rules"

# the child scene: SETUP runs after the views are made; prints the answers,
# then '#' and whether the caller's state is unchanged
cat > "$FVW_TMP/scene.sh" <<EOF
source '$FVG_TESTS_DIR/../fv.dialogs.sh'
exec {FVO}>/dev/null; FV_VIDEO_OUT_FD=\$FVO FV_SCREEN_W=80 FV_SCREEN_H=24; fv.video.initScreen
TGroup.new app 0 0 80 24; TGroup.new desk 0 0 80 24; TView.new bg 0 0 80 24
fv.views.insert desk bg; fv.views.insert app desk
app_data[State]=\$(( app_data[State] | FV_SF_EXPOSED | FV_SF_SELECTED | FV_SF_MODAL ))
fv.views.setState app "\$FV_SF_FOCUSED" 1
TDialog.new dlg 10 4 70 18 Find
TInputLine.new il 3 2 23 3 6
THistory.new hi 23 2 26 3 il 5
TInputLine.new il2 3 5 23 6 30
THistory.new hi2 23 5 26 6 il2 6
TButton.new ok 14 10 24 12 'O~K~' cmOK 1
for v in il hi il2 hi2 ok; do fv.views.insert dlg \$v; done
fv.views.select il
fv.views.drawView app
for v in alpha 'Бета два' '中文字符串和'; do fv.histlist.historyAdd 5 "\$v"; done
fv.dialogs.setText il 'mine'; fv.dialogs.setText il2 'two'
ge() {
    local s
    if (( \${#__FV_DR_PEND[@]} )); then fv.drivers.getEvent 0; return; fi
    if (( ! \${#q[@]} )); then FV_EV_WHAT=evNothing; return 1; fi
    s=\${q[0]}; q=("\${q[@]:1}")
    fv.drivers.clearEvent
    FV_EV_WHAT=\${s%%:*}; s=\${s#*:}
    if [ "\$FV_EV_WHAT" = evKeyDown ]; then FV_EV_KEY=\$s
    else FV_EV_MOUSE_X=\${s%%:*}; s=\${s#*:}; FV_EV_MOUSE_Y=\${s%%:*}; FV_EV_MOUSE_DOUBLE=\${s#*:}; FV_EV_MOUSE_BUTTONS=1; fi
}
__FV_VW_GETEVENT=ge
st() { printf -v "\$1" '%s|' "\${IFS@Q}" "\$-" "\$BASHOPTS" "\${LC_ALL-unset}" "\${#ZH}"; }
ZH=ж
eval "\$SETUP"
st S0
r=''
q=('evKeyDown:kbDown' 'evKeyDown:kbDown' 'evKeyDown:kbEnter' 'evKeyDown:kbTab' 'evKeyDown:kbDown' 'evKeyDown:kbEsc'
   'evMouseDown:34:6:0' 'evMouseUp:34:6:0' 'evMouseDown:14:6:0' 'evMouseUp:14:6:0' 'evMouseDown:14:6:1' 'evMouseUp:14:6:0' 'evKeyDown:kbEnter')
RESULT=keep
fv.views.execView desk dlg; r+="\$RESULT|"
fv.dialogs.getText il; r+="\$RESULT|"
fv.dialogs.getText il2; r+="\$RESULT|"
for id in 5 6; do
    fv.histlist.historyCount \$id; n=\$RESULT
    for (( i = 0; i < n; i++ )); do fv.histlist.historyStr \$id \$i; r+="\$RESULT,"; done
    r+='|'
done
n=0; for v in "\${!__FV_VW_LIVE[@]}"; do [[ \$v == *__fvhw* ]] && n=\$(( n + 1 )); done; r+="live \$n|"
st S1
eval "\${RESTORE:-:}"
printf '%s#%s' "\$r" "\$([ "\$S0" = "\$S1" ] && echo same || echo "\$S0 -> \$S1")"
EOF

# (il: MaxLen 6; Down records mine: mine 中文字符串和 Бета два alpha; item 1 +
# Down = Бета два -> cut to 6 clusters 'Бета д'; Tab records it; il2: Down
# records two (id 6: two), Esc; the click on hi focuses il, records 'Бета д'
# (already the newest), opens: item 1 = mine, the click on row 0 (y 6) then
# the double click on it: 'Бета д'; Enter: OK records both)
WANT='cmOK|Бета д|two|Бета д,mine,中文字符串和,Бета два,alpha,|two,|live 0|#same'

kt_test_start "PATH='': the whole history path, no external command; the reference answers"
out=$(SETUP="PATH=''" "$BASH" "$FVW_TMP/scene.sh" 2>&1)
if [[ $out == "$WANT" ]]; then kt_test_pass ok; else kt_test_fail "got [$out] want [$WANT]"; fi

for setup in "IFS=\$' \\t\\n'" "IFS=\$'\\x1f'" "IFS=" "shopt -s nocasematch" "shopt -s extglob" "LC_ALL=C" "set -u" \
             "shopt -s nocasematch extglob; IFS=\$'\\x1f'; set -u"; do
    kt_test_start "the caller's state: $setup"
    out=$(SETUP=$setup "$BASH" "$FVW_TMP/scene.sh" 2>&1)
    if [[ $out == "$WANT" ]]; then kt_test_pass ok; else kt_test_fail "got [$out] want [$WANT]"; fi
done

kt_test_section "023: 100 open / close cycles"
fvw_tscene 80 24
TDialog.new dlg 10 4 70 18 'Find'
TInputLine.new il 3 2 23 3 30
THistory.new hi 23 2 26 3 il 5
fv.views.insert dlg il; fv.views.insert dlg hi; fv.views.select il
fv.views.drawView app
fv.histlist.clearHistory; fv.histlist.historyAdd 5 one; fv.histlist.historyAdd 5 two
fv.dialogs.setText il three
# sizes: every global array's element count and every name (variables and
# functions), after a warm-up run
sizes() {
    local v out=''
    for v in $(compgen -v); do
        case $v in FVW_*|RESULT|REPLY|BASH_*|FUNCNAME|PIPESTATUS|_|v|out|COLUMNS|LINES|RANDOM|SECONDS|EPOCH*|SRANDOM|LINENO|BASHPID) continue ;; esac
        local -n __t_a=$v
        out+="$v:${#__t_a[@]} "
        unset -n __t_a
    done
    SZ="$out|$(compgen -A function | wc -l)"
}
ev=(); for i in {1..100}; do ev+=('key kbDown' 'key kbEsc'); done
s0='' s1='' SZ=''
fvg_run 'key kbDown' 'key kbEsc' 'key kbCtrlF4'
sizes; s0=$SZ
fvg_run "${ev[@]}" 'key kbCtrlF4'
sizes; s1=$SZ
kt_test_start "no view, array, variable or function left behind; no table grew"
if [[ $s0 == "$s1" ]] && ! compgen -v | grep -q fvhw; then kt_test_pass "$(( ${#s0} )) chars of sizes equal"
else
    d=''
    for w in $s1; do [[ " $s0 " == *" $w "* ]] || d+=" $w"; done
    kt_test_fail "changed: [$d] (functions ${s0##*|} -> ${s1##*|})"
fi
kt_test_start "after the cycles: the store unchanged in size, == a full repaint"
hist=''; fv.histlist.historyCount 5; n=$RESULT; for (( i = 0; i < n; i++ )); do fv.histlist.historyStr 5 $i; hist+="$RESULT,"; done
fv.views.insert desk dlg; fv.views.select dlg
if [[ $hist == 'three,two,one,' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$hist] $FVW_DIFF"; fi
fv.views.delete desk dlg
app.delete; dlg.delete

kt_test_section "023: overrides"
class XHistory : THistory
    public
        override proc Draw
        override proc HandleEvent
        override func GetPalette
        override func InitHistoryWindow
        override proc RecordHistory
end
XHistory.Draw() { inherited Draw "$@"; }
XHistory.HandleEvent() { inherited HandleEvent "$@"; }
XHistory.GetPalette() { inherited GetPalette "$@"; }
XHistory.InitHistoryWindow() { inherited InitHistoryWindow "$@"; }
XHistory.RecordHistory() { inherited RecordHistory "$@"; }
build XHistory
class XHistoryWindow : THistoryWindow
    public
        override func GetPalette
        override func GetSelection
        override proc InitViewer
end
XHistoryWindow.GetPalette() { inherited GetPalette "$@"; }
XHistoryWindow.GetSelection() { inherited GetSelection "$@"; RESULT="<$RESULT>"; }
XHistoryWindow.InitViewer() { inherited InitViewer "$@"; }
build XHistoryWindow
class YHistory : THistory
    public
        override func InitHistoryWindow
        override proc RecordHistory
end
YHistory.InitHistoryWindow() { XHistoryWindow.new yw "$1" "$2" "$3" "$4" "$HistoryId"; RESULT=yw; }
YHistory.RecordHistory() { fv.histlist.historyAdd "$HistoryId" "${1^^}"; }
build YHistory

# run CLASS : a dialog with a CLASS history view, Down Down Enter, then Esc;
# OUT = the answers and the screen's rows of the dialog
run() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Find'
    TInputLine.new il 3 2 23 3 30
    "$1.new" hi 23 2 26 3 il 5
    fv.views.insert dlg il; fv.views.insert dlg hi; fv.views.select il
    fv.views.drawView app
    fv.histlist.clearHistory; fv.histlist.historyAdd 5 one; fv.histlist.historyAdd 5 two
    fv.dialogs.setText il three
    snap() { local y; P_X=''; for y in 4 5 6 7 8 9 10 11 12; do fvw_row $y; P_X+="$RESULT|$REPLY/"; done; }
    fvg_run 'key kbDown' 'run snap' 'key kbDown' 'key kbEnter' 'key kbEsc'
    fv.dialogs.getText il; OUT="$FVG_R|$RESULT|"
    local i n; fv.histlist.historyCount 5; n=$RESULT
    for (( i = 0; i < n; i++ )); do fv.histlist.historyStr 5 $i; OUT+="$RESULT,"; done
    OUT+="|$P_X"
    fv.views.insert desk dlg; fv.views.select dlg
    fvw_full app || OUT+="|not a full repaint: $FVW_DIFF"
    app.delete
    if fv.views.isView dlg; then dlg.delete; fi
}
run THistory; base=$OUT
kt_test_start "every virtual overridden with inherited: the built-in's answers, history and screens"
run XHistory
if [[ $OUT == "$base" ]]; then kt_test_pass ok; else kt_test_fail "got [${OUT:0:300}] want [${base:0:300}]"; fi
kt_test_start "overrides used: InitHistoryWindow (a window class of yours, its GetSelection), RecordHistory (upper case)"
run YHistory
if [[ $OUT == 'cmCancel|<one>|<ONE>,THREE,two,one,|'* && $OUT != *'not a full repaint'* ]] && ! fv.views.isView yw; then kt_test_pass "${OUT:0:40}"
else kt_test_fail "[${OUT:0:200}]"; fi

kt_test_log "023_HistoryState.sh completed"
