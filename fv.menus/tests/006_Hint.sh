#!/usr/bin/env bash
# 006_Hint.sh - TStatusLine.Hint and Update (FV: Hint '' by default; Update
# takes TopView's GetHelpCtx and, when it differs from the line's HelpCtx,
# FindItems + DrawView; design §2.1, D17): the counts of an Update with no
# change (0 dispatches, 0 writes) and after a HelpCtx change (another def:
# 0 dispatches, 1 write); a change inside the same def with the same Hint
# (HelpCtx follows, nothing drawn); a Hint override (redrawn when the hint
# text changes; its dispatches); a Draw override (redrawn on every change,
# as FV); the top view of a modal dialog (execView) and no top view at all
# (hcNoContext); a GetHelpCtx override on the chain (one dispatch); an
# Update override reached by fv.menus.update; RESULT kept.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "006: Hint and Update"

fvm_scene
fvm_draw

RESULT=x; st.Hint 5
fvw_check "TStatusLine.Hint: '' (FV)" "" "$RESULT"

FVW_WRITES=0; fvw_writes_on
fvw_budget "update no change" 0 fv.menus.update st
fvw_writes_off
kt_test_log "# writes update no change $FVW_WRITES"
fvw_check "Update with no change: nothing written, HelpCtx 0, def 0" "0|0|0" "$FVW_WRITES|${st_data[HelpCtx]}|${__FV_MN_CUR[st]}"

w2l_data[HelpCtx]=42
FVW_WRITES=0; fvw_writes_on
fv.menus.update st
fvw_writes_off
fvw_check "a HelpCtx change inside the same def, same Hint: HelpCtx follows, nothing drawn (D17)" "42|0|0" "${st_data[HelpCtx]}|${__FV_MN_CUR[st]}|$FVW_WRITES"

w2l_data[HelpCtx]=150
FVW_WRITES=0; fvw_writes_on
fvw_budget "update helpctx change" 0 fv.menus.update st
fvw_writes_off
kt_test_log "# writes update helpctx change $FVW_WRITES"
fvm_st
fvw_check "a HelpCtx change to another def: 1 write, def 1 shown" "1|1|150| F1 Help  Esc Cancel " "$FVW_WRITES|${__FV_MN_CUR[st]}|${st_data[HelpCtx]}|${RESULT:0:21}"

kt_test_start "after the def change the screen equals a full repaint"
if fvw_full app; then kt_test_pass "ok"; else kt_test_fail "$FVW_DIFF"; fi

w2l_data[HelpCtx]=0; fv.menus.update st
RESULT=keep; st.Update; a=$RESULT
RESULT=keep; fv.menus.update st; b=$?:$RESULT
fvw_check "the alias Update and fv.menus.update keep RESULT" "keep|0:keep" "$a|$b"

# sfDragging: TView's GetHelpCtx answers hcDragging (1)
w2l_data[State]=$(( w2l_data[State] | FV_SF_DRAGGING ))
fv.menus.update st
w2l_data[State]=$(( w2l_data[State] & ~FV_SF_DRAGGING ))
fvw_check "a dragging view on the chain: hcDragging (1)" "1" "${st_data[HelpCtx]}"
fv.menus.update st

# a modal dialog: TopView is the view execView runs (its HelpCtx)
TWindow.new dlg 10 5 50 15 'Dlg' 0
dlg_data[HelpCtx]=120
U=''
upd() { fv.menus.update st; U+="${st_data[HelpCtx]}:${__FV_MN_CUR[st]},"; }
fvw_events "run upd"
fv.views.execView desk dlg
fvw_noevents
fv.menus.update st
fvw_check "inside execView TopView is the dialog (HelpCtx 120, def 1); back to the desktop's after" "120:1,|0:0" "$U|${st_data[HelpCtx]}:${__FV_MN_CUR[st]}"
dlg.delete

# a GetHelpCtx override on the chain: one dispatch per Update
class THelpLeaf : TTLeaf
    public
        override func GetHelpCtx
end
THelpLeaf.GetHelpCtx() { RESULT=$(( 100 + ${FVW_ROW[$this]:-0} )); }
build THelpLeaf
fvw_mktwin w3 5 3 45 18 'Help' 3 THelpLeaf
fv.views.insert desk w3
fvw_budget "update with a GetHelpCtx override" 1 fv.menus.update st
fvw_check "  its answer is used (100: def 1)" "100|1" "${st_data[HelpCtx]}|${__FV_MN_CUR[st]}"
fv.views.delete desk w3; w3.delete
fv.menus.update st

fvm_unscene

# a Hint override: redrawn when the hint text changes inside a def; a Draw
# override: redrawn on every change
class THL : TStatusLine
    public
        override func Hint
end
THL.Hint() { if (( $1 < 50 )); then RESULT="low"; else RESULT="ctx $1"; fi; }
build THL
class TDL : TStatusLine
    public
        override proc Draw
end
declare -gi DLDRAWS=0
TDL.Draw() { DLDRAWS+=1; inherited Draw; }
build TDL
fvw_screen 80 24
TGroup.new root 0 0 80 24
TView.new lf 0 0 80 23
lf_data[Options]=$FV_OF_SELECTABLE
fv.views.insert root lf
THL.new hl 0 23 80 24 'a' kbF2 cmA
fv.views.insert root hl
fvw_root root
fv.views.drawView root
fv.video.getRow 23
fvw_check "the hint drawn after the items" " a │ low " "${RESULT:0:9}"
FVW_WRITES=0; fvw_writes_on
lf_data[HelpCtx]=10; fv.menus.update hl; w1=$FVW_WRITES
lf_data[HelpCtx]=60; fv.menus.update hl; w2=$FVW_WRITES
lf_data[HelpCtx]=70; fv.menus.update hl; w3=$FVW_WRITES
fvw_writes_off
fv.video.getRow 23
fvw_check "a Hint override: same hint (low) 0 writes; 'ctx 60' 1; 'ctx 70' 1 more" "0|1|2| a │ ctx 70 " "$w1|$w2|$w3|${RESULT:0:12}"
fvw_budget "update with a Hint override, no HelpCtx change" 0 fv.menus.update hl
fv.views.delete root hl; hl.delete

TDL.new dl 0 23 80 24 'a' kbF2 cmA
fv.views.insert root dl
lf_data[HelpCtx]=0; fv.menus.update dl
DLDRAWS=0
lf_data[HelpCtx]=5; fv.menus.update dl
lf_data[HelpCtx]=6; fv.menus.update dl
fv.menus.update dl
fvw_check "a Draw override: drawn on every HelpCtx change (FV), not without one" "2" "$DLDRAWS"
fv.views.delete root dl; dl.delete

# no top view (no sfModal on the way up): hcNoContext
TGroup.new free 0 0 80 24
TStatusLine.new fs 0 23 80 24 def 5 9 'a' kbF2 cmA
fv.views.insert free fs
fs_data[HelpCtx]=7; fv.menus._findItems fs
fv.menus.update fs
fvw_check "no top view: hcNoContext (0), no def holds it" "0|-1" "${fs_data[HelpCtx]}|${__FV_MN_CUR[fs]}"
free.delete

# an Update override, through fv.menus.update
class TUL : TStatusLine
    public
        override proc Update
end
TUL.Update() { UPD=$this; inherited Update; }
build TUL
TUL.new ul 0 0 10 1
UPD=''
fvw_budget "fv.menus.update with an Update override (+ inherited)" 2 fv.menus.update ul
fvw_check "  it ran" "ul" "$UPD"
ul.delete
root.delete

kt_test_log "006_Hint.sh completed"
