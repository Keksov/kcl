#!/bin/bash

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TSTRINGLIST_SOURCED:-}" ]]; then
    return
fi
declare -g _TSTRINGLIST_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR)
TSTRINGLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TSTRINGLIST_DIR/../../kklass/kklass_pascal.sh"
source "$TSTRINGLIST_DIR/../tlist/tlist.sh"

# ---------------------------------------------------------------------------
# TStringList: a string list with sorting, duplicate policies and
# case-(in)sensitive comparison (Free Pascal's Classes.TStringList).
# Inherits TList — `class TStringList : TList`.
#
# Pascal DSL form: the class STRUCTURE (interface) first, then the method
# BODIES as real bash functions, then `build TStringList`.
#
# - `override` marks every method that replaces a TList implementation
#   (build errors if the ancestor doesn't actually define it — typo guard).
# - The constructor chains to the parent with `inherited` (rewritten to
#   `parent.constructor "$@"`), then sets the TStringList-specific fields.
# - Insert delegates to the parent for unsorted lists via `inherited Insert`.
# - CompareStrings returns 0 (equal) / 1 (str1 < str2) / 2 (str1 > str2) via
#   RESULT; duplicates policy is one of dupAccept | dupIgnore | dupError.
# ---------------------------------------------------------------------------
class TStringList : TList
    public
        constructor Create
        var case_sensitive
        property sorted read sorted write _setSorted
        proc           _setSorted
        var duplicates
        override func  IndexOf
        override proc  Sort
        override func  Find
        override proc  Assign
        proc           AddStrings
        override func  Remove
        override func  Add
        override proc  Insert
        func           CompareStrings
end

# ---- method bodies (real bash functions; extracted by `build`) --------------

TStringList.Create() {
    # Call parent constructor
    inherited

    # Initialize TStringList-specific properties
    case_sensitive=false
    sorted=false
    duplicates="dupAccept"
}

# Get and Put are NOT overridden here — TList.Get/Put are real (bounds-checked
# indexed access) and inherited unchanged. (Removed the duplicate overrides.)

TStringList._setSorted() {
    # FPC `TStringList.SetSorted`: `if FSorted <> Value then begin if Value then
    # Sort; FSorted := Value end`. Before this (finding G1-04) `sorted` was a
    # plain field, so `L.sorted = true` on a populated list left the data
    # unsorted while Find and the sorted Add ran binary searches over it and
    # returned nonsense. `$this.Sort` is the virtual member, and it sets the
    # stored flag itself; the assignment here covers the false case and the
    # already-true case. Only the two boolean tokens are accepted (G1-16
    # applied to this unit): anything else is a malformed call, rc 2, no change.
    case "${1:-}" in
        true)
            if [[ "$sorted" != "true" ]]; then
                $this.Sort
            fi
            sorted=true ;;
        false)
            sorted=false ;;
        *)
            kk.debug "Error: TStringList.sorted: '${1:-}' is not 'true' or 'false'"
            return 2 ;;
    esac
}

TStringList.IndexOf() {
    # FPC: `if not Sorted then Result := inherited IndexOf(S) else if not
    # Find(S, Result) then Result := -1` — a sorted list is searched by BINARY
    # search, not linearly (G1-03: 20 lookups over 300 items cost 1975 ms
    # linearly against 124 ms via Find). The linear branch compares through the
    # plain `_cmpCore` instead of dispatching `$this.CompareStrings` per
    # element; see the note above _cmpCore about that trade.
    local item="$1"
    local items_var="${__inst__}_items"
    local current_count="$count"
    if [[ "$sorted" == "true" ]]; then
        local __tsl_pos __tsl_hit
        if TStringList._findPos "$item" "$case_sensitive" "$items_var" "$current_count"; then
            RESULT="$__tsl_hit"
        else
            RESULT="-1"
        fi
    else
        local i rc
        declare -n items_ref="$items_var"
        RESULT="-1"
        for (( i = 0; i < current_count; i++ )); do
            rc=0
            TStringList._cmpCore "${items_ref[$i]}" "$item" "$case_sensitive" || rc=$?
            if (( rc == 1 )); then
                RESULT="$i"
                break
            fi
        done
    fi
}

TStringList.Sort() {
    # Delegates the O(n log n) STABLE mergesort to TArray.sort over the [0,count)
    # range (leaving any capacity padding untouched), exactly as FPC's generics
    # TList<T>.Sort delegates to TArrayHelper.Sort(FItems, cmp, 0, Count). The
    # comparator is _sortcmp (the CompareStrings core WITHOUT kklass dispatch),
    # so equal keys keep input order — byte-identical to the old stable bubble
    # sort, ~2 orders faster. case_sensitive is captured for the shim; `sorted`
    # is set unconditionally afterward (incl. empty/single lists).
    __tsl_sortcs="$case_sensitive"
    TArray.sort "${this}_items" TStringList._sortcmp 0 "$count"
    sorted=true
}

TStringList.Find() {
    # FPC `Find(S, out Index): Boolean` over a SORTED list. The bash contract
    # (pinned by tests 007/015/016 since before the review) packs both halves
    # into RESULT: a hit is the index, a miss is `-insertionPoint - 1`.
    # Unsorted -> rc 1 (FPC's Find is only defined for sorted lists).
    local item="$1"
    if [[ "$sorted" != "true" ]]; then
        kk.debug "Error: List must be sorted for Find operation"
        return 1
    fi
    local __tsl_pos __tsl_hit
    if TStringList._findPos "$item" "$case_sensitive" "${__inst__}_items" "$count"; then
        RESULT="$__tsl_hit"
    else
        RESULT=$(( -__tsl_pos - 1 ))
    fi
}

TStringList.Assign() {
    # FPC `TStringList.Assign` copies FSorted/FCaseSensitive/FDuplicates from a
    # TStringList source and then runs the inherited TStrings.Assign
    # (Clear + AddStrings). Two findings live here:
    #   G1-10 the flags were NOT copied, so a `sorted = true` destination
    #         received unsorted data and went on claiming to be sorted — Find
    #         then missed items that were present.
    #   G1-11 the source count came from `$($source.count)`, i.e. one FORK per
    #         call, and an invalid source name was never rejected.
    # Copying the source's items verbatim is equivalent to FPC's per-item Add
    # loop here: the flags are taken from the same source, so the source's
    # element order already satisfies them.
    local source="$1"
    if ! TStringList._isStringList "$source"; then
        kk.debug "Error: TStringList.Assign: '$source' is not a TStringList"
        return 1
    fi
    local idx
    declare -n source_data_ref="${source}_data"
    local source_count="${source_data_ref[count]:-0}"
    local source_items_var="${source}_items"
    declare -n source_items_ref="$source_items_var"
    local assign_temp=()
    for (( idx = 0; idx < source_count; idx++ )); do
        assign_temp[$idx]="${source_items_ref[$idx]}"
    done

    $this.Clear

    # Flags first (FPC order), then the payload — `sorted` is written raw, NOT
    # through the setter: the data that follows is already in the source's
    # order, so re-sorting would be wasted work.
    case_sensitive="${source_data_ref[case_sensitive]:-false}"
    duplicates="${source_data_ref[duplicates]:-dupAccept}"
    sorted="${source_data_ref[sorted]:-false}"

    declare -n items_ref="${__inst__}_items"
    for (( idx = 0; idx < source_count; idx++ )); do
        items_ref[$idx]="${assign_temp[$idx]}"
    done

    # Set destination count
    $this.property count = "$source_count"
}

TStringList.AddStrings() {
    # G1-11: `$($source.count)` forked once per call, and a nonexistent source
    # produced a kklass "command not found" on stderr followed by rc 0.
    local source="$1"
    if ! TStringList._isStringList "$source"; then
        kk.debug "Error: TStringList.AddStrings: '$source' is not a TStringList"
        return 1
    fi
    declare -n source_data_ref="${source}_data"
    local source_count="${source_data_ref[count]:-0}"
    if (( source_count == 0 )); then
        return 0
    fi

    local source_items_var="${source}_items"
    local items_var="${__inst__}_items"
    declare -n source_items_ref="$source_items_var"
    declare -n items_ref="$items_var"

    if [[ "$sorted" != "true" && "$duplicates" == "dupAccept" ]]; then
        local current_count="$count"
        local new_count=$((current_count + source_count))
        if (( new_count > capacity )); then
            $__inst__.property capacity = "$new_count" >/dev/null
        fi

        local copied_items=()
        local idx
        for (( idx = 0; idx < source_count; idx++ )); do
            copied_items[$idx]="${source_items_ref[$idx]}"
        done
        for (( idx = 0; idx < source_count; idx++ )); do
            items_ref[$((current_count + idx))]="${copied_items[$idx]}"
        done

        $__inst__.property count = "$new_count" >/dev/null
        return 0
    fi

    # Add each item through Add when sorting or duplicate policy must be enforced
    local idx
    for (( idx = 0; idx < source_count; idx++ )); do
        local item_to_add
        item_to_add="${source_items_ref[$idx]}"
        $this.Add "$item_to_add" >/dev/null
    done
}

TStringList.Remove() {
    local i                     # X-LOCALS (G1-08)
    local item="$1"
    local index
    $this.IndexOf "$item" >/dev/null
    index=$RESULT
    if [[ "$index" != "-1" ]]; then
        local current_count=$count
        if (( index < 0 || index >= current_count )); then
            kk.debug "Error: Index out of bounds"
            return 1
        fi
        local items_var="${__inst__}_items"
        declare -n items_ref="$items_var"
        # Shift elements left from index+1
        for (( i = index; i < current_count - 1; i++ )); do
            items_ref[$i]="${items_ref[$((i+1))]}"
        done
        # Clear the last element
        unset "items_ref[$((current_count-1))]"
        local new_count=$((current_count - 1))
        $__inst__.property count = "$new_count"
        RESULT="$index"
    else
        RESULT="-1"
    fi
}

TStringList.Add() {
    # FPC:
    #     if not Sorted then Result := FCount
    #     else if Find(S, Result) then
    #        case Duplicates of dupIgnore: Exit; dupError: Error end;
    #     InsertItem(Result, S);
    # Three findings converge here:
    #   G1-03 the Duplicates policy was applied to UNSORTED lists too (FPC does
    #         not), and the check ran a full kklass-dispatched IndexOf over the
    #         whole list on EVERY Add — 300 Adds cost 16.6 s against 0.12 s for
    #         the same Adds on a TList. Unsorted Add is now O(1) and the sorted
    #         one is one binary search of plain function calls.
    #   G1-05 the dupIgnore branch did `RESULT=…; return`, and an explicit
    #         return skips the func trailer, so `kk._invoke` put the CALLER's
    #         RESULT back: the existing index never reached the caller.
    #   G1-04 the binary search only makes sense because `sorted = true` now
    #         really sorts.
    local j                     # X-LOCALS (G1-08)
    local item="$1"
    local current_count="$count"
    local items_var="${__inst__}_items"
    declare -n items_ref="$items_var"
    local insert_index=$current_count

    if [[ "$sorted" == "true" ]]; then
        local __tsl_pos __tsl_hit
        if TStringList._findPos "$item" "$case_sensitive" "$items_var" "$current_count"; then
            if [[ "$duplicates" == "dupIgnore" ]]; then
                # kk._return, not a bare RESULT= (the trailer trap, G1-05).
                kk._return "$__tsl_hit"
                return 0
            elif [[ "$duplicates" == "dupError" ]]; then
                kk.debug "Error: Duplicate item not allowed"
                return 1
            fi
            # dupAccept: fall through and insert at the same position.
        fi
        insert_index=$__tsl_pos
    fi

    # Grow capacity if needed
    if (( current_count >= capacity )); then
        $__inst__.call Grow
    fi

    if (( insert_index < current_count )); then
        # Shift elements to the right to make room
        for (( j = current_count; j > insert_index; j-- )); do
            items_ref[$j]="${items_ref[$((j-1))]}"
        done
    fi

    items_ref[$insert_index]="$item"
    local new_count=$((current_count + 1))
    $__inst__.property count = "$new_count"
    RESULT="$insert_index"
}

TStringList.Insert() {
    local index="$1"
    local item="${2:-}"
    if [[ "$sorted" == "true" ]]; then
        kk.debug "Error: Cannot insert into sorted list"
        return 1
    fi
    # Call parent Insert for unsorted lists
    inherited Insert "$index" "$item"
}

# Plain comparison CORE (NOT a class member — like math._num_cmp). Single
# source of truth for the string ordering, callable WITHOUT kklass dispatch so
# the delegated Sort is fast. rc protocol = TArray cmpFn: 0 = a<b, 1 = a==b,
# 2 = a>b.  $1 a, $2 b, $3 case_sensitive ("true" = exact, else fold both to
# lower). Ambient-locale [[ < ]] (NOT LC_ALL=C) — verbatim old CompareStrings.
TStringList._cmpCore() {
    local __a __b
    if [[ "$3" == "true" ]]; then __a="$1"; __b="$2"; else __a="${1,,}"; __b="${2,,}"; fi
    # X-SETE (D7): `[[ ... ]] && return 0` returns 1 when the test is false, and
    # under `set -e` that aborts the caller before the next line is reached.
    if [[ "$__a" < "$__b" ]]; then return 0; fi
    if [[ "$__a" == "$__b" ]]; then return 1; fi
    return 2
}

# Binary search CORE over the sorted region [0,count) — a plain function, so a
# lookup costs one bash call per probe instead of a kklass CompareStrings
# dispatch (G1-03). Shared by Find, IndexOf and the sorted Add, which is why
# they can no longer disagree about where an item belongs.
#   $1 item, $2 case_sensitive, $3 the items array NAME, $4 count
# Out (the caller declares them local): __tsl_pos = lower bound = the insertion
# point, __tsl_hit = the index of an equal element or -1. rc 0 found / 1 not.
# The loop is the textbook lower bound, so on a hit __tsl_hit == __tsl_pos ==
# the FIRST index of the equal run (FPC's Find with dupAccept returns exactly
# that; with dupIgnore/dupError the run cannot be longer than one element).
TStringList._findPos() {
    local -n __tsl_it="$3"
    local __tsl_lo=0 __tsl_hi="$4" __tsl_mid __tsl_rc
    __tsl_hit=-1
    while (( __tsl_lo < __tsl_hi )); do
        __tsl_mid=$(( (__tsl_lo + __tsl_hi) / 2 ))
        __tsl_rc=0
        TStringList._cmpCore "${__tsl_it[__tsl_mid]}" "$1" "$2" || __tsl_rc=$?
        if (( __tsl_rc == 0 )); then          # element < item -> go right
            __tsl_lo=$(( __tsl_mid + 1 ))
        else                                  # element >= item -> go left
            __tsl_hi=$__tsl_mid
            if (( __tsl_rc == 1 )); then __tsl_hit=$__tsl_mid; fi
        fi
    done
    __tsl_pos=$__tsl_lo
    if (( __tsl_hit >= 0 )); then
        return 0
    fi
    return 1
}

# Is $1 a live TStringList (or a descendant)? Operand check for Assign/
# AddStrings — decision R5: the CLASS decides, not the mere presence of an
# `_items` array (a TList, a TObjectList or a THashSet all have one).
# G1-11: a nonexistent name used to reach `$($source.count)` and produce a
# kklass "command not found" plus rc 0.
TStringList._isStringList() {
    local __tsl_c="${1:-}" __tsl_cv
    [[ -n "$__tsl_c" ]] || return 1
    __tsl_cv="${__tsl_c}_class"
    __tsl_c="${!__tsl_cv:-}"
    while [[ -n "$__tsl_c" ]]; do
        if [[ "$__tsl_c" == "TStringList" ]]; then return 0; fi
        __tsl_cv="${__tsl_c}_parent_class"
        __tsl_c="${!__tsl_cv:-}"
    done
    return 1
}

# Comparator shim handed to TArray.sort (cmpFn form). Reads the case-sensitivity
# captured by Sort into __tsl_sortcs, so a comparison is one plain-function call
# — NOT a per-element kklass CompareStrings dispatch (the point of delegating).
TStringList._sortcmp() {
    # The comparator answers with its exit STATUS (0/1/2), so a bare call would
    # abort the caller under `set -e`; capture it and re-return (X-SETE, D7).
    local __rc=0
    TStringList._cmpCore "$1" "$2" "$__tsl_sortcs" || __rc=$?
    return $__rc
}

# CompareStrings (public method, unchanged contract) — now a thin wrapper over
# the core, mapping its rc to the historical RESULT protocol: 0 = equal,
# 1 = str1 < str2, 2 = str1 > str2.
TStringList.CompareStrings() {
    # X-SETE (D7): `_cmpCore` carries its ANSWER in the exit status (0/1/2), so
    # a bare call aborted the caller under `set -e` for every "equal" and
    # "greater" comparison — with bash's own `pop_var_context` noise on top.
    # Found by the P2 contract assertion, in the same class as the four cases
    # P1 fixed (TArray._cmp3, the sort merge loop, _sortcmp, TRegEx._match1).
    local __tsl_rc=0
    TStringList._cmpCore "$1" "$2" "$case_sensitive" || __tsl_rc=$?
    case $__tsl_rc in
        0) RESULT=1 ;;   # str1 < str2
        1) RESULT=0 ;;   # equal
        2) RESULT=2 ;;   # str1 > str2
    esac
}

# Finalize: extract the bodies above into the TStringList class (the override
# guard verifies each `override` against TList) and finalize the runtime.
build TStringList
