#!/bin/bash

# ===========================================================================
# tarray — a bash port of FPC rtl-generics TArrayHelper<T>
#          (kcl static class operating on caller-named INDEXED arrays).
#
# Source of truth: FPC generics.collections.pas — TCustomArrayHelper<T> /
# TArrayHelper<T>. Delphi System.Generics.Collections.TArray is the same API
# household. Plan/ledger: kcl/tarray/PLAN.md, kcl/tarray/tarray_ledger.json.
#
# ---- FPC seed (P0, 2026-07-12): a real one EXISTS -------------------------
# packages/rtl-generics/tests/tests.generics.arrayhelper.pas is a dedicated
# fpcunit test (BinarySearch/IndexOf/First/Last/Min/Max/Contains/Reverse) — it
# is the parity ORACLE, mined in tests/00X_FpcParity.sh. (NB: it has NO Sort
# test; sort parity = the sorted-invariant + hand matrices.) Fixture used
# throughout: a = (1 3 5 7 9 11 13 15 20).
#
# ---- Pinned semantics (P0 — from the impl + the FPC test) -----------------
#   S1 BinarySearch on empty -> found=false, FoundIndex=-1, CandidateIndex=-1,
#      CompareResult=0 (impl :1231-1237; test Test_BinarySearch_EmptyArray).
#   S2 BinarySearch loop compares Compare(AValues[mid], AItem) (ARRAY-first!):
#      <0 -> go right, >=0 -> go left, =0 -> found. CandidateIndex = the
#      convergence index imin; RESULT_COMPARE = sign(array[candidate] - item);
#      a MISS's candidate is the insertion point. Test: search 10 in the
#      fixture -> candidate 5, found -1, compare>0 (array[5]=11 > 10); search
#      20 -> candidate 8, found 8, compare 0 (impl :1243-1292).
#   S3 IndexOf == FirstIndexOf (first occurrence); LastIndexOf = last (impl
#      :1371; test 9 -> 4 first / 7 last in (1 3 5 7 9 11 13 9 20)).
#   S4 Reverse(src,dst) builds via a TEMP buffer, so src==dst (in-place) is
#      SAFE; Reverse(a,b) leaves a untouched, b = reversed a (impl :1324-1339).
#   S5 Min/Max return the min/max VALUE, or aDefault when empty (test:
#      (1..20) -> 1/20; [] -> default). Values, not indices -> no tie issue.
#   S6 Copy: same-array -> ERROR (SErrSameArrays); count<0 or beyond src/dst
#      bounds -> ERROR; dst is NOT auto-grown (must pre-hold dstIdx+count)
#      (impl :1301-1322).
#   S7 Concat sums the arg lengths and SKIPS empty args; all-empty -> empty
#      (impl :1347-1369).
#   S8 Sort range = [AIndex .. AIndex+ACount-1] inclusive; ACount<=1 -> no-op;
#      elements outside the range untouched (impl :1059-1065).
#
# ---- Design freeze (P0) ---------------------------------------------------
# * Arrays BY NAME via `declare -n`, `__ta_` local prefix; do NOT pass arrays
#   named __ta_* (nameref self-reference). Contract: indices dense 0..n-1 (the
#   FPC data model); sparse input is undefined (a density check runs only under
#   VERBOSE_KKLASS=debug); TArray.compact is the explicit re-index tool. Assoc
#   arrays (${v@a} contains 'A') are rejected rc=1 (no order to sort).
# * Default comparator = BYTE order via a scoped `local LC_ALL=C` (probed on
#   BOTH bashes: local LC_ALL=C forces strcmp `[[ < ]]` regardless of the
#   ambient locale — `local LC_COLLATE=C` does NOT, LC_ALL overrides it).
#   Locale-collation sort is a documented NON-goal (non-deterministic).
# * Numeric mode (`-n`): 64-bit `(( ))` compare; elements failing the integer
#   shape ^-?[0-9]+$ -> rc=1 (no silent lexicographic fallback); 10# guards the
#   octal trap on leading zeros.
# * Custom comparator `cmpFn a b`: a PLAIN bash function (kklass dispatch in an
#   n log n loop would be catastrophic). Result via RETURN CODE, fork-free:
#     rc 0 = a<b,  rc 1 = a==b,  rc 2 = a>b   (NO stdout; $() would fork/compare).
#   The two built-in modes are INLINED in the merge/search loops. Sign mapping
#   for RESULT_COMPARE: rc {0:-1, 1:0, 2:+1}.
# * Algorithm: bottom-up iterative STABLE mergesort (not FPC introsort — the
#   sorted RESULT is the contract, not the algorithm; FPC leaves equal-order
#   unspecified, so stability is a strictly stronger, documented guarantee).
#
# ---- Return contract (static proc; call DIRECT) ---------------------------
# All members are `static proc` (house finding: a static `func` echoes RESULT
# on every call; `static proc` is silent). They operate on nameref arrays
# and/or set RESULT* globals, so CALL THEM DIRECTLY — a $() subshell loses the
# array mutation and the globals. (Whether the read-only scalar returners
# min/max/indexOf should also body-echo for $() ergonomics is an OPEN P1
# choice, mirroring tregex escape/replace.)
#   RESULT            index | value | (search FoundIndex)
#   RESULT_CANDIDATE  binarySearch CandidateIndex
#   RESULT_COMPARE    binarySearch last-compare sign (-1/0/+1)
# rc: 0 ok/found/true, 1 not-found/false/bad-input, 2 argument error.
# ===========================================================================

# Re-source guard.
if [[ -n "$_TARRAY_SOURCED" ]]; then
    return
fi
declare -g _TARRAY_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TARRAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TARRAY_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Class surface (member types FINAL as of P0 — bodies filled per phase).
# All members `static proc` (silent RESULT/nameref contract, call direct).
# ---------------------------------------------------------------------------
class TArray
    public
        static proc sort          # P1  sort arr [cmp|-n] [start count]
        static proc binarySearch  # P2  binarySearch arr item [cmp] [start count] -> RESULT/_CANDIDATE/_COMPARE
        static proc indexOf       # P2  indexOf arr item [cmp]       -> RESULT (first, -1 miss)
        static proc firstIndexOf  # P2  firstIndexOf arr item [cmp]  -> RESULT
        static proc lastIndexOf   # P2  lastIndexOf arr item [cmp]   -> RESULT
        static proc contains      # P2  contains arr item [cmp]      -> rc 0/1
        static proc min           # P2  min arr [cmp] [default]      -> RESULT
        static proc max           # P2  max arr [cmp] [default]      -> RESULT
        static proc copy          # P3  copy src dst [srcIdx dstIdx] count
        static proc reverse       # P3  reverse src dst              (src==dst safe)
        static proc reverseInPlace # P3 reverseInPlace arr           (bash extra)
        static proc concat        # P3  concat dst src1 [src2 ...]   (array NAMES)
        static proc compact       # P3  compact arr                 (bash extra: sparse->dense)
end

# ---------------------------------------------------------------------------
# P1: sort  —  sort arr [cmp|-n] [start count]
#   Bottom-up iterative STABLE mergesort over the caller's dense indexed array,
#   in place. Comparator selection: '-n' = numeric (int64), a defined FUNCTION
#   name = custom (rc 0/1/2 protocol, §2.4), else = default BYTE order. Range
#   form: sort only [start, start+count-1] (S8); count<=1 -> no-op; elements
#   outside the range untouched. Stability: on a tie the LEFT run wins.
#   rc: 0 ok, 1 rejected (assoc array, or non-integer element in -n mode),
#       2 argument error (missing array name).
#   Numeric mode preserves the ORIGINAL element strings (e.g. '007' stays
#   '007') and compares by value via a parallel normalized-int key array
#   (10# guards the leading-zero octal trap; bare (( 08 )) is a fatal error).
# ---------------------------------------------------------------------------
TArray.sort() {
    local __ta_name="$1"
    if [[ -z "$__ta_name" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "TArray.sort: array name required" >&2
        return 2
    fi
    shift
    local -n __ta_arr="$__ta_name"
    # reject associative arrays (§2.2: no order to sort)
    if [[ "${__ta_arr@a}" == *A* ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "TArray.sort: '$__ta_name' is associative (no order)" >&2
        return 1
    fi
    local __ta_mode="str" __ta_cmp=""
    if [[ "${1:-}" == "-n" ]]; then
        __ta_mode="num"; shift
    elif [[ -n "${1:-}" ]] && declare -F "$1" >/dev/null 2>&1; then
        __ta_mode="fn"; __ta_cmp="$1"; shift
    fi
    local __ta_n=${#__ta_arr[@]}
    local __ta_start="${1:-0}" __ta_count="${2:-}"
    (( __ta_start < 0 )) && __ta_start=0
    (( __ta_start >= __ta_n )) && return 0
    [[ -z "$__ta_count" ]] && __ta_count=$(( __ta_n - __ta_start ))
    (( __ta_start + __ta_count > __ta_n )) && __ta_count=$(( __ta_n - __ta_start ))
    (( __ta_count <= 1 )) && return 0    # S8: nothing to sort

    # extract the range into a dense work array (elements are ORIGINAL strings)
    local -a __ta_w=() __ta_nw=() __ta_buf=() __ta_nbuf=()
    local __ta_i __ta_x
    for (( __ta_i = 0; __ta_i < __ta_count; __ta_i++ )); do
        __ta_w[__ta_i]="${__ta_arr[__ta_start + __ta_i]}"
    done

    if [[ "$__ta_mode" == "num" ]]; then
        # validate integer shape + build the normalized (decimal) key array
        for (( __ta_i = 0; __ta_i < __ta_count; __ta_i++ )); do
            __ta_x="${__ta_w[__ta_i]}"
            if [[ ! "$__ta_x" =~ ^-?[0-9]+$ ]]; then
                [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "TArray.sort -n: non-integer element '$__ta_x'" >&2
                return 1
            fi
            if [[ "$__ta_x" == -* ]]; then __ta_nw[__ta_i]=$(( -1 * 10#${__ta_x#-} ))
            else __ta_nw[__ta_i]=$(( 10#$__ta_x )); fi
        done
    fi

    # str mode: force BYTE order for every [[ < ]] below (P0 idiom); num/fn
    # must NOT be forced (num uses (( )); fn may want the ambient locale).
    if [[ "$__ta_mode" == "str" ]]; then local LC_ALL=C; fi

    local __ta_width=1 __ta_lo __ta_mid __ta_hi __ta_l __ta_r __ta_k __ta_tr
    while (( __ta_width < __ta_count )); do
        __ta_lo=0
        while (( __ta_lo < __ta_count )); do
            __ta_mid=$(( __ta_lo + __ta_width )); (( __ta_mid > __ta_count )) && __ta_mid=$__ta_count
            __ta_hi=$(( __ta_lo + 2 * __ta_width )); (( __ta_hi > __ta_count )) && __ta_hi=$__ta_count
            __ta_l=$__ta_lo; __ta_r=$__ta_mid; __ta_k=$__ta_lo
            while (( __ta_l < __ta_mid && __ta_r < __ta_hi )); do
                case "$__ta_mode" in
                    str) [[ "${__ta_w[__ta_l]}" > "${__ta_w[__ta_r]}" ]] && __ta_tr=1 || __ta_tr=0 ;;
                    num) (( __ta_nw[__ta_l] > __ta_nw[__ta_r] )) && __ta_tr=1 || __ta_tr=0 ;;
                    fn)  "$__ta_cmp" "${__ta_w[__ta_l]}" "${__ta_w[__ta_r]}"; (( $? == 2 )) && __ta_tr=1 || __ta_tr=0 ;;
                esac
                if (( __ta_tr )); then
                    __ta_buf[__ta_k]="${__ta_w[__ta_r]}"; [[ "$__ta_mode" == "num" ]] && __ta_nbuf[__ta_k]="${__ta_nw[__ta_r]}"
                    (( __ta_r++ ))
                else
                    __ta_buf[__ta_k]="${__ta_w[__ta_l]}"; [[ "$__ta_mode" == "num" ]] && __ta_nbuf[__ta_k]="${__ta_nw[__ta_l]}"
                    (( __ta_l++ ))
                fi
                (( __ta_k++ ))
            done
            while (( __ta_l < __ta_mid )); do
                __ta_buf[__ta_k]="${__ta_w[__ta_l]}"; [[ "$__ta_mode" == "num" ]] && __ta_nbuf[__ta_k]="${__ta_nw[__ta_l]}"
                (( __ta_l++, __ta_k++ ))
            done
            while (( __ta_r < __ta_hi )); do
                __ta_buf[__ta_k]="${__ta_w[__ta_r]}"; [[ "$__ta_mode" == "num" ]] && __ta_nbuf[__ta_k]="${__ta_nw[__ta_r]}"
                (( __ta_r++, __ta_k++ ))
            done
            __ta_lo=$__ta_hi
        done
        for (( __ta_i = 0; __ta_i < __ta_count; __ta_i++ )); do
            __ta_w[__ta_i]="${__ta_buf[__ta_i]}"
            [[ "$__ta_mode" == "num" ]] && __ta_nw[__ta_i]="${__ta_nbuf[__ta_i]}"
        done
        __ta_width=$(( __ta_width * 2 ))
    done

    # write the sorted range back into the caller's array
    for (( __ta_i = 0; __ta_i < __ta_count; __ta_i++ )); do
        __ta_arr[__ta_start + __ta_i]="${__ta_w[__ta_i]}"
    done
    return 0
}

# ---------------------------------------------------------------------------
# P2: binarySearch + scan family. Shared internals (plain functions, dynamic
# scope — the caller declares __ta_mode/__ta_cmp/__ta_sign local first).
# ---------------------------------------------------------------------------

# Resolve an optional comparator arg -> __ta_mode (str|num|fn), __ta_cmp,
# __ta_shifted (1 if the arg was a comparator and should be shifted away).
TArray._resolveCmp() {
    __ta_mode="str"; __ta_cmp=""; __ta_shifted=0
    if [[ "$1" == "-n" ]]; then
        __ta_mode="num"; __ta_shifted=1
    elif [[ -n "$1" ]] && declare -F "$1" >/dev/null 2>&1; then
        __ta_mode="fn"; __ta_cmp="$1"; __ta_shifted=1
    fi
}

# 3-way compare -> __ta_sign = -1 (a<b) / 0 (a==b) / +1 (a>b), per __ta_mode.
# str mode assumes the caller set `local LC_ALL=C`. num normalizes with a 10#
# guard (malformed elements -> 0, i.e. undefined-but-crash-free; a precondition
# violation, documented). fn calls __ta_cmp (rc 0/1/2).
TArray._cmp3() {
    case "$__ta_mode" in
        str)
            if   [[ "$1" == "$2" ]]; then __ta_sign=0
            elif [[ "$1" <  "$2" ]]; then __ta_sign=-1
            else __ta_sign=1; fi ;;
        num)
            local __a="$1" __b="$2" __na __nb
            if [[ "$__a" =~ ^-?[0-9]+$ ]]; then [[ "$__a" == -* ]] && __na=$(( -1 * 10#${__a#-} )) || __na=$(( 10#$__a )); else __na=0; fi
            if [[ "$__b" =~ ^-?[0-9]+$ ]]; then [[ "$__b" == -* ]] && __nb=$(( -1 * 10#${__b#-} )) || __nb=$(( 10#$__b )); else __nb=0; fi
            if   (( __na < __nb )); then __ta_sign=-1
            elif (( __na > __nb )); then __ta_sign=1
            else __ta_sign=0; fi ;;
        fn)
            "$__ta_cmp" "$1" "$2"
            case $? in 0) __ta_sign=-1 ;; 2) __ta_sign=1 ;; *) __ta_sign=0 ;; esac ;;
    esac
}

# binarySearch arr item [cmp] [start count]  ->  rc 0 found / 1 not found.
#   RESULT=FoundIndex (-1 miss), RESULT_CANDIDATE=CandidateIndex,
#   RESULT_COMPARE=last-compare sign (S1/S2, FPC loop verbatim; array is sorted
#   under the SAME comparator — garbage-in-garbage-out, like FPC).
TArray.binarySearch() {
    if [[ -z "$1" ]]; then RESULT=-1; RESULT_CANDIDATE=-1; RESULT_COMPARE=0; return 2; fi
    local __ta_name="$1" __ta_item="$2"; shift 2
    local __ta_mode __ta_cmp __ta_shifted
    TArray._resolveCmp "${1:-}"; (( __ta_shifted )) && shift
    local -n __ta_arr="$__ta_name"
    local __ta_n=${#__ta_arr[@]}
    local __ta_start="${1:-0}" __ta_count="${2:-}"
    [[ -z "$__ta_count" ]] && __ta_count=$(( __ta_n - __ta_start ))
    [[ "$__ta_mode" == "str" ]] && local LC_ALL=C
    if (( __ta_n == 0 || __ta_count <= 0 )); then      # S1 (empty / empty range)
        RESULT=-1; RESULT_CANDIDATE=-1; RESULT_COMPARE=0; return 1
    fi
    local __ta_imin=$__ta_start __ta_imax=$(( __ta_start + __ta_count - 1 )) __ta_imid __ta_sign
    while (( __ta_imin < __ta_imax )); do
        __ta_imid=$(( __ta_imin + ( (__ta_imax - __ta_imin) >> 1 ) ))
        TArray._cmp3 "${__ta_arr[__ta_imid]}" "$__ta_item"
        RESULT_COMPARE=$__ta_sign
        if (( __ta_sign < 0 )); then
            __ta_imin=$(( __ta_imid + 1 ))
        else
            __ta_imax=$__ta_imid
            if (( __ta_sign == 0 )); then RESULT=$__ta_imid; RESULT_CANDIDATE=$__ta_imid; return 0; fi
        fi
    done
    TArray._cmp3 "${__ta_arr[__ta_imin]}" "$__ta_item"      # deferred equality (imin==imax)
    RESULT_COMPARE=$__ta_sign; RESULT_CANDIDATE=$__ta_imin
    if (( __ta_sign == 0 )); then RESULT=$__ta_imin; return 0; else RESULT=-1; return 1; fi
}

# firstIndexOf arr item [cmp]  ->  RESULT = first matching index, or -1; rc 0/1.
TArray.firstIndexOf() {
    if [[ -z "$1" ]]; then RESULT=-1; return 2; fi
    local __ta_name="$1" __ta_item="$2"; shift 2
    local __ta_mode __ta_cmp __ta_shifted
    TArray._resolveCmp "${1:-}"
    local -n __ta_arr="$__ta_name"
    [[ "$__ta_mode" == "str" ]] && local LC_ALL=C
    local __ta_n=${#__ta_arr[@]} __ta_i __ta_sign
    for (( __ta_i = 0; __ta_i < __ta_n; __ta_i++ )); do
        TArray._cmp3 "${__ta_arr[__ta_i]}" "$__ta_item"
        if (( __ta_sign == 0 )); then RESULT=$__ta_i; return 0; fi
    done
    RESULT=-1; return 1
}

# indexOf == firstIndexOf (S3, impl :1371).
TArray.indexOf() { TArray.firstIndexOf "$@"; }

# lastIndexOf arr item [cmp]  ->  RESULT = last matching index, or -1; rc 0/1.
TArray.lastIndexOf() {
    if [[ -z "$1" ]]; then RESULT=-1; return 2; fi
    local __ta_name="$1" __ta_item="$2"; shift 2
    local __ta_mode __ta_cmp __ta_shifted
    TArray._resolveCmp "${1:-}"
    local -n __ta_arr="$__ta_name"
    [[ "$__ta_mode" == "str" ]] && local LC_ALL=C
    local __ta_n=${#__ta_arr[@]} __ta_i __ta_sign
    for (( __ta_i = __ta_n - 1; __ta_i >= 0; __ta_i-- )); do
        TArray._cmp3 "${__ta_arr[__ta_i]}" "$__ta_item"
        if (( __ta_sign == 0 )); then RESULT=$__ta_i; return 0; fi
    done
    RESULT=-1; return 1
}

# contains arr item [cmp]  ->  rc 0 present / 1 absent (RESULT = the found index).
TArray.contains() { TArray.firstIndexOf "$@"; }

# min arr [cmp] [default]  ->  RESULT = min VALUE, or default on empty; rc 0/1.
TArray.min() {
    if [[ -z "$1" ]]; then RESULT=""; return 2; fi
    local __ta_name="$1"; shift
    local __ta_mode __ta_cmp __ta_shifted
    TArray._resolveCmp "${1:-}"; (( __ta_shifted )) && shift
    local __ta_default="${1:-}"
    local -n __ta_arr="$__ta_name"
    local __ta_n=${#__ta_arr[@]}
    if (( __ta_n == 0 )); then RESULT="$__ta_default"; return 1; fi
    [[ "$__ta_mode" == "str" ]] && local LC_ALL=C
    local __ta_best="${__ta_arr[0]}" __ta_i __ta_sign
    for (( __ta_i = 1; __ta_i < __ta_n; __ta_i++ )); do
        TArray._cmp3 "${__ta_arr[__ta_i]}" "$__ta_best"
        (( __ta_sign < 0 )) && __ta_best="${__ta_arr[__ta_i]}"
    done
    RESULT="$__ta_best"; return 0
}

# max arr [cmp] [default]  ->  RESULT = max VALUE, or default on empty; rc 0/1.
TArray.max() {
    if [[ -z "$1" ]]; then RESULT=""; return 2; fi
    local __ta_name="$1"; shift
    local __ta_mode __ta_cmp __ta_shifted
    TArray._resolveCmp "${1:-}"; (( __ta_shifted )) && shift
    local __ta_default="${1:-}"
    local -n __ta_arr="$__ta_name"
    local __ta_n=${#__ta_arr[@]}
    if (( __ta_n == 0 )); then RESULT="$__ta_default"; return 1; fi
    [[ "$__ta_mode" == "str" ]] && local LC_ALL=C
    local __ta_best="${__ta_arr[0]}" __ta_i __ta_sign
    for (( __ta_i = 1; __ta_i < __ta_n; __ta_i++ )); do
        TArray._cmp3 "${__ta_arr[__ta_i]}" "$__ta_best"
        (( __ta_sign > 0 )) && __ta_best="${__ta_arr[__ta_i]}"
    done
    RESULT="$__ta_best"; return 0
}

# ---------------------------------------------------------------------------
# P3: copy / reverse / concat + reverseInPlace / compact (bash extras).
# Pure array mutators — they set no RESULT (call directly; a $() subshell would
# discard the array writes). Reserved local names: don't pass arrays named
# __ta_src / __ta_dst / __ta_tmp / __ta_cur / __ta_arr (nameref self-reference).
# ---------------------------------------------------------------------------

# reverse src dst  ->  dst = src reversed; src left untouched. Built through a
# TEMP buffer so src==dst (in-place) is SAFE (S4, FPC impl :1324-1339). rc 0/2.
TArray.reverse() {
    if [[ -z "$1" || -z "$2" ]]; then return 2; fi
    local -n __ta_src="$1"
    local __ta_n=${#__ta_src[@]} __ta_i __ta_j
    local -a __ta_tmp=()
    __ta_j=$(( __ta_n - 1 ))
    for (( __ta_i = 0; __ta_i < __ta_n; __ta_i++ )); do
        __ta_tmp[__ta_j]="${__ta_src[__ta_i]}"
        (( __ta_j-- ))
    done
    local -n __ta_dst="$2"
    __ta_dst=( "${__ta_tmp[@]}" )
    return 0
}

# reverseInPlace arr  ->  reverse arr in place (bash extra) = reverse arr arr.
TArray.reverseInPlace() {
    if [[ -z "$1" ]]; then return 2; fi
    TArray.reverse "$1" "$1"
}

# copy src dst [srcIdx dstIdx] count  ->  copy `count` elements src[srcIdx..]
# into dst[dstIdx..]. S6 (FPC impl :1301-1322): same array -> ERROR; count<0 or
# beyond src/dst bounds -> ERROR; dst is NOT auto-grown (must already hold
# dstIdx+count). rc 0 ok / 2 argument error.
TArray.copy() {
    if [[ -z "$1" || -z "$2" ]]; then return 2; fi
    local __ta_srcname="$1" __ta_dstname="$2"; shift 2
    [[ "$__ta_srcname" == "$__ta_dstname" ]] && return 2          # SErrSameArrays
    local __ta_srcidx __ta_dstidx __ta_count
    if (( $# == 1 )); then __ta_srcidx=0; __ta_dstidx=0; __ta_count="$1"
    elif (( $# == 3 )); then __ta_srcidx="$1"; __ta_dstidx="$2"; __ta_count="$3"
    else return 2; fi
    [[ "$__ta_srcidx" =~ ^[0-9]+$ && "$__ta_dstidx" =~ ^[0-9]+$ && "$__ta_count" =~ ^-?[0-9]+$ ]] || return 2
    local -n __ta_src="$__ta_srcname" __ta_dst="$__ta_dstname"
    local __ta_sn=${#__ta_src[@]} __ta_dn=${#__ta_dst[@]}
    if (( __ta_count < 0 || __ta_count > __ta_sn - __ta_srcidx || __ta_count > __ta_dn - __ta_dstidx )); then
        return 2                                                  # ErrorArgumentOutOfRange
    fi
    local __ta_i
    for (( __ta_i = 0; __ta_i < __ta_count; __ta_i++ )); do
        __ta_dst[__ta_dstidx + __ta_i]="${__ta_src[__ta_srcidx + __ta_i]}"
    done
    return 0
}

# concat dst src1 [src2 ...]  ->  dst = src1 ++ src2 ++ ...  (array NAMES).
# Empty sources contribute nothing (S7, FPC impl :1347-1369). Built through a
# temp, so dst may also be one of the sources. rc 0 / 2.
TArray.concat() {
    if [[ -z "$1" ]]; then return 2; fi
    local __ta_dstname="$1"; shift
    local -a __ta_tmp=()
    local __ta_s
    for __ta_s in "$@"; do
        [[ -z "$__ta_s" ]] && continue
        local -n __ta_cur="$__ta_s"
        __ta_tmp+=( "${__ta_cur[@]}" )
        unset -n __ta_cur
    done
    local -n __ta_dst="$__ta_dstname"
    __ta_dst=( "${__ta_tmp[@]}" )
    return 0
}

# compact arr  ->  re-index a sparse array to dense 0..n-1, order preserved
# (bash extra; the ONE place holes are dropped — §2.1). rc 0 / 2.
TArray.compact() {
    if [[ -z "$1" ]]; then return 2; fi
    local -n __ta_arr="$1"
    __ta_arr=( "${__ta_arr[@]}" )
    return 0
}

# Finalize the class.
build TArray
