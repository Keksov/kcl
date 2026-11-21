#!/usr/bin/env bash
# 012_Focus.sh - focus between the controls of a dialog (design P3 §3.1):
#   * Tab / Shift+Tab follow FV's order (insertion order, ring; labels and
#     static texts are not selectable), the arrows move too where no control
#     takes them (buttons), a cluster takes its arrows first;
#   * the phases: a pre / post-process view of yours sees each key with its
#     owner's Phase, interleaved with the widgets in Z order (the hot-key map
#     skips only built-in widgets the key does not name);
#   * the focus broadcasts reach the labels (Light) and the buttons' default
#     grab / release; every step == a full repaint;
#   * a disabled control is skipped by Tab.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "012: Tab order"
fvg_modeless
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-}; fv.views._virt dlg HandleEvent; }
kt_test_start "Tab: opts -> dir -> ok -> cn -> hp -> opts, each == a full repaint"
seq='' bad=''
for i in 1 2 3 4 5; do k kbTab; seq+="${dlg_data[Current]} "; fvw_full app || bad+=" step $i:$FVW_DIFF"; done
if [[ $seq == 'dir ok cn hp opts ' && -z $bad ]]; then kt_test_pass ok; else kt_test_fail "[$seq] $bad"; fi
kt_test_start "Shift+Tab backwards: opts -> hp -> cn"
k kbShiftTab; a=${dlg_data[Current]}; k kbShiftTab; b=${dlg_data[Current]}
if [[ $a.$b == hp.cn ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "arrows on a button move the focus (TWindow); on a cluster they move Sel"
k kbRight; a=${dlg_data[Current]}
fv.views.focus opts; k kbDown; b=${dlg_data[Current]}:${opts_data[Sel]}
if [[ $a == hp && $b == opts:1 ]]; then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "a disabled button is skipped by Tab"
cn_data[State]=$(( cn_data[State] | FV_SF_DISABLED ))
fv.views.focus ok; k kbTab; a=${dlg_data[Current]}
cn_data[State]=$(( cn_data[State] & ~FV_SF_DISABLED ))
if [ "$a" = hp ]; then kt_test_pass ok; else kt_test_fail "$a"; fi

kt_test_section "012: phases and views of yours"
class TSpy : TView
    public
        override proc HandleEvent
end
TSpy.HandleEvent() {
    local -n o=${Owner}_data
    if [ "$FV_EV_WHAT" = evKeyDown ]; then GOT+="$this:${o[Phase]}:$FV_EV_KEY;"; fi
}
build TSpy
TSpy.new spya 0 0 1 1; spya_data[Options]=$(( FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
TSpy.new spyb 0 0 1 1; spyb_data[Options]=$FV_OF_POSTPROCESS
fv.views.insertBefore dlg spya ok
fv.views.insertBefore dlg spyb opts
kt_test_start "an unnamed key: the spies see pre and post with their Phase, in Z order; widgets skipped"
fv.views.focus ok
GOT=''; k kbF9
if [ "$GOT" = 'spya:phPreProcess:kbF9;spya:phPostProcess:kbF9;spyb:phPostProcess:kbF9;' ]; then kt_test_pass ok; else kt_test_fail "[$GOT]"; fi
kt_test_start "a hot key handled in the pre-process phase (Alt+H by hp, in front of spya): spya not reached"
GOT=''; __FV_DR_PEND=(); k kbAltH h
p=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [[ $p == cmHelp && -z $GOT ]]; then kt_test_pass ok; else kt_test_fail "[$p] [$GOT]"; fi
kt_test_start "a plain hot letter: handled by hp in the post phase, after spya's pre call"
GOT=''; k kbChar h
p=${__FV_DR_PEND[3]-}; __FV_DR_PEND=()
if [[ $p == cmHelp && $GOT == 'spya:phPreProcess:kbChar;' ]]; then kt_test_pass ok; else kt_test_fail "[$p] [$GOT]"; fi
fv.views.delete dlg spya; fv.views.delete dlg spyb; spya.delete; spyb.delete

kt_test_section "012: the broadcasts"
kt_test_start "focus on cn: OK gives up the default look, l1 goes dark; back on opts: both return"
fv.views.focus cn
a=${ok_data[AmDefault]}${l1_data[Light]}
fv.views.focus opts
b=${ok_data[AmDefault]}${l1_data[Light]}
if [[ $a.$b == 00.11 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a $b $FVW_DIFF"; fi
fvg_unscene
