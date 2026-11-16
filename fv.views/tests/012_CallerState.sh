#!/usr/bin/env bash
# 012_CallerState.sh - the caller's shell state neither changes what this
# stage's calls do nor is changed by them: one scripted scene (views whose
# names differ only in case: Win / win, Lab / lab; insert, insertBefore,
# makeFirst, putInFrontOf, the navigation, locate / moveTo / growTo,
# changeBounds with GrowMode, makeLocal / makeGlobal / mouseInView,
# GetHelpCtx, refusals on every return path, delete and .delete, and at the
# end the constructor guard: a live leaf re-created -> refused with its Error
# line, the tree repaired, insert refusing the bare instance, .delete)
# runs in a child shell under each setup - nocasematch, failglob, nullglob,
# noglob, extglob on and off, globasciiranges off, odd IFS values (digits,
# '-', letters, empty), set -eu with pipefail, a C locale, all at once - and
# must give the reference output; the setup's options, IFS and locale are the
# same after the scene as before. The views are created before the setup
# (kklass's own `.new` is not part of this unit; under an IFS of letters it
# crashes bash, a kklass finding), the calls run after it; the guard part
# needs `.new` and is skipped (and left out of the comparison) under the
# IFS of letters only.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "012: the caller's shell state"

UNIT="$FVW_TESTS_DIR/../fv.views.sh"
STATE='printf "%s|" "$(shopt -p nocasematch failglob nullglob extglob globasciiranges)" "$-" "${IFS@Q}" "${LC_ALL-unset}"'
MAKE='
TGroup.new desk 0 1 80 24
TGroup.new Win 0 0 40 20
TGroup.new win 40 0 80 20
TView.new Lab 1 1 10 2
TView.new lab 2 2 12 3
TView.new st 0 22 80 23
'
SCENE='
r=""
Win_data[GrowMode]=$FV_GF_GROWALL win_data[GrowMode]=$(( FV_GF_GROWLOX | FV_GF_GROWHIY | FV_GF_GROWREL ))
lab_data[Options]=$FV_OF_SELECTABLE lab_data[HelpCtx]=17
fv.views.insert desk Win; fv.views.insert desk win; fv.views.insertBefore desk st ""
fv.views.insert Win Lab; fv.views.insert Win lab
fvw_tree desk; r+="$REPLY;"
fv.views.makeFirst Win; fv.views.putInFrontOf win Win; fv.views.putInFrontOf Lab lab
fvw_tree desk; r+="$REPLY;"
fv.views.first desk; r+="$RESULT,"; fv.views.last desk; r+="$RESULT,"
fv.views.next Win; r+="$RESULT,"; fv.views.prev Win; r+="$RESULT,"
fv.views.nextView st || r+="nil$?,"; fv.views.prevView win || r+="nil$?;"
fv.views.locate Win -3 2 30 18; fv.views.moveTo Win 1 2; fv.views.growTo Win 33 17
fv.views.changeBounds desk 0 1 120 40
for v in Win win Lab lab st; do fv.views.getBounds "$v"; r+="$v=$RESULT,"; done
r+="abs=${__FV_VW_AX[lab]}:${__FV_VW_AY[lab]}:${__FV_VW_C3[lab]}:${__FV_VW_C4[lab]};"
fv.views.makeLocal lab 20 20; r+="$RESULT,"; fv.views.makeGlobal Lab 0 0; r+="$RESULT,"
if fv.views.mouseInView lab "${__FV_VW_AX[lab]}" "${__FV_VW_AY[lab]}"; then r+=in,; fi
if ! fv.views.mouseInView Lab 0 0; then r+=out,; fi
RESULT=x; Win.GetHelpCtx; r+="help=$RESULT;"
fv.views.insert desk Lab || r+="$?,"
fv.views.insert nosuch Lab || r+="$?,"
fv.views.delete win Lab || r+="$?,"
fv.views.moveTo Win "1*" 2 || r+="$?,"
fv.views.locate Win "a[0]" 0 0 0 || r+="$?,"
fv.views.putInFrontOf Lab win || r+="$?,"
fv.views.first st || r+="$?;"
fv.views.delete Win lab; fvw_tree desk; r+="$REPLY;"
lab.delete; Win.delete
fvw_tree desk; r+="$REPLY"
# the constructor guard: st (a live leaf in desk) re-created -> refused, the
# tree repaired, insert refuses the bare instance, .delete frees it. Not run
# where the .new of kklass cannot (NOKKNEW: an IFS of letters, see the header)
if [[ -z ${NOKKNEW-} ]]; then
    r+="|G="
    TView.new st 0 0 1 1 2>"$GERR" || r+="$?,"
    IFS= read -r l < "$GERR" || :
    if [[ $l == "Error: fv.views: TView.Create: "?st?" is a live view"* ]]; then r+="E,"; fi
    fvw_tree desk; r+="$REPLY,"
    fv.views.insert desk st 2>/dev/null || r+="$?,"
    if st.delete; then r+=del; fi
    fv.views.isView st || r+=",gone"
fi
printf "%s" "$r"
'
TREEFN=$(declare -f fvw_tree)
run() {   # SETUP -> OUT = before-state # scene output # after-state
    OUT=$("$BASH" -c "unset LC_ALL LC_CTYPE LANG; export LC_ALL=C.UTF-8
$TREEFN
GERR='$FVW_TMP/guard.err'
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
# win: gfGrowLoX + gfGrowHiY + gfGrowRel: AX (40*120 + 80 shr 1) div 80 = 60,
# BY (20*39 + 23 shr 1) div 23 = 34; Win: gfGrowAll, +40 / +16
want='desk[st {Win[Lab lab]*lab} {win[]}]*win;desk[st {Win[lab Lab]*lab} {win[]}]*win;win,st,st,win,nil1,nil1;'
want+='Win=41 18 74 35,win=60 0 80 34,Lab=1 1 10 2,lab=2 2 12 3,st=0 22 80 23,abs=43:21:53:22;-23 -1,42 20,in,out,help=17;'
want+='1,2,1,2,2,1,2;desk[st {Win[Lab]} {win[]}]*win;desk[st {win[]}]*win|G=1,E,desk[{win[]}]*win,2,del,gone'
if [[ $ref == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$ref] want [$want]"; fi

# (an IFS of letters: kklass's .new crashes bash, so that setup skips the
# guard part (NOKKNEW) and is compared without it)
for setup in 'shopt -s nocasematch' 'shopt -s failglob' 'shopt -s nullglob' 'set -f' 'shopt -s extglob' 'shopt -u extglob' \
    'shopt -u globasciiranges' "IFS='0123456789 '" "IFS='-'" "NOKKNEW=1; IFS='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.'" 'IFS=' \
    'set -eu -o pipefail' 'export LC_ALL=C' \
    "shopt -s nocasematch failglob nullglob extglob; shopt -u globasciiranges; set -f -eu; IFS='-0123456789Ww'; export LC_ALL=C"; do
    kt_test_start "same output and the state kept: $setup"
    run "$setup"
    got=${OUT#*#} got=${got%#*}
    before=${OUT%%#*} after=${OUT##*#}
    want=$ref
    if [[ $setup == NOKKNEW=1* ]]; then want=${ref%|G=*}; fi
    if [[ $got == "$want" && $before == "$after" ]]; then kt_test_pass "ok"
    else kt_test_fail "output [$got] vs [$want]; state before [$before] after [$after]"; fi
done

kt_test_log "012_CallerState.sh completed"
