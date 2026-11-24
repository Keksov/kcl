#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.histlist.sh}../../kbool.sh" || return
kk.unit fv.histlist || return $__kk_unit_rc

# fv.histlist — Free Vision's HistList unit for the fv.* text UI (layer L3,
# P3 stage 3h, design kcl/docs/dev/fv/P3_DESIGN.md §15, D28): the input
# history store THistory records into and THistoryViewer shows. Plain
# functions, no classes, no forks; API and deviations: README.md.
#
#   fv.histlist.historyAdd ID TEXT    FV HistoryAdd: TEXT becomes the newest
#                                     string of list ID (a copy already there
#                                     moves to the front); '' is not added
#   fv.histlist.historyCount ID       FV HistoryCount: RESULT = the count
#   fv.histlist.historyStr ID INDEX   FV HistoryStr: RESULT = string INDEX
#                                     (0 = the newest); rc 1 + '' past the end
#   fv.histlist.clearHistory          FV ClearHistory: every list emptied
#
# ID: 0-255 (FV: a Byte). Per process, not saved (FV keeps it in memory too:
# Load/StoreHistory are not ported). One store for all ids, as FV's
# HistoryBlock: FV_HISTORY_SIZE bytes (FV HistorySize, default 65536) shared
# by every list, each string taking FV_UNICODE's record (its UTF-8 bytes +
# the length's ULEB128 bytes + 2); a string that does not fit drops the
# OLDEST strings of the whole store (FV InsertString).
#
# Answers (the kcl house style for plain functions, as fv.dialogs.getText):
# the getters answer in RESULT, the procedures keep it; a malformed call (an
# ID that is not 0-255, an INDEX that is not digits, a wrong argument count)
# is rc 2 with RESULT='' and a kk.debug line; historyStr past the last string
# is rc 1 with RESULT='' (FV answers '').
#
# Conventions: locals `__fvh_*` (fv.drivers has __fvd_), globals __FV_HL_*;
# fork-free and set -eu clean; strings compared with `[ "$a" = "$b" ]`
# (byte-exact whatever nocasematch says); the byte count of a non-ASCII
# string in a UTF-8 caller under a local LC_ALL=C (kcl/README §1.6).
#
# State (kept across a reload; the first load in a process starts empty and
# drops any __FV_HL_* the environment brought):
#   __FV_HL_T<ID>  list ID's strings, newest first (an indexed array)
#   __FV_HL_Q<ID>  their sequence numbers, in the same order
#   __FV_HL_ID[S]  the list of the string with sequence number S, and
#   __FV_HL_SZ[S]  its record size (sparse; element 0 a sentinel)
#   __FV_HL_SEQ    the next sequence number; __FV_HL_LO the oldest that may
#                  still be live; __FV_HL_USED the bytes in use (FV's
#                  HistoryUsed: 1 for the empty store)

# the settings hook (kkore kk.settings): the kcl locale default and a
# caller's FV_HISTORY_SIZE (described below)
fv.histlist._settings() {
    kk.localeDefault
    declare -g FV_HISTORY_SIZE=${FV_HISTORY_SIZE:-65536}
    return 0
}
kk.settings fv.histlist._settings LC_CTYPE FV_HISTORY_SIZE || return

# (the first load in this process: a sentinel-marked array is ours)
fv.histlist._load() {
    local __fvh_v IFS=' '
    if [[ ${__FV_HL_ID[@]@a} != a* ]]; then
        # (the names are identifiers: no glob character to expand)
        for __fvh_v in ${!__FV_HL_*}; do unset -v "$__fvh_v" 2>/dev/null || :; done
        declare -ga __FV_HL_ID=(-) __FV_HL_SZ=(0)
        declare -g __FV_HL_SEQ=1 __FV_HL_LO=1 __FV_HL_USED=1
    fi
}
fv.histlist._load
# FV_HISTORY_SIZE: FV's HistorySize (bytes of the whole store); read at each
# historyAdd: digits (1-9 of them), else 65536. A smaller value set later
# drops the oldest strings at the next historyAdd (its default, 65536 when
# unset or empty, is set by the settings hook above)
# the probe: one character in a UTF-8 caller, two bytes in a C-locale one
declare -g __FV_HL_P=$'\xd0\xb6'

# fv.histlist._bad CALLER MSG — a malformed call: RESULT='', a debug line, rc 2
fv.histlist._bad() {
    RESULT=''
    kk.debug "Error: fv.histlist.$1: $2"
    return 2
}
# fv.histlist._id ID CALLER — the caller's __fvh_id = ID as a number when it
# is 0-255 (plain digits); else _bad's rc 2
fv.histlist._id() {
    if [[ -n $1 && $1 != *[!0123456789]* && ${#1} -le 3 ]] && (( 10#$1 <= 255 )); then __fvh_id=$(( 10#$1 )); return 0; fi
    fv.histlist._bad "$2" "ID must be 0-255 (got: '$1')"
}
# fv.histlist._size TEXT — the caller's __fvh_sz = TEXT's record: its UTF-8
# bytes, the ULEB128 bytes of that length, 2 (FV_UNICODE's InsertString)
fv.histlist._size() {
    local __fvh_b=${#1}
    if [[ $1 == *[![:ascii:]]* ]] && (( ${#__FV_HL_P} == 1 )); then fv.histlist._bytes "$1"; fi
    __fvh_sz=$(( __fvh_b + 3 ))
    if (( __fvh_b >= 128 )); then __fvh_sz=$(( __fvh_sz + 1 )); fi
    if (( __fvh_b >= 16384 )); then __fvh_sz=$(( __fvh_sz + 1 )); fi
    if (( __fvh_b >= 2097152 )); then __fvh_sz=$(( __fvh_sz + 1 )); fi
}
# (a non-ASCII text in a UTF-8 caller: its bytes, the caller's __fvh_b)
fv.histlist._bytes() {
    local LC_ALL=C
    __fvh_b=${#1}
}
# fv.histlist._drop ID K — string K of list ID (- = its oldest) out of the
# store (its record freed, its sequence number forgotten; the lists compacted)
fv.histlist._drop() {
    local -n __fvh_dt=__FV_HL_T$1 __fvh_dq=__FV_HL_Q$1
    local __fvh_k=$2 __fvh_s
    if [ "$__fvh_k" = - ]; then __fvh_k=$(( ${#__fvh_dt[@]} - 1 )); fi
    __fvh_s=${__fvh_dq[__fvh_k]}
    __FV_HL_USED=$(( __FV_HL_USED - ${__FV_HL_SZ[__fvh_s]:-0} ))
    unset '__FV_HL_ID[__fvh_s]' '__FV_HL_SZ[__fvh_s]' '__fvh_dt[__fvh_k]' '__fvh_dq[__fvh_k]'
    if (( __fvh_k < ${#__fvh_dt[@]} )); then __fvh_dt=("${__fvh_dt[@]}") __fvh_dq=("${__fvh_dq[@]}"); fi
}

# fv.histlist.historyAdd ID TEXT — FV HistoryAdd: '' is not added; a copy of
# TEXT in list ID is deleted (FV: every duplicate), the oldest strings of the
# store dropped until TEXT's record fits FV_HISTORY_SIZE, TEXT inserted as
# list ID's newest string. A TEXT whose record alone does not fit the store
# is not added (FV_UNICODE would loop). RESULT kept; rc 2: a malformed call
fv.histlist.historyAdd() {
    if (( $# != 2 )); then fv.histlist._bad "${FUNCNAME#fv.histlist.}" 'wrong argument count'; return; fi
    local __fvh_id __fvh_sz __fvh_i __fvh_n __fvh_c=${FV_HISTORY_SIZE-}
    fv.histlist._id "$1" historyAdd || return
    if [[ -z $2 ]]; then return 0; fi
    local -n __fvh_t=__FV_HL_T$__fvh_id __fvh_q=__FV_HL_Q$__fvh_id
    if [[ -z $__fvh_c || $__fvh_c == *[!0123456789]* || ${#__fvh_c} -gt 9 ]]; then __fvh_c=65536; fi
    __fvh_c=$(( 10#$__fvh_c ))
    # (the list's newest string again — a focus release, a button press: it
    # only becomes the store's youngest record, as FV's delete + insert)
    if [[ -n ${__fvh_t[0]+x} ]] && [ "${__fvh_t[0]}" = "$2" ] && (( __FV_HL_USED <= __fvh_c )); then
        __fvh_i=${__fvh_q[0]}
        __FV_HL_ID[__FV_HL_SEQ]=$__fvh_id __FV_HL_SZ[__FV_HL_SEQ]=${__FV_HL_SZ[__fvh_i]} __fvh_q[0]=$__FV_HL_SEQ
        unset '__FV_HL_ID[__fvh_i]' '__FV_HL_SZ[__fvh_i]'
        __FV_HL_SEQ=$(( __FV_HL_SEQ + 1 ))
        return 0
    fi
    fv.histlist._size "$2"
    if (( __fvh_sz > __fvh_c - 1 )); then return 0; fi
    if [[ -z ${__fvh_t[0]+x} ]]; then __fvh_t=() __fvh_q=(); fi
    __fvh_n=${#__fvh_t[@]}
    for (( __fvh_i = 0; __fvh_i < __fvh_n; __fvh_i++ )); do
        if [ "${__fvh_t[__fvh_i]}" = "$2" ]; then fv.histlist._drop "$__fvh_id" "$__fvh_i"; break; fi
    done
    # (FV: the oldest records go until the new one fits)
    while (( __FV_HL_USED + __fvh_sz > __fvh_c && __FV_HL_LO < __FV_HL_SEQ )); do
        if [[ -z ${__FV_HL_ID[__FV_HL_LO]+x} ]]; then __FV_HL_LO=$(( __FV_HL_LO + 1 )); continue; fi
        # (the store's oldest string is the oldest of its list)
        fv.histlist._drop "${__FV_HL_ID[__FV_HL_LO]}" -
        __FV_HL_LO=$(( __FV_HL_LO + 1 ))
    done
    __fvh_t=("$2" "${__fvh_t[@]}") __fvh_q=("$__FV_HL_SEQ" "${__fvh_q[@]}")
    __FV_HL_ID[__FV_HL_SEQ]=$__fvh_id __FV_HL_SZ[__FV_HL_SEQ]=$__fvh_sz
    __FV_HL_USED=$(( __FV_HL_USED + __fvh_sz )) __FV_HL_SEQ=$(( __FV_HL_SEQ + 1 ))
    return 0
}

# fv.histlist.historyCount ID — FV HistoryCount: RESULT = the strings of
# list ID. rc 2: a malformed call
fv.histlist.historyCount() {
    if (( $# != 1 )); then fv.histlist._bad "${FUNCNAME#fv.histlist.}" 'wrong argument count'; return; fi
    local __fvh_id
    fv.histlist._id "$1" historyCount || return
    local -n __fvh_t=__FV_HL_T$__fvh_id
    RESULT=0
    if [[ -n ${__fvh_t[0]+x} ]]; then RESULT=${#__fvh_t[@]}; fi
}

# fv.histlist.historyStr ID INDEX — FV HistoryStr: RESULT = string INDEX of
# list ID (0 = the newest); rc 1 and RESULT='' when the list has no string
# INDEX (FV: ''). rc 2: a malformed call (INDEX not digits)
fv.histlist.historyStr() {
    if (( $# != 2 )); then fv.histlist._bad "${FUNCNAME#fv.histlist.}" 'wrong argument count'; return; fi
    local __fvh_id
    fv.histlist._id "$1" historyStr || return
    if [[ -z $2 || $2 == *[!0123456789]* || ${#2} -gt 9 ]]; then fv.histlist._bad historyStr "INDEX must be digits (got: '$2')"; return; fi
    local -n __fvh_t=__FV_HL_T$__fvh_id
    RESULT=''
    if [[ -z ${__fvh_t[10#$2]+x} ]]; then return 1; fi
    RESULT=${__fvh_t[10#$2]}
}

# fv.histlist.clearHistory — FV ClearHistory: every list emptied, the store
# back to its empty state (HistoryUsed 1). RESULT kept
fv.histlist.clearHistory() {
    if (( $# != 0 )); then fv.histlist._bad "${FUNCNAME#fv.histlist.}" 'wrong argument count'; return; fi
    local __fvh_s
    # (every live string's list, once per sequence number: no name listing)
    for __fvh_s in "${!__FV_HL_ID[@]}"; do
        if (( __fvh_s > 0 )); then unset "__FV_HL_T${__FV_HL_ID[__fvh_s]}" "__FV_HL_Q${__FV_HL_ID[__fvh_s]}"; fi
    done
    __FV_HL_ID=(-) __FV_HL_SZ=(0) __FV_HL_LO=$__FV_HL_SEQ __FV_HL_USED=1
    return 0
}
