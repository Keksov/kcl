#!/usr/bin/env bash
# 011_Data.sh - the data transfer (FV TGroup.GetData / SetData / DataSize;
# design P3 §4.6): one element per data-bearing subview in FV's order
# (insertion order, the back of the list first): a cluster its Value, a
# TParamText its ParamCount parameters, a static text / label / button
# nothing; a subgroup's subviews in place (FV TGroup.DataSize sums them); a
# view of yours takes part with DataSize / GetData / SetData (FV's virtuals,
# here GetData ARRAY INDEX and SetData ARRAY INDEX); setData redraws (==
# a full repaint); refusals: no view, a bad array name, an associative
# array, RESULT kept.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "011: getData / setData"
fvg_modeless
kt_test_start "dataSize: 2 for the test dialog (opts, dir); 1 for a cluster, 0 for a button"
fv.dialogs.dataSize dlg; a=$RESULT; fv.dialogs.dataSize opts; b=$RESULT; fv.dialogs.dataSize ok; c=$RESULT
if [[ $a$b$c == 210 ]]; then kt_test_pass ok; else kt_test_fail "$a $b $c"; fi
kt_test_start "getData: the order is FV's (opts before dir), the array replaced"
opts_data[Value]=5 dir_data[Value]=1
REC=(x y z w); RESULT=keep
fv.dialogs.getData dlg REC
if [[ ${#REC[@]} == 2 && ${REC[0]} == 5 && ${REC[1]} == 1 && $RESULT == keep ]]; then kt_test_pass ok; else kt_test_fail "$(declare -p REC) $RESULT"; fi
kt_test_start "setData: values set, Sel of the radio too, redrawn == a full repaint"
REC=(2 0)
fv.dialogs.setData dlg REC
if [[ ${opts_data[Value]} == 2 && ${dir_data[Value]} == 0 && ${dir_data[Sel]} == 0 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "${opts_data[Value]} ${dir_data[Value]} $FVW_DIFF"; fi
kt_test_start "a value that is no number: 0"
REC=(abc 1); fv.dialogs.setData dlg REC
if [[ ${opts_data[Value]} == 0 && ${dir_data[Value]} == 1 ]]; then kt_test_pass ok; else kt_test_fail "${opts_data[Value]}"; fi

kt_test_section "011: views of yours, subgroups, TParamText"
class TPair : TView
    public
        var A
        var B
        func DataSize
        proc GetData
        proc SetData
end
TPair.DataSize() { RESULT=2; }
TPair.GetData() { local -n r=$1; r[$2]=$A r[$2+1]=$B; }
TPair.SetData() { local -n r=$1; A=${r[$2]} B=${r[$2+1]}; }
build TPair
TPair.new pair 0 0 1 1; pair_data[A]=a pair_data[B]=b
TGroup.new sub 0 0 2 2
TParamText.new ptx 0 0 2 1 '%s' 1
fv.views.insert sub ptx
fv.views.insertBefore dlg pair dlg__fvframe
fv.views.insert dlg sub
kt_test_start "dataSize sums a subgroup's views; a view of yours counts its DataSize"
fv.dialogs.dataSize dlg
if [ "$RESULT" = 5 ]; then kt_test_pass ok; else kt_test_fail "$RESULT"; fi
kt_test_start "getData: pair (behind the frame) first, then opts, dir, then the subgroup's parameter"
ptx_params=(P); opts_data[Value]=3
REC=(); fv.dialogs.getData dlg REC
if [ "${REC[*]}" = 'a b 3 1 P' ]; then kt_test_pass ok; else kt_test_fail "${REC[*]}"; fi
kt_test_start "setData through all of them"
REC=(c d 4 0 Q); fv.dialogs.setData dlg REC
if [[ ${pair_data[A]}${pair_data[B]} == cd && ${opts_data[Value]} == 4 && ${dir_data[Value]} == 0 && ${ptx_params[0]} == Q ]]; then kt_test_pass ok; else kt_test_fail "${pair_data[A]}${pair_data[B]} ${opts_data[Value]} ${ptx_params[*]}"; fi
fv.views.delete dlg sub; sub.delete; fv.views.delete dlg pair; pair.delete

kt_test_section "011: refusals"
kt_test_start "not a view, bad names, an associative array, a wrong count: rc 2, RESULT ''"
declare -A AA=([k]=1)
r=''
for args in "nope REC" "dlg 1bad" "dlg RESULT" "dlg __fvx" "dlg _fvg_t" "dlg AA"; do
    rc=0; eval "fv.dialogs.getData $args" || rc=$?; r+="$rc${RESULT:-.} "
done
rc=0; fv.dialogs.setData dlg || rc=$?; r+="$rc "
rc=0; fv.dialogs.dataSize || rc=$?; r+="$rc"
if [ "$r" = '2. 2. 2. 2. 2. 2. 2 2' ]; then kt_test_pass ok; else kt_test_fail "[$r]"; fi
fvg_unscene
