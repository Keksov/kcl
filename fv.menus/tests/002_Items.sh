#!/usr/bin/env bash
# 002_Items.sh - TStatusLine's defs and items (FV TStatusDef / TStatusItem,
# NewStatusDef / NewStatusKey, FindItems): the constructor's FV defaults
# (ofPreProcess, EventMask + evBroadcast, GrowMode gfGrowLoY + HiX + HiY),
# the constructor list (`def MIN MAX` + TEXT KEY CMD triples, an implicit
# def 0..65535, a triple whose text is `def`), the per-instance arrays and
# the key map (a chain for a key used twice in a def, key-only and
# click-only items), addDef / addItem (also on an empty line, the method
# aliases), FindItems by HelpCtx (the first def that holds it, none),
# refusals (a malformed list: rc 2, one Error line, NAME no view; bad
# keys / commands / numbers / argument counts, not a status line), the
# destructor freeing the arrays, the re-creation guard.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvm_testlib.sh"
fvm_init "$(basename "$0" .sh)" "$@"

kt_test_section "002: defs and items"

fvm_mkst st 0 23 80 24
fvw_check "the constructor: FV TStatusLine.Init's options, mask and grow mode" \
    "16 785 14 0 0" "${st_data[Options]} ${st_data[EventMask]} ${st_data[GrowMode]} ${st_data[HelpCtx]} ${__FV_MN_CUR[st]}"
fvw_check "the defs: ranges and first items" "0 100|99 199|0 4" "${st_sdmin[*]}|${st_sdmax[*]}|${st_sdfirst[*]}"
fvw_check "the items: texts, keys, commands" \
    "~Alt+X~ Exit,~F10~ Menu,,~F5~ Zoom,~F1~ Help,~Esc~ Cancel|kbAltX kbF10 kbF6 kbF5 kbF1 kbEsc|cmQuit cmMenu cmNext cmZoom cmHelp cmCancel" \
    "$(IFS=,; printf '%s' "${st_sitext[*]}")|${st_sikey[*]}|${st_sicmd[*]}"
km=''
for k in 0:kbAltX 0:kbF10 0:kbF6 0:kbF5 1:kbF1 1:kbEsc 0:kbF1 1:kbF10; do km+="$k=${st_skey[$k]-none},"; done
fvw_check "the key map per def: DEF:KEY -> the item; another def's key is not in it" \
    "0:kbAltX=0,0:kbF10=1,0:kbF6=2,0:kbF5=3,1:kbF1=4,1:kbEsc=5,0:kbF1=none,1:kbF10=none," "$km"
st.delete

TStatusLine.new s2 0 0 40 1 'one' kbF2 cmA '' kbF2 cmB 'click' '' cmC def 5 9 def kbF9 cmD def 7 7
fvw_check "triples before a def: the implicit def 0..65535; 'def kbF9 cmD' is an item; a key twice in a def chains" \
    "0 5 7|65535 9 7|0 3 4|one,,click,def|kbF2 kbF2  kbF9|cmA cmB cmC cmD|0|1 -1" \
    "${s2_sdmin[*]}|${s2_sdmax[*]}|${s2_sdfirst[*]}|$(IFS=,; printf '%s' "${s2_sitext[*]}")|${s2_sikey[*]}|${s2_sicmd[*]}|${s2_skey[0:kbF2]}|${s2_sinext[0]} ${s2_sinext[1]}"
fvw_check "a click-only item (KEY '') is not in the key map (2 keys: kbF2, kbF9)" "2" "${#s2_skey[@]}"

# FindItems: the first def whose range holds HelpCtx
s2_data[HelpCtx]=7; fv.menus._findItems s2; a=${__FV_MN_CUR[s2]}
TStatusLine.new s3 0 0 40 1 def 5 9 'a' kbF2 cmA def 7 7 'b' kbF3 cmB
s3_data[HelpCtx]=7; fv.menus._findItems s3; b=${__FV_MN_CUR[s3]}
s3_data[HelpCtx]=10; fv.menus._findItems s3; c=${__FV_MN_CUR[s3]}
s3_data[HelpCtx]=4; fv.menus._findItems s3; d=${__FV_MN_CUR[s3]}
fvw_check "FindItems: the first def holding HelpCtx (7 in 0..65535 / 5..9 before 7..7), none -> -1" "0 0 -1 -1" "$a $b $c $d"
s2.delete

# addDef / addItem
TStatusLine.new e 0 0 40 1
fvw_check "an empty line: no def, no items" "0 0 -1" "${#e_sdmin[@]} ${#e_sitext[@]} ${__FV_MN_CUR[e]}"
RESULT=keep
fv.menus.addItem e '~F2~ Save' kbF2 cmSave; r1=$?
fvw_check "addItem on an empty line: the implicit def, the item, RESULT kept" "0:0 65535 0:~F2~ Save:0:keep" "$r1:${e_sdmin[*]} ${e_sdmax[*]} ${e_sdfirst[*]}:${e_sitext[0]}:${__FV_MN_CUR[e]}:$RESULT"
e.AddDef 10 20; e.AddItem 'x' kbF2 cmX; e.AddItem '' kbF2 cmY
fvw_check "the aliases AddDef / AddItem: items go to the last def; the key map per def" \
    "0 10|0 1|1 2 -1|0" "${e_sdmin[*]}|${e_sdfirst[*]}|${e_skey[1:kbF2]} ${e_sinext[1]} ${e_sinext[2]}|${e_skey[0:kbF2]}"
e_data[HelpCtx]=15; fv.menus._findItems e
fvw_check "FindItems: the implicit def 0..65535 comes first and still holds 15 (FV order)" "0" "${__FV_MN_CUR[e]}"

# refusals
bad=''
fv.menus.addItem e x F2 cmA || bad+="$?,"
fv.menus.addItem e x kb cmA || bad+="$?,"
fv.menus.addItem e x kbF-2 cmA || bad+="$?,"
fv.menus.addItem e x kbF2 '' || bad+="$?,"
fv.menus.addItem e x kbF2 'cm X' || bad+="$?,"
fv.menus.addItem e x kbF2 || bad+="$?,"
fv.menus.addDef e 1 || bad+="$?,"
fv.menus.addDef e -1 5 || bad+="$?,"
fv.menus.addDef e 1 x || bad+="$?,"
fv.menus.addDef e 1 1234567890 || bad+="$?,"
fv.menus.addDef nosuch 1 2 || bad+="$?,"
TView.new plain 0 0 1 1
fv.menus.addItem plain x kbF2 cmA || bad+="$?,"
fv.menus.update plain || bad+="$?,"
fv.menus.update || bad+="$?"
fvw_check "refusals: bad keys, commands, numbers, argument counts, not a status line (rc 2)" "2,2,2,2,2,2,2,2,2,2,2,2,2,2" "$bad"
fvw_check "the refusals changed nothing" "2|3" "${#e_sdmin[@]}|${#e_sitext[@]}"
plain.delete

kt_test_start "a malformed constructor list: rc 2, one Error line, NAME is no view, nothing kept"
out=''
for args in "'x' kbF2" "'x' F2 cmA" "'x' kbF2 'c m'" "def 1 2 'x'"; do
    eval "TStatusLine.new m 0 0 10 1 $args" 2>"$FVW_TMP/m.err"; rc=$?
    n=0; while IFS= read -r l; do n=$(( n + 1 )); [[ $l == "Error: fv.menus: TStatusLine.Create: 'm': "* ]] || n=99; done < "$FVW_TMP/m.err"
    fv.views.isView m && out+=live
    out+="$rc:$n:${__FV_MN_CUR[m]-unset}:${m_sitext[*]-unset},"
    m.delete
done
if [[ $out == "2:1:unset:unset,2:1:unset:unset,2:1:unset:unset,2:1:unset:unset," ]]; then kt_test_pass "ok"; else kt_test_fail "$out"; fi

# the destructor frees what the line made (kcl §1.9)
e.delete
kt_test_start "the destructor frees the per-instance arrays and entries"
left=''
for v in e_sdmin e_sdmax e_sdfirst e_sitext e_sikey e_sicmd e_sinext e_siplain e_sipat e_skey; do [[ -n ${!v+x} ]] && left+=" $v"; declare -p "$v" >/dev/null 2>&1 && left+=" decl:$v"; done
for a in __FV_MN_CUR __FV_MN_GREY __FV_MN_HINT __FV_MN_AM; do t="$a[e]"; [[ -n ${!t+x} ]] && left+=" $t"; done
if [[ -z $left ]]; then kt_test_pass "ok"; else kt_test_fail "left:$left"; fi
TStatusLine.new e 0 0 40 1
fvw_check "a new line under the same name starts empty" "0 0 -1" "${#e_sdmin[@]} ${#e_sitext[@]} ${__FV_MN_CUR[e]}"
e.delete

# the constructor guard: a live status line re-created
TGroup.new g 0 0 80 24
fvm_mkst sg 0 23 80 24
fv.views.insert g sg
TStatusLine.new sg 0 0 10 1 'z' kbF2 cmZ 2>"$FVW_TMP/g.err"; rc=$?
IFS= read -r l < "$FVW_TMP/g.err" || :
fvw_tree g
gone=''; [[ -z ${__FV_MN_CUR[sg]+x} && -z ${sg_sitext+x} ]] && gone=freed
fvw_check "re-creating a live status line: TView's guard (rc 1, Error, the tree repaired), its arrays freed" \
    "1|g[]|freed|Error:" "$rc|$REPLY|$gone|${l:0:6}"
sg.delete
fv.views.isView sg || fvw_check "the bare instance deleted" ok ok
g.delete

kt_test_log "002_Items.sh completed"
