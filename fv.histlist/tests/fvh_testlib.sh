#!/usr/bin/env bash
# fvh_testlib.sh — what the fv.histlist test files share. Not a test file (the
# ktests runner picks up NNN_*.sh only).
#
#   fvh_init NAME "$@"   ktest init + the unit + a scratch folder ($FVH_TMP)
#   fvh_forks LINE       rc 0 when a code line holds a construct that forks
#                        (fv.video's 006 scanner, fvv_forks, read from its
#                        test lib as fv.views' fvw_forks does)
#   The model (FV HistList's block, one record list for all ids, newest
#   first): fvh_mreset CAP; fvh_madd ID TEXT; fvh_mclear; fvh_mlist ID ->
#   REPLY = the id's strings newest first, joined by \x1f
#   fvh_list ID          REPLY = the unit's strings of ID the same way
#   fvh_bytes TEXT       REPLY = TEXT's UTF-8 bytes (LC_ALL=C)

FVH_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FVH_TESTS_DIR/../../../ktests/ktest.sh"

fvh_init() {
    local name=$1
    shift
    source "$FVH_TESTS_DIR/../fv.histlist.sh"
    kt_test_init "$name" "$FVH_TESTS_DIR" "$@"
    FVH_TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
}

fvh_forks() {
    if ! declare -F fvv_forks >/dev/null; then
        local l src='' on=0
        while IFS= read -r l || [[ -n $l ]]; do
            if [[ $l == 'fvv_forks() {' ]]; then on=1; fi
            if (( on )); then src+=$l$'\n'; fi
            if (( on )) && [[ $l == '}' ]]; then break; fi
        done < "$FVH_TESTS_DIR/../../fv.video/tests/fvv_testlib.sh"
        eval "$src"
    fi
    fvv_forks "$1"
}

fvh_bytes() {
    local LC_ALL=C
    REPLY=${#1}
}
# the model: FVH_MI / FVH_MT / FVH_MS = id, text, record size per record,
# newest first; FVH_MU = the bytes used (FV's HistoryUsed), FVH_MC the cap
fvh_mreset() { FVH_MI=() FVH_MT=() FVH_MS=() FVH_MU=1 FVH_MC=${1:-65536}; }
fvh_mclear() { FVH_MI=() FVH_MT=() FVH_MS=() FVH_MU=1; }
fvh_madd() {
    local id=$1 t=$2 b s i
    local -a ni=() nt=() ns=()
    [[ -n $t ]] || return 0
    fvh_bytes "$t"; b=$REPLY
    s=$(( b + 2 + (b < 128 ? 1 : b < 16384 ? 2 : b < 2097152 ? 3 : 4) ))
    (( s <= FVH_MC - 1 )) || return 0
    # (FV HistoryAdd: the duplicates of the id deleted, then InsertString)
    for (( i = 0; i < ${#FVH_MI[@]}; i++ )); do
        if [[ ${FVH_MI[i]} == "$id" ]] && [ "${FVH_MT[i]}" = "$t" ]; then FVH_MU=$(( FVH_MU - FVH_MS[i] )); continue; fi
        ni+=("${FVH_MI[i]}") nt+=("${FVH_MT[i]}") ns+=("${FVH_MS[i]}")
    done
    FVH_MI=("${ni[@]}") FVH_MT=("${nt[@]}") FVH_MS=("${ns[@]}")
    while (( FVH_MU + s > FVH_MC )); do
        i=$(( ${#FVH_MI[@]} - 1 ))
        FVH_MU=$(( FVH_MU - FVH_MS[i] ))
        unset 'FVH_MI[i]' 'FVH_MT[i]' 'FVH_MS[i]'
    done
    FVH_MI=("$id" "${FVH_MI[@]}") FVH_MT=("$t" "${FVH_MT[@]}") FVH_MS=("$s" "${FVH_MS[@]}")
    FVH_MU=$(( FVH_MU + s ))
}
fvh_mlist() {
    local i
    REPLY=''
    for (( i = 0; i < ${#FVH_MI[@]}; i++ )); do
        if [[ ${FVH_MI[i]} == "$1" ]]; then REPLY+=${FVH_MT[i]}$'\x1f'; fi
    done
}
fvh_list() {
    local i n
    REPLY=''
    fv.histlist.historyCount "$1"; n=$RESULT
    for (( i = 0; i < n; i++ )); do
        fv.histlist.historyStr "$1" "$i"
        REPLY+=$RESULT$'\x1f'
    done
}
