#!/usr/bin/env bash
# 013_CallBudget.sh - the dispatch and write budgets of design P3 §8.1 for
# the dialog actions of stage 3c, in the design's scene: an application
# whose HandleEvent is an override (TMyApp-like, `inherited` first; F2 runs
# the pre-built test dialog modally in the desktop, F4 builds the 8-control
# test dialog, runs it and destroys it), the desktop with two windows side
# by side, the events through TGroup's Execute with the scripted source:
#   * Tab between two controls of the modal dialog: 0 dispatches (limit 4),
#     writes <= 8 (four focus changes' redraws: the old and the new control,
#     the default button's look given up and taken back);
#   * the dialog open + close, pre-built (F2 ... Ctrl+F4): limit 6 / 30;
#   * the 8-control dialog end to end (F4: build, open, close, destroy):
#     limit 30 / 26;
#   * the dialog's full draw (drawView): limit 2 / 24;
#   * a hot key (Alt+K) pressing OK, Space on a check box (one write), a
#     radio move (one write); each scene == a full repaint;
#   * (3d) typing into an input line; (3h) the same with a THistory after
#     the line (the hot-key map calls it for kbDown / kbCtrlX only: the
#     typing budgets unchanged), and the history window opened by Down on
#     the line and closed by Esc (10 strings; the window, its frame, two
#     bars and the viewer made and destroyed: 10 dispatches, the
#     constructors, and 19 writes measured): limit 14 / 26;
#   * (3g, design R1 / R2) a 20-control dialog against an 8-control one:
#     Tab, Shift+Tab, typing, Backspace, F9 and a hot key cost the same
#     dispatches and writes; keys reach no label / button / cluster body in
#     either; a focus change reaches each extra label twice (FV's focus
#     broadcasts), without a write.
# Measured (Git-bash 5.3; §8.1's prototype numbers in brackets): open +
# close 5 / 21 [2 / 23: here the focused stand-in sees F2 and the two
# stand-ins' Draw overrides repaint under the closed dialog], Tab 0 / 4
# [0 / 6], build-run-destroy 25 / 21 [22 / 19: 3 + 10 constructors (the
# dialog, its frame, 8 controls) + 2 stand-in Draws + 10 Done], paint 0 / 13
# [0 / 21], typing 0 / 1.
# The counts are logged ("# calls" / "# writes"); deltas are taken against a
# run with only the closing key, so the loop's own reads cancel out.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "013: dialog budgets (design §8.1)"
class TDApp : TGroup
    public
        override proc HandleEvent
end
TDApp.HandleEvent() {
    inherited HandleEvent "$@"
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbF2 ]; then fv.views.execView desk "${EXDLG:-dlg}"; fv.views.clearEvent "$this"
        elif [ "$FV_EV_KEY" = kbF4 ]; then
            fvg_mkdlg dlg8 e_
            fv.views.execView desk dlg8
            dlg8.delete
            fv.views.clearEvent "$this"
        fi
    fi
}
build TDApp

fvw_screen 80 24
fvw_classes3
TDApp.new app 0 0 80 24
TGroup.new desk 0 0 80 23
TView.new bg 0 0 80 23
fv.views.insert desk bg
fvw_mklwin w1 0 0 40 23 'Files' 1
fvw_mklwin w2 40 0 80 23 'Panel two' 2
fv.views.insert desk w1; fv.views.insert desk w2
fv.views.insert app desk
TView.new sl 0 23 80 24; fv.views.insert app sl
fvw_root app
fvg_mkdlg dlg
fv.views.drawView app

# run SPEC... : the application's loop over the scripted events, counted;
# C / W = its dispatches / writes
run() {
    if [[ -n ${PREP-} ]]; then "$PREP"; fi
    fvg_events "$@"
    fvw_count_on; fvw_writes_on
    FVW_CALLS=0 FVW_WRITES=0 FVW_HB=0
    fv.views._virt app Execute || :
    C=$FVW_CALLS W=$FVW_WRITES HB=$FVW_HB
    fvw_count_off; fvw_writes_off
    fvw_noevents
}
# budget LABEL LIMITC LIMITW BASE-SPECS -- SPECS : the delta of SPECS over BASE
budget() {
    local l=$1 lc=$2 lw=$3 c0 w0 h0
    shift 3
    local -a b=()
    while (( $# )) && [ "$1" != -- ]; do b+=("$1"); shift; done
    shift
    run "${b[@]}"; c0=$C w0=$W h0=$HB
    run "$@"
    C=$(( C - c0 )) W=$(( W - w0 )) HB=$(( HB - h0 ))
    kt_test_start "budget $l: at most $lc dispatches, $lw writes"
    kt_test_log "# calls $l $C"
    kt_test_log "# writes $l $W"
    if (( C <= lc && W <= lw )); then kt_test_pass "$C dispatches, $W writes"; else kt_test_fail "$C dispatches ($lc), $W writes ($lw)"; fi
}

budget dlg.open-close 6 30 -- 'key kbF2' 'key kbCtrlF4'
kt_test_start "after open + close: == a full repaint, the dialog out of desk"
if [[ -z ${dlg_data[Owner]} ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
budget dlg.tab 4 8 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbTab' 'key kbCtrlF4'
budget dlg.tab-buttons 4 8 'key kbF2' 'key kbShiftTab' 'key kbShiftTab' 'key kbCtrlF4' -- 'key kbF2' 'key kbShiftTab' 'key kbShiftTab' 'key kbShiftTab' 'key kbCtrlF4'
fv.views.select opts
budget dlg.space 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char _' 'key kbCtrlF4'
rprep() { dir_data[Value]=0 dir_data[Sel]=0; fv.views.select dir; }
PREP=rprep budget dlg.radio-down 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbDown' 'key kbCtrlF4'
PREP=
fv.views.select opts
budget dlg.hotkey-ok 6 30 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'alt k'
budget dlg.build-run-destroy 30 26 -- 'key kbF4' 'key kbCtrlF4'
kt_test_start "after the end-to-end dialog: no view left, == a full repaint"
if ! fv.views.isView dlg8 && ! fv.views.isView e_ok && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi

fv.views.insert desk dlg; fv.views.select dlg
fvw_budgetw dlg.paint 2 fv.views.drawView dlg
kt_test_start "budget dlg.paint: at most 24 writes"
if (( FVW_LASTW <= 24 )); then kt_test_pass "$FVW_LASTW writes"; else kt_test_fail "$FVW_LASTW writes"; fi
kt_test_start "the dialog's draw == a full repaint"
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete desk dlg

# (P3 3d) typing into an input line of the modal dialog (design §8.1:
# 0 dispatches, 1 write per key; limits 2 / 2), the line made the dialog's
# Current (its text selected as the dialog opens: FV's SelectAll on focus)
TInputLine.new tin 3 8 40 9 255
fv.views.insert dlg tin
# (P3 3h) its history view: the typing budgets below hold with it
THistory.new thi 40 8 43 9 tin 1
fv.views.insert dlg thi
for i in {1..10}; do fv.histlist.historyAdd 1 "search text $i"; done
fv.views.select tin
budget dlg.type 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbCtrlF4'
budget dlg.type-cyr 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char ж' 'key kbCtrlF4'
budget dlg.type-cjk 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char 中' 'key kbCtrlF4'
budget dlg.type-back 2 2 'key kbF2' 'char a' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbBack' 'key kbCtrlF4'
fv.dialogs.setText tin "$(printf 'w%.0s' {1..70})"
budget dlg.type-scrolled 2 2 'key kbF2' 'key kbEnd' 'key kbCtrlF4' -- 'key kbF2' 'key kbEnd' 'char a' 'key kbCtrlF4'
fv.dialogs.setText tin "$(printf 'w%.0s' {1..70})"
budget dlg.shift-left 2 2 'key kbF2' 'key kbEnd' 'key kbCtrlF4' -- 'key kbF2' 'key kbEnd' 'key kbShiftLeft' 'key kbCtrlF4'
fv.dialogs.setText tin 'search text 3'
budget dlg.history-open-close 14 26 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbDown' 'key kbEsc' 'key kbCtrlF4'
kt_test_start "after the typing: == a full repaint"
fv.views.insert desk dlg; fv.views.select dlg
if fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
fv.views.delete desk dlg

# (P3 3g) design R1 / R2: a 20-control dialog costs what an 8-control one
# costs per keystroke. Both dialogs 76 x 21, built by mkdlgn: a label + input
# line (focused), check boxes, a label + radio buttons, then (20 only) six
# more labels + input lines, then OK (default) / Cancel / Help: Tab and
# Shift+Tab leave the line for the same neighbours in both. Tab, Shift+Tab,
# typing, Backspace, a key nobody takes (F9) and a hot key (Alt+W: an item of
# the check boxes) give the same dispatches and writes in both — the pre /
# post-process views are found by the hot-key map, not by a scan, and the
# broadcasts reach only the views whose built-in handler reacts (the
# broadcast table) — within the §8.1 limits of the 8-control dialog
mkdlgn() {   # NAME N
    local d=$1 p=${1}_ v i
    local -a c=()
    TDialog.new "$d" 2 1 78 22 'Find'
    TLabel.new "${p}l1" 2 1 14 2 '~T~ext' "${p}in1"
    TInputLine.new "${p}in1" 15 1 57 2 255
    TCheckBoxes.new "${p}opts" 3 3 30 6 '~C~ase sensitive' '~W~hole words' 'Re~g~ex'
    TLabel.new "${p}l2" 32 2 46 3 '~D~irection' "${p}dir"
    TRadioButtons.new "${p}dir" 32 3 56 5 '~F~orward' '~B~ackward'
    c=(l1 in1 opts l2 dir)
    if (( $2 == 20 )); then
        local -a hot=(N P M E S A)
        for (( i = 0; i < 6; i++ )); do
            TLabel.new "${p}x$i" 2 $(( 7 + i * 2 )) 14 $(( 8 + i * 2 )) "Field ~${hot[i]}~" "${p}y$i"
            TInputLine.new "${p}y$i" 15 $(( 7 + i * 2 )) 57 $(( 8 + i * 2 )) 255
            c+=("x$i" "y$i")
        done
    fi
    TButton.new "${p}ok" 14 18 24 20 'O~K~' cmOK "$FV_BF_DEFAULT"
    TButton.new "${p}cn" 26 18 38 20 'Cancel' cmCancel
    TButton.new "${p}hp" 40 18 50 20 '~H~elp' cmHelp
    c+=(ok cn hp)
    if (( ${#c[@]} != $2 )); then echo "mkdlgn: ${#c[@]} controls, not $2" >&2; fi
    for v in "${c[@]}"; do fv.views.insert "$d" "$p$v"; done
    fv.views.select "${p}in1"
}
mkdlgn dn8 8
mkdlgn dn20 20
declare -A NC=() NW=() NH=()
# (the built-in HandleEvent bodies of the labels, buttons and clusters
# counted too: FVW_HB, the views the pre / post-process passes reach)
fvw_wrap FVW_HB fv.dialogs._lblEvent fv.dialogs._btnEvent fv.dialogs._clEvent
for n in 8 20; do
    EXDLG=dn$n
    nprep() { fv.views.select "${EXDLG}_in1"; local -n o=${EXDLG}_opts_data; o[Value]=0; }
    PREP=nprep
    budget "dlg$n.tab" 4 8 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbTab' 'key kbCtrlF4'
    NC[tab|$n]=$C NW[tab|$n]=$W NH[tab|$n]=$HB
    budget "dlg$n.tab-back" 4 8 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbShiftTab' 'key kbCtrlF4'
    NC[tab-back|$n]=$C NW[tab-back|$n]=$W NH[tab-back|$n]=$HB
    budget "dlg$n.type" 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbCtrlF4'
    NC[type|$n]=$C NW[type|$n]=$W NH[type|$n]=$HB
    budget "dlg$n.type-back" 2 2 'key kbF2' 'char a' 'key kbCtrlF4' -- 'key kbF2' 'char a' 'key kbBack' 'key kbCtrlF4'
    NC[type-back|$n]=$C NW[type-back|$n]=$W NH[type-back|$n]=$HB
    budget "dlg$n.fkey" 2 2 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'key kbF9' 'key kbCtrlF4'
    NC[fkey|$n]=$C NW[fkey|$n]=$W NH[fkey|$n]=$HB
    budget "dlg$n.hotkey" 4 8 'key kbF2' 'key kbCtrlF4' -- 'key kbF2' 'alt w' 'key kbCtrlF4'
    NC[hotkey|$n]=$C NW[hotkey|$n]=$W NH[hotkey|$n]=$HB
    kt_test_start "dlg$n: the actions did their work (Alt+W: the check boxes focused, Whole words checked)"
    r="${EXDLG}_opts_data[Value]" q="${EXDLG}_data[Current]"
    if [[ ${!r-} == 2 && ${!q-} == "${EXDLG}_opts" ]]; then kt_test_pass ok; else kt_test_fail "Value [${!r-}] Current [${!q-}]"; fi
done
PREP=
kt_test_start "R1: a 20-control dialog costs the dispatches and writes of an 8-control one (Tab, Shift+Tab, typing, Backspace, F9, a hot key)"
bad=''
for a in tab tab-back type type-back fkey hotkey; do
    [[ ${NC[$a|8]}/${NW[$a|8]} == "${NC[$a|20]}/${NW[$a|20]}" ]] || bad+=" [$a: ${NC[$a|8]}/${NW[$a|8]} vs ${NC[$a|20]}/${NW[$a|20]}]"
done
if [[ -z $bad && ${#NC[@]} == 12 ]]; then kt_test_pass ok; else kt_test_fail "$bad"; fi
fvw_unwrap fv.dialogs._lblEvent fv.dialogs._btnEvent fv.dialogs._clEvent
# (keys: no label / button / cluster body reached in either dialog — the
# hot-key map; a focus change: FV's cmReleasedFocus + cmReceivedFocus
# broadcasts reach every TLabel, whose built-in handler reacts to them (its
# Light), so the 20-control dialog's six extra labels add 2 x 6 = 12 body
# calls per focus change and no write: P3-12 redraws a label only when its
# Light changes. Measured 8 / 20: tab 10 / 22, tab-back 16 / 28, hot key
# 11 / 23, typing / Backspace / F9 0 / 0)
kt_test_start "R1 / R2: label / button / cluster bodies reached: keys none in both (the hot-key map), a focus change + 2 per extra label (the focus broadcasts)"
bad='' r=''
for a in tab tab-back type type-back fkey hotkey; do
    r+=" $a ${NH[$a|8]}/${NH[$a|20]}"
    case $a in
        type|type-back|fkey) [[ ${NH[$a|8]}/${NH[$a|20]} == 0/0 ]] || bad+=" [$a: ${NH[$a|8]} / ${NH[$a|20]}]" ;;
        *) (( ${NH[$a|20]} - ${NH[$a|8]} == 12 )) || bad+=" [$a: ${NH[$a|8]} / ${NH[$a|20]}]" ;;
    esac
done
kt_test_log "# handler bodies (8 / 20 controls):$r"
if [[ -z $bad && ${#NH[@]} == 12 ]]; then kt_test_pass "$r"; else kt_test_fail "$bad"; fi
EXDLG=
kt_test_start "after the 20-control runs: both dialogs closed, == a full repaint"
if [[ -z ${dn8_data[Owner]} && -z ${dn20_data[Owner]} ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$FVW_DIFF"; fi
app.delete; dlg.delete; dn8.delete; dn20.delete
