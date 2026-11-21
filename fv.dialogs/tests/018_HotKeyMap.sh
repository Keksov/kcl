#!/usr/bin/env bash
# 018_HotKeyMap.sh - fv.views' hot-key map (design P3 §3.1, 10.3b) with the
# real widgets: each scene is played with the map and with a full scan (the
# hot-key table emptied: fv.views' pre / post scan as before 3c) and must
# give the same reactions (who handled the key, the posted command, the
# dialog's Phase and Current after the key) and the expected one:
#   * a typed letter on a view that cannot react (disabled; a cluster whose
#     item with that letter is off in EnableMask; a button without
#     ofPreProcess / ofPostProcess) next to a base-key match: the base view
#     reacts (§14.4: typed first over the views that can react, then base);
#     an enabled typed match still wins;
#   * nested groups with pre / post holding mapped widgets, in both orders:
#     the inner group's pass does not leak into the outer group's list, and
#     an outer typed match wins over an inner base match (designed);
#   * a subclass that overrides HandleEvent (never mapped) asks in the typed
#     pass too, else without a pass (as a full scan); a typed letter written
#     away directly rebuilds the map before the pass (no stale typed pass);
#   * the focus moved to a mapped widget by a view during the key (focused
#     phase): the widget is called in the post phase (a focused button takes
#     Space);
#   * the Phase a full scan leaves: phPostProcess after a key nobody takes,
#     phPreProcess when only pre-process widgets were skipped;
#   * direct writes while the view is unfocused (no setter): a cluster's
#     `_items` element and a label's `Text` — the map's stamp sees them.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

hk_off() {
    unset '__FV_VW_HKS[fv.dialogs._btnEvent]' '__FV_VW_HKS[fv.dialogs._lblEvent]' '__FV_VW_HKS[fv.dialogs._clEvent]'
    fv.views._hkDirty
}
hk_on() { fv.dialogs._register; fv.views._hkDirty; }
declare -A VAL=()
sc_begin() { fvw_tscene 80 24; TDialog.new dlg 5 2 75 21 D; }
sc_open() {   # MODE [CURRENT]
    if [[ -n ${2-} ]]; then fv.views.select "$2"; fi
    fv.views.insert desk dlg
    fv.views.select dlg
    fv.views.drawView app
    if [ "$1" = full ]; then hk_off; else hk_on; fi
}
sc_end() { fvg_unscene; hk_on; }
# k KEY [CHAR [BASE]] — one key to the dialog; OUT += who handled it, the
# posted command, the dialog's Phase and Current
k() {
    fv.drivers.clearEvent
    __FV_DR_PEND=()
    FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=${3-}
    fv.views._virt dlg HandleEvent
    OUT+="$1/${2-}>$FV_EV_WHAT:${FV_EV_INFO-}:${__FV_DR_PEND[3]-}:${dlg_data[Phase]-}:${dlg_data[Current]-};"
    __FV_DR_PEND=()
}
# twice SCENE — A = the scene with the map, B = with the full scan
twice() { OUT=''; "sc_$1" map; A=$OUT; OUT=''; "sc_$1" full; B=$OUT; }
same() {   # SCENE TITLE GLOB: A == B and A matches GLOB
    twice "$1"
    kt_test_start "$2"
    # shellcheck disable=SC2053
    if [[ $A == "$B" && $A == $3 ]]; then kt_test_pass "$A"; else kt_test_fail "map [$A] full [$B]"; fi
}

kt_test_section "018: a typed letter that cannot react, next to a base match"
# Russian Alt+ф on the US a key; plain ф (its base from the layout tables)
sc_dis() {
    sc_begin
    TButton.new bf 2 2 14 4 '~Ф~айл' cmFile 0
    TButton.new ba 16 2 28 4 '~A~bout' cmAbout 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg bf; fv.views.insert dlg ba; fv.views.insert dlg ok
    sc_open "$1" ok
    bf_data[State]=$(( bf_data[State] | FV_SF_DISABLED ))
    k kbAltA ф a; k kbChar ф
    sc_end
}
same dis "a disabled ~Ф~ button: Alt+ф / ф press ~A~bout (base a)" '*kbAltA/ф>evNothing:ba:cmAbout:*kbChar/ф>evNothing:ba:cmAbout:*'
sc_mask() {
    sc_begin
    TCheckBoxes.new cb 2 6 26 8 '~Ф~ормат' '~B~ig'
    TButton.new ba 16 2 28 4 '~A~bout' cmAbout 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg cb; fv.views.insert dlg ba; fv.views.insert dlg ok
    sc_open "$1" ok
    fv.dialogs.setButtonState cb 1 0
    k kbAltA ф a; k kbChar ф
    VAL[$1]=${cb_data[Value]}
    sc_end
}
same mask "a check box whose ~Ф~ item is off in EnableMask: Alt+ф / ф press ~A~bout" '*kbAltA/ф>evNothing:ba:cmAbout:*kbChar/ф>evNothing:ba:cmAbout:*'
fvw_check "the masked item stays unmarked" 0.0 "${VAL[map]}.${VAL[full]}"
sc_noopt() {
    sc_begin
    TButton.new bf 2 2 14 4 '~Ф~айл' cmFile 0
    TButton.new ba 16 2 28 4 '~A~bout' cmAbout 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg bf; fv.views.insert dlg ba; fv.views.insert dlg ok
    sc_open "$1" ok
    bf_data[Options]=$(( bf_data[Options] & ~(FV_OF_PREPROCESS | FV_OF_POSTPROCESS) ))
    k kbAltA ф a; k kbChar ф
    sc_end
}
same noopt "a ~Ф~ button without ofPreProcess / ofPostProcess (not focused): Alt+ф / ф press ~A~bout" '*kbAltA/ф>evNothing:ba:cmAbout:*kbChar/ф>evNothing:ba:cmAbout:*'
sc_live() {
    sc_begin
    TCheckBoxes.new cb 2 6 26 8 '~Ф~ормат' '~B~ig'
    TButton.new ba 16 2 28 4 '~A~bout' cmAbout 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg cb; fv.views.insert dlg ba; fv.views.insert dlg ok
    sc_open "$1" ok
    fv.dialogs.setButtonState cb 2 0
    k kbAltA ф a
    VAL[$1]=${cb_data[Value]}
    sc_end
}
twice live
kt_test_start "the ~Ф~ item enabled (another one off): the typed match wins over ~A~bout (focus to the check box, the item marked); the full scan asks ~A~bout first in Z order (the designed difference)"
if [[ $A == 'kbAltA/ф>evNothing:cb::phPreProcess:cb;' && ${VAL[map]} == 1 && $B == *':ba:cmAbout:'* ]]; then kt_test_pass "$A"; else kt_test_fail "map [$A] value ${VAL[map]} full [$B]"; fi

kt_test_section "018: nested groups with pre / post"
# inner (ofPreProcess + ofPostProcess) holds a disabled ~A~bout and a plain
# button; the dialog holds ~Ф~айл: the inner group's base pass must not
# leak into the dialog's list
sc_nest() {   # MODE ORDER
    sc_begin
    TGroup.new inner 2 6 40 12
    inner_data[Options]=$(( inner_data[Options] | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    TButton.new ba 1 1 13 3 '~A~bout' cmAbout 0
    TButton.new bo 15 1 25 3 'Other' cmOther 0
    fv.views.insert inner ba; fv.views.insert inner bo
    TButton.new bf 2 2 14 4 '~Ф~айл' cmFile 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    if [ "$NORDER" = 1 ]; then fv.views.insert dlg inner; fv.views.insert dlg bf
    else fv.views.insert dlg bf; fv.views.insert dlg inner; fi
    fv.views.insert dlg ok
    sc_open "$1" ok
    ba_data[State]=$(( ba_data[State] | FV_SF_DISABLED ))
    k kbAltA ф a; k kbChar ф
    sc_end
}
NORDER=1; same nest "the inner group in front of ~Ф~айл: Alt+ф / ф press ~Ф~айл" '*kbAltA/ф>evNothing:bf:cmFile:*kbChar/ф>evNothing:bf:cmFile:*'
NORDER=2; same nest "the inner group behind ~Ф~айл: Alt+ф / ф press ~Ф~айл" '*kbAltA/ф>evNothing:bf:cmFile:*kbChar/ф>evNothing:bf:cmFile:*'
# the same with an enabled inner ~A~bout: the inner group answers in its
# own pass (base) without changing the dialog's
sc_nest2() {
    sc_begin
    TGroup.new inner 2 6 40 12
    inner_data[Options]=$(( inner_data[Options] | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    TButton.new ba 1 1 13 3 '~A~bout' cmAbout 0
    fv.views.insert inner ba
    TButton.new bx 2 2 14 4 '~X~ray' cmXray 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    if [ "$NORDER" = 1 ]; then fv.views.insert dlg inner; fv.views.insert dlg bx
    else fv.views.insert dlg bx; fv.views.insert dlg inner; fi
    fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltA ф a; k kbAltX x
    sc_end
}
NORDER=1; same nest2 "an enabled inner ~A~bout in front: Alt+ф presses it, then Alt+X presses ~X~ray" '*kbAltA/ф>evNothing:ba:cmAbout:*kbAltX/x>evNothing:bx:cmXray:*'
NORDER=2; same nest2 "an enabled inner ~A~bout behind: the same" '*kbAltA/ф>evNothing:ba:cmAbout:*kbAltX/x>evNothing:bx:cmXray:*'
# the dialog's ~Ф~айл behind an inner group holding an enabled ~A~bout: the
# dialog decided typed, so the inner group asks no base key (a typed match
# anywhere wins); a full scan takes the inner ~A~bout, first in Z order
sc_nest3() {
    sc_begin
    TButton.new bf 2 2 14 4 '~Ф~айл' cmFile 0
    TGroup.new inner 2 6 40 12
    inner_data[Options]=$(( inner_data[Options] | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    TButton.new ba 1 1 13 3 '~A~bout' cmAbout 0
    fv.views.insert inner ba
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg bf; fv.views.insert dlg inner; fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltA ф a
    sc_end
}
twice nest3
kt_test_start "~Ф~айл behind an inner group with ~A~bout: Alt+ф presses ~Ф~айл (the typed match wins across the tree; the full scan presses the inner ~A~bout: the designed difference)"
if [[ $A == 'kbAltA/ф>evNothing:bf:cmFile:'* && $B == *':ba:cmAbout:'* ]]; then kt_test_pass "$A"; else kt_test_fail "map [$A] full [$B]"; fi

kt_test_section "018: a subclass the map does not know"
# overrides HandleEvent and calls TButton's body with inherited: never
# mapped, so it asks without the map's pass (as in a full scan)
class TXBtn : TButton
    public
        override proc HandleEvent
end
TXBtn.HandleEvent() { inherited HandleEvent "$@"; }
build TXBtn
sc_over() {
    sc_begin
    TButton.new ba 16 2 28 4 '~A~bout' cmAbout 0
    TXBtn.new xf 2 2 14 4 '~Ф~айл' cmFile 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    if [ "$NORDER" = 1 ]; then fv.views.insert dlg ba; fv.views.insert dlg xf
    else fv.views.insert dlg xf; fv.views.insert dlg ba; fi
    fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltA ф a
    sc_end
}
NORDER=1; same over "a subclass ~Ф~айл in front of ~A~bout: Alt+ф presses the subclass (its typed match, asked without a pass)" 'kbAltA/ф>evNothing:xf:cmFile:*'
NORDER=2; same over "~A~bout in front of the subclass ~Ф~айл: Alt+ф presses ~A~bout, first in Z order" 'kbAltA/ф>evNothing:ba:cmAbout:*'
# the differential's seed 54: the dialog's ~И~ж behind, an inner group with
# a subclass x~b~y, a plain x~b~y in front. Russian Alt+и (US b): the dialog
# decides typed; the subclass, unknown to the map, asks in the typed pass
# too (no base match while a typed one exists)
sc_mixed() {
    sc_begin
    TButton.new vi 2 2 14 4 '~И~ж' cmVi 0
    TGroup.new inner 2 6 40 12
    inner_data[Options]=$(( inner_data[Options] | FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))
    TXBtn.new w0 1 1 13 3 'x~b~y' cmW0 0
    fv.views.insert inner w0
    TButton.new b4 16 2 28 4 'x~b~y' cmB4 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg vi; fv.views.insert dlg inner; fv.views.insert dlg b4; fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltB и b
    sc_end
}
twice mixed
kt_test_start "~И~ж behind, an inner subclass x~b~y and x~b~y in front: Alt+и presses ~И~ж (typed wins; never the subclass by the base key); the full scan presses the front x~b~y"
if [[ $A == 'kbAltB/и>evNothing:vi:cmVi:'* && $B == 'kbAltB/и>evNothing:b4:cmB4:'* ]]; then kt_test_pass "$A"; else kt_test_fail "map [$A] full [$B]"; fi

kt_test_section "018: a typed letter written away directly"
# ~И~ж mapped, then its Title written directly to ~X~ray while unfocused:
# Russian Alt+и must not stay "typed" on the old letter (the base ~B~ig
# reacts, as in a full scan)
sc_stale() {
    sc_begin
    TButton.new bi 2 2 14 4 '~И~ж' cmBi 0
    TButton.new bb 16 2 28 4 '~B~ig' cmBb 0
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg bi; fv.views.insert dlg bb; fv.views.insert dlg ok
    sc_open "$1" ok
    k kbF9
    bi_data[Title]='~X~ray'
    k kbAltB и b; k kbAltX x
    sc_end
}
same stale "~И~ж written to ~X~ray directly: Alt+и presses ~B~ig (base), Alt+X presses ~X~ray" 'kbF9/>*;kbAltB/и>evNothing:bb:cmBb:*;kbAltX/x>evNothing:bi:cmBi:*'

kt_test_section "018: the focus moved during the key"
# a field that, focused, moves the focus to a button on Space without
# handling the key; FV presses a focused button on Space in any phase
class TJump : TView
    public
        override proc HandleEvent
end
TJump.HandleEvent() { if [ "$FV_EV_WHAT" = evKeyDown ] && [ "$FV_EV_KEY" = kbChar ] && [ "$FV_EV_CHAR" = ' ' ]; then fv.views.focus go || :; fi; }
build TJump
sc_jump() {
    sc_begin
    TJump.new j 2 2 20 3
    j_data[Options]=$(( j_data[Options] | FV_OF_SELECTABLE ))
    TButton.new go 2 5 12 7 '~G~o' cmGo 0
    TButton.new ok 30 5 40 7 'O~K~' cmOK 1
    fv.views.insert dlg j; fv.views.insert dlg go; fv.views.insert dlg ok
    sc_open "$1" j
    k kbChar ' '
    sc_end
}
same jump "Space moves the focus to ~G~o in the focused phase: ~G~o pressed in the post phase" '*>evNothing:go:cmGo:phPostProcess:go;'

kt_test_section "018: the Phase a full scan leaves"
# Current a view of yours without pre / post work; two buttons skipped
sc_ph1() {
    sc_begin
    TView.new pv 2 2 10 3
    pv_data[Options]=$(( pv_data[Options] | FV_OF_SELECTABLE ))
    TButton.new b1 2 5 12 7 '~A~a' cmAa 0
    TButton.new b2 14 5 24 7 '~B~b' cmBb 0
    fv.views.insert dlg pv; fv.views.insert dlg b1; fv.views.insert dlg b2
    sc_open "$1" pv
    k kbChar x; k kbF9; k kbAltZ z
    sc_end
}
same ph1 "a key nobody takes (x, F9, Alt+Z) with every widget skipped: phPostProcess" 'kbChar/x>evKeyDown:*:phPostProcess:pv;kbF9/>evKeyDown:*:phPostProcess:pv;kbAltZ/z>evKeyDown:*:phPostProcess:pv;'
# pre-process-only buttons, a disabled Current: only the pre phase calls
sc_ph2() {
    sc_begin
    TView.new pv 2 2 10 3
    pv_data[Options]=$(( pv_data[Options] | FV_OF_SELECTABLE ))
    TButton.new b1 2 5 12 7 '~A~a' cmAa 0
    TButton.new b2 14 5 24 7 '~B~b' cmBb 0
    fv.views.insert dlg pv; fv.views.insert dlg b1; fv.views.insert dlg b2
    sc_open "$1" pv
    b1_data[Options]=$(( b1_data[Options] & ~FV_OF_POSTPROCESS ))
    b2_data[Options]=$(( b2_data[Options] & ~FV_OF_POSTPROCESS ))
    pv_data[State]=$(( pv_data[State] | FV_SF_DISABLED ))
    dlg_data[Phase]=phFocused
    k kbF9
    sc_end
}
same ph2 "pre-process-only buttons skipped, a disabled Current: phPreProcess" 'kbF9/>evKeyDown:*:phPreProcess:pv;'
# a disabled button only: the full scan calls nobody, the Phase stays
sc_ph3() {
    sc_begin
    TView.new pv 2 2 10 3
    pv_data[Options]=$(( pv_data[Options] | FV_OF_SELECTABLE ))
    TButton.new b1 2 5 12 7 '~A~a' cmAa 0
    fv.views.insert dlg pv; fv.views.insert dlg b1
    sc_open "$1" pv
    b1_data[State]=$(( b1_data[State] | FV_SF_DISABLED ))
    k kbF9
    sc_end
}
same ph3 "only a disabled button skipped: phFocused (the full scan never reaches it)" 'kbF9/>evKeyDown:*:phFocused:pv;'

kt_test_section "018: direct writes while unfocused"
sc_items() {
    sc_begin
    TCheckBoxes.new cb 2 6 26 8 '~A~lpha' '~B~eta'
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg cb; fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltA a
    fv.views.select ok
    cb_items[1]='~Z~eta'
    k kbAltZ z; k kbAltB b
    VAL[$1]=${cb_data[Value]}
    sc_end
}
twice items
kt_test_start "a cluster's _items element written directly (the map built before): Alt+Z marks the new item, Alt+B no longer does"
if [[ $A == "$B" && $A == *'kbAltZ/z>evNothing:cb::'*'kbAltB/b>evKeyDown:'* && ${VAL[map]}.${VAL[full]} == 3.3 ]]; then kt_test_pass "$A"; else kt_test_fail "map [$A] value ${VAL[map]}.${VAL[full]} full [$B]"; fi
sc_ltext() {
    sc_begin
    TLabel.new lb 2 5 14 6 '~T~ext' cb
    TCheckBoxes.new cb 2 6 26 8 'one' 'two'
    TButton.new ok 30 2 40 4 'O~K~' cmOK 1
    fv.views.insert dlg lb; fv.views.insert dlg cb; fv.views.insert dlg ok
    sc_open "$1" ok
    k kbAltT t
    fv.views.select ok
    lb_data[Text]='~Q~uery'
    k kbAltQ q; fv.views.select ok; k kbAltT t
    sc_end
}
same ltext "a label's Text written directly: Alt+Q focuses its link, Alt+T no longer does" 'kbAltT/t>evNothing:lb::*:cb;kbAltQ/q>evNothing:lb::*:cb;kbAltT/t>evKeyDown:*:ok;'

kt_test_log "018_HotKeyMap.sh completed"
